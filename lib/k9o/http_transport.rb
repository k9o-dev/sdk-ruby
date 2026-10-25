# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative 'multipart'

module K9o
  # Retry + backoff policy. Applied to idempotent methods
  # (GET/HEAD/OPTIONS/DELETE) on transient failures only (transport error /
  # 502 / 503 / 504 / 429); semantic 4xx and non-idempotent methods are
  # never retried.
  class RetryConfig
    attr_reader :max_retries, :backoff, :initial_delay_ms, :max_delay_ms

    # backoff: 'exponential' | 'linear' | 'none'
    def initialize(max_retries: 3, backoff: 'exponential', initial_delay_ms: 100, max_delay_ms: 5000)
      @max_retries = max_retries
      @backoff = backoff
      @initial_delay_ms = initial_delay_ms
      @max_delay_ms = max_delay_ms
    end

    def self.default
      new
    end
  end

  # Per-instance HTTP config bound on K9oClient.
  class HttpClientConfig
    attr_reader :base_url, :api_key, :org_slug, :project_slug, :default_headers, :http_client, :retry_config,
                :region_mutex
    # Cached regional origin (see K9o::Region); nil until a definite answer.
    attr_accessor :regional_origin

    def initialize(base_url:, api_key: nil, org_slug: nil, project_slug: nil, default_headers: {}, http_client: nil,
                   retry_config: nil)
      @base_url = base_url
      @api_key = api_key
      @org_slug = org_slug
      @project_slug = project_slug
      @default_headers = default_headers.freeze
      @http_client = http_client
      @retry_config = retry_config
      @region_mutex = Mutex.new
      @regional_origin = nil
    end
  end

  # HTTP transport using Net::HTTP stdlib.
  module HttpTransport
    RETRYABLE_METHODS = %w[GET HEAD OPTIONS DELETE].freeze
    RETRYABLE_STATUS = [502, 503, 504, 429].freeze

    module_function

    # Issue a request with retry on transient failures. Idempotent methods
    # are retried with backoff per config.retry_config;
    # semantic / non-idempotent failures raise immediately.
    #
    # `headers:` carries per-call header overrides on top of
    # `config.default_headers` — e.g. `client.kibo.vault.secrets.reveal`'s
    # single-use `X-K9O-Reveal-Challenge` header, which is per-request rather
    # than a client-wide default.
    #
    # `multipart:` is an array of parts (see K9o::Multipart) sent as a
    # multipart/form-data body instead of JSON.
    #
    # `authenticated: false` sends NO credential: no api_key bearer, and any
    # authorization / cookie header from `default_headers` or `headers:` is dropped.
    def request(config:, method:, path:, body: nil, query: nil, headers: nil, authenticated: true, multipart: nil)
      retry_with_backoff(method, config.retry_config || RetryConfig.default) do
        request_once(config: config, method: method, path: path, body: body, query: query, headers: headers,
                     authenticated: authenticated, multipart: multipart)
      end
    end

    # Run a block with retry-with-backoff. Extracted so the retry policy is
    # unit-testable without a live HTTP round-trip.
    def retry_with_backoff(method, retry_config)
      last_error = nil
      attempt = 0
      while attempt <= retry_config.max_retries
        begin
          return yield
        rescue KError => e
          last_error = e
          raise e if attempt == retry_config.max_retries || !retryable?(e, method)

          delay_ms = compute_delay_ms(retry_config, attempt)
          sleep(delay_ms / 1000.0) if delay_ms > 0
          attempt += 1
        end
      end
      raise last_error
    end

    def retryable?(error, method)
      return false unless RETRYABLE_METHODS.include?(method.to_s.upcase)
      return true if error.code == 'K9O_UPSTREAM_UNAVAILABLE'

      RETRYABLE_STATUS.include?(error.status)
    end

    def compute_delay_ms(config, attempt)
      return 0 if config.backoff == 'none'

      base = if config.backoff == 'linear'
               config.initial_delay_ms * (attempt + 1)
             else
               config.initial_delay_ms * (2**attempt)
             end
      capped = [base, config.max_delay_ms].min
      jitter = capped * 0.25 * (rand * 2 - 1)
      [(capped + jitter).to_i, 0].max
    end

    # Single-attempt request. `request` wraps this in retry-with-backoff.
    def request_once(config:, method:, path:, body: nil, query: nil, headers: nil, authenticated: true, multipart: nil)
      url = "#{Region.resolve_origin(config).sub(%r{/\z}, '')}#{path}"
      if query && !query.empty?
        url += '?' + URI.encode_www_form(query)
      end

      uri = URI.parse(url)
      http = config.http_client || ::Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = 30

      req_class = case method.to_s.upcase
                  when 'GET' then ::Net::HTTP::Get
                  when 'POST' then ::Net::HTTP::Post
                  when 'PATCH' then ::Net::HTTP::Patch
                  when 'PUT' then ::Net::HTTP::Put
                  when 'DELETE' then ::Net::HTTP::Delete
                  else raise ArgumentError, "Unsupported method: #{method}"
                  end

      req = req_class.new(uri.request_uri)
      req['accept'] = 'application/json'
      config.default_headers.each { |k, v| req[k] = v }
      req['x-k9o-project-slug'] = config.project_slug if config.project_slug
      headers&.each { |k, v| req[k] = v }
      req['x-k9o-org-slug'] = config.org_slug if config.org_slug
      if authenticated
        req['authorization'] = "Bearer #{config.api_key}" if config.api_key
      else
        req.delete('authorization')
        req.delete('cookie')
      end

      if multipart
        # multipart/form-data: the encoder sets the boundary; never force JSON.
        data, content_type = Multipart.encode(multipart)
        req['content-type'] = content_type
        req.body = data
      elsif body
        req['content-type'] = 'application/json'
        req.body = JSON.dump(body)
      end

      begin
        response = http.request(req)
      rescue => e
        raise KError.new(
          code: 'K9O_UPSTREAM_UNAVAILABLE',
          message: "Network error reaching #{url}: #{e.message}",
          context: { url: url },
          recommendation: 'Check connectivity to the gateway; retry with backoff if transient.'
        )
      end

      status = response.code.to_i

      return Envelope.new(data: nil, meta: Meta.new) if status == 204

      begin
        parsed = JSON.parse(response.body || '')
      rescue JSON::ParserError => e
        raise KError.new(
          code: 'K9O_INTERNAL_ERROR',
          message: "Failed to parse JSON response from #{url}: #{e.message}",
          context: { url: url, status: status },
          status: status
        )
      end

      if status >= 200 && status < 300
        unless parsed.is_a?(Hash) && parsed.key?('data') && parsed.key?('meta')
          raise KError.new(
            code: 'K9O_INTERNAL_ERROR',
            message: "Malformed envelope from #{url}: expected {data, meta}",
            context: { url: url, status: status },
            status: status
          )
        end
        return Envelope.from_wire(parsed)
      end

      if parsed.is_a?(Hash) && parsed['code'].is_a?(String) && parsed['message'].is_a?(String)
        raise KError.from_wire(parsed, status)
      end

      raise KError.new(
        code: 'K9O_INTERNAL_ERROR',
        message: "Upstream returned #{status} with non-KError body",
        context: { url: url, status: status },
        status: status
      )
    end

    # Open an SSE stream and return an Enumerator yielding decoded `data:`
    # payloads (parsed JSON). Used by Compute LLMs #invoke_stream
    # and the Realtime #subscribe SSE transport. The [DONE]
    # sentinel terminates the stream; non-2xx raises KError before any
    # event is yielded.
    #
    # Per the Ruby async-iteration idiom is Enumerator — caller
    # writes `client.compute.llms.invoke_stream(...).each { |chunk| ... }`.
    def stream_sse(config:, method:, path:, body: nil, query: nil)
      url = "#{Region.resolve_origin(config).sub(%r{/\z}, '')}#{path}"
      if query && !query.empty?
        url += '?' + URI.encode_www_form(query)
      end
      uri = URI.parse(url)

      Enumerator.new do |yielder|
        http = config.http_client || ::Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.read_timeout = 300

        req_class = case method.to_s.upcase
                    when 'GET' then ::Net::HTTP::Get
                    when 'POST' then ::Net::HTTP::Post
                    else raise ArgumentError, "Unsupported stream method: #{method}"
                    end
        req = req_class.new(uri.request_uri)
        req['accept'] = 'text/event-stream'
        config.default_headers.each { |k, v| req[k] = v }
        req['x-k9o-project-slug'] = config.project_slug if config.project_slug
        req['x-k9o-org-slug'] = config.org_slug if config.org_slug
        req['authorization'] = "Bearer #{config.api_key}" if config.api_key
        if body
          req['content-type'] = 'application/json'
          req.body = JSON.dump(body)
        end

        begin
          http.request(req) do |response|
            status = response.code.to_i
            if status < 200 || status >= 300
              raw = +''
              response.read_body { |c| raw << c }
              parsed = begin
                JSON.parse(raw)
              rescue JSON::ParserError
                nil
              end
              if parsed.is_a?(Hash) && parsed['code'].is_a?(String) && parsed['message'].is_a?(String)
                raise KError.from_wire(parsed, status)
              end

              raise KError.new(
                code: 'K9O_INTERNAL_ERROR',
                message: "Upstream returned #{status} opening stream",
                context: { url: url, status: status },
                status: status
              )
            end

            buffer = +''
            data_lines = []
            flush = lambda do
              return true if data_lines.empty?

              payload = data_lines.join("\n")
              data_lines = []
              return false if payload == '[DONE]'

              begin
                yielder << JSON.parse(payload)
              rescue JSON::ParserError => e
                raise KError.new(code: 'K9O_INTERNAL_ERROR', message: "failed to decode stream chunk: #{e.message}")
              end
              true
            end

            response.read_body do |chunk|
              buffer << chunk
              while (idx = buffer.index("\n"))
                line = buffer.slice!(0..idx).chomp
                if line.empty?
                  break unless flush.call
                elsif line.start_with?(':')
                  next
                elsif line.start_with?('data:')
                  rest = line[5..]
                  rest = rest[1..] if rest.start_with?(' ')
                  data_lines << rest
                end
              end
            end
            flush.call
          end
        rescue KError
          raise
        rescue StandardError => e
          raise KError.new(
            code: 'K9O_UPSTREAM_UNAVAILABLE',
            message: "Network error reaching #{url}: #{e.message}",
            context: { url: url },
            recommendation: 'Check connectivity to the gateway; retry with backoff if transient.'
          )
        end
      end
    end
  end
end
