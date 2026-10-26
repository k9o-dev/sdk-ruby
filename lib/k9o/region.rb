# frozen_string_literal: true

require 'net/http'
require 'uri'

module K9o
  # Regional host resolution.
  #
  # A region-free org host `<org>.api.<rest>` (or `<org>.api-staging.<rest>`)
  # redirects GET/HEAD only and REFUSES a request carrying a body /
  # Authorization / cookie, so credentials must go to `<org>.api-<rgn>.<rest>`.
  # The SDK learns the region with ONE unauthenticated HEAD to the configured
  # host (Net::HTTP never follows redirects, so the 308 is read, not followed),
  # takes the 308 `Location`, and caches the regional origin per client config.
  #
  # Nothing here knows an apex: the host comes from the configured base URL and
  # `<rest>` is whatever follows the gateway label, so public-cloud,
  # internal-apex, air-gapped and localhost deployments all work.
  #
  # - Only a region-free org host (see UrlGrammar.parse_api_host) is ever
  #   probed; any other base URL is used exactly as given.
  # - The probe carries no Authorization, cookie or default header.
  # - The Location is trusted only if https, no userinfo, no port, and host is
  #   exactly the same org and the same remainder with a region code
  #   ([a-z]{2}\d{2}) appended to the gateway label.
  # - Any other status or failure keeps the configured base URL. A definite
  #   answer is cached; a network failure of the probe is not.
  module Region
    module_function

    # The regional origin `location` may name for `host`, or nil. Pure.
    def origin_from_location(host, location, base)
      from = UrlGrammar.parse_api_host(host)
      return nil if from.nil? || from.org_slug.nil? || !from.region.nil?

      begin
        u = URI.join(base.sub(%r{/+\z}, '') + '/', location)
      rescue URI::Error, ArgumentError
        return nil
      end
      return nil unless u.is_a?(URI::HTTPS) && u.scheme == 'https'
      return nil unless u.userinfo.nil? && u.user.nil? && u.password.nil?
      return nil unless u.port == u.default_port

      h = u.host.to_s.downcase
      to = UrlGrammar.parse_api_host(h)
      return nil if to.nil? || to.region.nil?
      return nil unless to.org_slug == from.org_slug && to.family == from.family && to.apex == from.apex

      "https://#{h}"
    end

    # The origin requests for this client go to: the cached regional origin
    # once learned, else the configured base URL. Never raises.
    def resolve_origin(config)
      config.region_mutex.synchronize do
        cached = config.regional_origin
        return cached unless cached.nil?

        origin, cacheable = probe(config)
        config.regional_origin = origin if cacheable
        origin
      end
    end

    def probe(config)
      configured = config.base_url
      begin
        uri = URI.parse(configured)
        host = uri.host.to_s.downcase
      rescue URI::Error
        return [configured, true]
      end
      parsed_host = UrlGrammar.parse_api_host(host)
      return [configured, true] if parsed_host.nil? || parsed_host.org_slug.nil? || !parsed_host.region.nil?

      begin
        probe_uri = URI.parse("#{configured.sub(%r{/+\z}, '')}/")
        http = config.http_client || ::Net::HTTP.new(probe_uri.host, probe_uri.port)
        http.use_ssl = (probe_uri.scheme == 'https')
        http.read_timeout = 30
        # Deliberately NOT built from default_headers / api_key / org slug.
        req = ::Net::HTTP::Head.new(probe_uri.request_uri)
        req['accept'] = '*/*'
        res = http.request(req)
        if res.code.to_s == '308'
          loc = res['location']
          origin = loc.nil? ? nil : origin_from_location(host, loc.to_s, configured)
          return [origin, true] unless origin.nil?
        end
        [configured, true]
      rescue StandardError
        [configured, false]
      end
    end
  end
end
