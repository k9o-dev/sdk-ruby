# frozen_string_literal: true

module K9o
  # The customer-facing client returned by K9o.create_client.
  class K9oClient
    attr_reader :config, :projects, :gate, :studio, :compute, :realtime, :org,
                :orgs, :migrations, :functions, :policies, :audit, :me, :kibo, :ai, :storage

    def initialize(config)
      @config = config
      @projects = Projects.new(config)
      @gate = Gate.new(config)
      @studio = Studio.new(config)
      @compute = Compute.new(config)
      @realtime = Realtime.new(config)
      @org = Org.new(config)
      @orgs = Orgs.new(config)
      @migrations = Migrations.new(config)
      @functions = Functions.new(config)
      @policies = Policies.new(config)
      @audit = Audit.new(config)
      @me = Me.new(config)
      @kibo = KiboNamespace.new(config)
      @ai = Ai.new(config)
      @storage = Storage.new(config)
    end

    def from(collection)
      FromBuilder.new(@config, collection)
    end

    def base_url
      @config.base_url
    end
  end

  # Factory — construct a K9oClient bound to the supplied options.
  #
  # Per spec sample:
  #   k9o = K9o.create_client(
  #     api_key: ENV["K9O_API_KEY"],
  #     org_slug: "acme",
  #     project_slug: "member-portal",
  #   )
  #
  # base_url is OPTIONAL. When omitted it
  # defaults to the platform apex https://api.k9o.io; when the host is the
  # bare apex and org_slug is set, the canonical org-subdomain wire root
  # https://<org_slug>.api.k9o.io is composed. Any other host passes through.
  def self.create_client(base_url: nil, api_key: nil, org_slug: nil, project_slug: nil, default_headers: {}, http_client: nil)
    normalised = UrlGrammar.resolve_base_url(base_url, org_slug)
    config = HttpClientConfig.new(
      base_url: normalised,
      api_key: api_key, org_slug: org_slug, project_slug: project_slug,
      default_headers: default_headers, http_client: http_client
    )
    K9oClient.new(config)
  end
end
