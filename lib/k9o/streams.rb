# frozen_string_literal: true

module K9o
  # User data streams namespace: k9o.streams.*.
  #
  # Routes under /@<slug>/data-streams/user. Publish needs project admin; subscribe and replay need admin or
  # auditor. While the stream data plane is unavailable the gateway answers K9O_STREAM_UNAVAILABLE (503); a bad
  # subject answers K9O_STREAM_INVALID. Both raise K9o::KError.
  class Streams
    @reconnect_delay = 0.25

    class << self
      # Seconds to wait before reconnecting after the server closes a subscribe connection.
      attr_accessor :reconnect_delay
    end

    def initialize(config)
      @config = config
    end

    # POST /@<slug>/data-streams/user — +max_bytes+ is the storage ceiling; the slug is derived from +display_name+.
    def create(display_name, max_bytes, retention_seconds: nil)
      body = { 'displayName' => display_name, 'maxBytes' => max_bytes }
      body['retentionSeconds'] = retention_seconds unless retention_seconds.nil?
      call('POST', path, body)
    end

    # GET /@<slug>/data-streams/user — the project's active user streams.
    def list
      call('GET', path)
    end

    # GET /@<slug>/data-streams/user/<slug>
    def get(slug)
      call('GET', path(slug))
    end

    # DELETE /@<slug>/data-streams/user/<slug> — retire the stream.
    def delete(slug)
      call('DELETE', path(slug))
    end

    # POST .../<slug>/publish — +data+ is any JSON value; +subject+ is an optional dot-separated routing suffix.
    def publish(slug, data, subject: nil)
      body = { 'data' => data }
      body['subject'] = subject unless subject.nil?
      call('POST', path(slug, 'publish'), body)
    end

    # POST .../<slug>/replay — a bounded range of past events: data['events'], data['nextCursor'], data['hasMore'].
    def replay(slug, from_sequence: nil, until_sequence: nil, limit: nil)
      body = {}
      body['fromSequence'] = from_sequence unless from_sequence.nil?
      body['untilSequence'] = until_sequence unless until_sequence.nil?
      body['limit'] = limit unless limit.nil?
      call('POST', path(slug, 'replay'), body)
    end

    # GET .../<slug>/subscribe — an Enumerator tailing live events { 'sequence', 'subject', 'data', 'publishedAt' }.
    # The gateway bounds each connection and closes it; the enumerator reconnects from the last sequence it yielded.
    # Stop by leaving the +each+ block (break) or by taking a finite number (+first(n)+).
    def subscribe(slug, from_sequence: nil)
      route = path(slug, 'subscribe')
      Enumerator.new do |yielder|
        cursor = from_sequence
        loop do
          query = cursor.nil? ? nil : { 'fromSequence' => cursor.to_s }
          HttpTransport.stream_sse(config: @config, method: 'GET', path: route, query: query).each do |event|
            next unless event.is_a?(Hash) && event.key?('sequence')

            cursor = event['sequence']
            yielder << event
          end
          delay = self.class.reconnect_delay
          sleep(delay) if delay.positive?
        end
      end
    end

    private

    def call(method, route, body = nil)
      HttpTransport.request(config: @config, method: method, path: route, body: body)
    end

    def path(stream_slug = nil, suffix = nil)
      project = Studio.require_project_slug(@config, 'streams')
      sub = +'data-streams/user'
      sub << "/#{::URI.encode_www_form_component(stream_slug)}" if stream_slug
      sub << "/#{suffix}" if suffix
      UrlGrammar.project_path(project, sub)
    end
  end
end
