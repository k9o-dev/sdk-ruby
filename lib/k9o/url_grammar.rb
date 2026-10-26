# frozen_string_literal: true

require 'uri'

module K9o
  # URL grammar helpers.
  module UrlGrammar
    SLUG_RE = /\A[a-z][a-z0-9-]{1,62}\z/

    # The convenience default when the caller passes no base_url. A default value only: never used to parse a host.
    DEFAULT_BASE_URL = 'https://api.k9o.io'

    # `api` or `api-staging`, optionally followed by `-<rgn>`: the label that marks a gateway host.
    API_LABEL = /\A(api|api-staging)(?:-([a-z]{2}\d{2}))?\z/.freeze

    # The structure of a gateway API host, read from the host itself.
    #   org_slug: first label of an org host (+acme+ in +acme.api.corp.internal+); nil for a platform host.
    #   family:   +api+ or +api-staging+.
    #   region:   4-character region code when the host is regional (+api-de01+), else nil.
    #   apex:     everything after the gateway label; never matched against a list.
    ApiHost = Struct.new(:org_slug, :family, :region, :apex)

    module_function

    def validate_base_url(base_url)
      raise KError.new(
        code: 'K9O_INVALID_BASE_URL',
        message: "base_url #{base_url.inspect} is not a valid URL",
        context: { base_url: base_url }
      ) unless base_url.is_a?(String) && !base_url.empty?

      begin
        uri = URI.parse(base_url)
      rescue URI::InvalidURIError => e
        raise KError.new(
          code: 'K9O_INVALID_BASE_URL',
          message: "base_url #{base_url.inspect} is not a valid URL: #{e.message}",
          context: { base_url: base_url }
        )
      end

      unless %w[http https].include?(uri.scheme)
        raise KError.new(
          code: 'K9O_INVALID_BASE_URL',
          message: "base_url #{base_url.inspect} uses unsupported scheme #{uri.scheme.inspect}; expected http or https",
          context: { base_url: base_url, scheme: uri.scheme }
        )
      end
      if uri.host.nil? || uri.host.empty?
        raise KError.new(
          code: 'K9O_INVALID_BASE_URL',
          message: "base_url #{base_url.inspect} missing host",
          context: { base_url: base_url }
        )
      end
      if uri.path && uri.path != '' && uri.path != '/'
        raise KError.new(
          code: 'K9O_INVALID_BASE_URL',
          message: "base_url #{base_url.inspect} must not contain a path segment; got #{uri.path.inspect}",
          context: { base_url: base_url, path: uri.path }
        )
      end
      if uri.query || uri.fragment
        raise KError.new(
          code: 'K9O_INVALID_BASE_URL',
          message: "base_url #{base_url.inspect} must not contain query or fragment",
          context: { base_url: base_url }
        )
      end

      host_port = uri.port && uri.port != uri.default_port ? "#{uri.host}:#{uri.port}" : uri.host
      "#{uri.scheme}://#{host_port}"
    end

    # Read the org slug and region out of a gateway host without knowing its apex. The gateway label is +api+ or
    # +api-staging+, optionally followed by +-<rgn>+; the label before it is the org slug and whatever follows it is
    # the apex. Returns nil for any other shape (localhost, an IP, a single-label host, a host with no gateway
    # label), which callers use exactly as given.
    def parse_api_host(host)
      labels = host.to_s.downcase.split('.', -1)
      return nil if labels.empty? || labels.any?(&:empty?)

      build = lambda do |gateway_label, org_slug, rest|
        m = API_LABEL.match(gateway_label)
        next nil if m.nil? || rest.empty?

        ApiHost.new(org_slug, m[1], m[2], rest.join('.'))
      end
      # Org host first: <org>.<api[-rgn]>.<apex>.
      if labels.length >= 3 && labels[0].match?(SLUG_RE) && !labels[0].end_with?('-') && API_LABEL.match?(labels[1])
        return build.call(labels[1], labels[0], labels[2..-1])
      end
      # Platform host: api.<apex>.
      return build.call(labels[0], nil, labels[1..-1]) if labels.length >= 2 && API_LABEL.match?(labels[0])

      nil
    end

    # Resolve the effective base_url. base_url is OPTIONAL: omitted, it defaults to DEFAULT_BASE_URL (the public
    # cloud, a convenience only). When the (validated) host is a platform host (+api.<apex>+ or +api-staging.<apex>+,
    # any apex) and org_slug is supplied, the canonical org host +<org_slug>.<host>+ is composed. Any other host (an
    # org host already, an internal or air-gapped host, localhost) passes through unchanged; org_slug is then only
    # sent as a header.
    def resolve_base_url(base_url, org_slug = nil)
      validated = validate_base_url(base_url.nil? ? DEFAULT_BASE_URL : base_url)
      uri = URI.parse(validated)
      host = parse_api_host(uri.host)
      if !host.nil? && host.org_slug.nil? && host.region.nil? && org_slug
        validate_slug(org_slug, 'org')
        host_port = uri.port && uri.port != uri.default_port ? "#{uri.host}:#{uri.port}" : uri.host
        return "#{uri.scheme}://#{org_slug}.#{host_port}"
      end
      validated
    end

    def validate_slug(slug, kind)
      unless slug.is_a?(String) && slug.match?(SLUG_RE) && !slug.end_with?('-')
        raise KError.new(
          code: 'K9O_INVALID_FIELD_VALUE',
          message: "#{kind}_slug #{slug.inspect} does not match required format ^[a-z][a-z0-9-]{1,62}$ (must not end with hyphen)",
          context: { slug: slug, kind: kind }
        )
      end
    end

    def project_path(project_slug, sub_resource)
      cleaned = sub_resource.sub(%r{\A/}, '')
      "/@#{project_slug}/#{cleaned}"
    end

    def org_path(resource)
      "/#{resource.sub(%r{\A/}, '')}"
    end

    def platform_path(resource)
      "/#{resource.sub(%r{\A/}, '')}"
    end
  end
end
