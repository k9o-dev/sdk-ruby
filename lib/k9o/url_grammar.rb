# frozen_string_literal: true

require 'uri'

module K9o
  # URL grammar helpers.
  module UrlGrammar
    SLUG_RE = /\A[a-z][a-z0-9-]{1,62}\z/

    # Bare platform apex hosts org-subdomain derivation applies to —
    # production and staging share the <org_slug>.<apex> wire-routing
    # scheme (confirmed live). A third apex needs the same confirmation
    # before joining this set.
    ORG_DERIVABLE_APEXES = %w[api.k9o.io api-staging.k9o.io].freeze

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

    # Resolve the effective base_url. base_url is
    # OPTIONAL — it defaults to the platform apex https://api.k9o.io. When the
    # (validated) host is a bare apex in ORG_DERIVABLE_APEXES and org_slug is
    # supplied, the SDK composes the canonical org-subdomain wire root
    # https://<org_slug>.<apex>. An explicit <org_slug> subdomain,
    # a self-hosted / Sovereign host, or a dev host (anything not in that
    # set) passes through unchanged — org_slug is intentionally NOT composed
    # onto a non-apex host.
    #
    # Fixed 2026-08-30 (SDK-2): this used to silently ignore org_slug for
    # api-staging.k9o.io too, not just genuine self-hosted/custom hosts,
    # since only the literal production apex string was checked.
    def resolve_base_url(base_url, org_slug = nil)
      validated = validate_base_url(base_url.nil? ? 'https://api.k9o.io' : base_url)
      uri = URI.parse(validated)
      if ORG_DERIVABLE_APEXES.include?(uri.host) && org_slug
        validate_slug(org_slug, 'org')
        return "#{uri.scheme}://#{org_slug}.#{uri.host}"
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
