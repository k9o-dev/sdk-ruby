# frozen_string_literal: true

module K9o
  # The customer-facing client returned by K9o.create_client.
  class K9oClient
    include QueryMethods

    attr_reader :config, :projects, :gate, :studio, :compute, :realtime, :streams, :org,
                :approvals, :approval_policies, :schema, :orgs, :migrations, :functions, :policies, :audit, :me, :kibo, :ai, :storage

    def initialize(config)
      @config = config
      @projects = Projects.new(config)
      @gate = Gate.new(config)
      @studio = Studio.new(config)
      @compute = Compute.new(config)
      @realtime = Realtime.new(config)
      @streams = Streams.new(config)
      @approvals = Approvals.new(config)
      @approval_policies = ApprovalPolicies.new(config)
      @schema = Schema.new(config)
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
  #   k9o = K9o.create_client(
  #     api_key: ENV["K9O_API_KEY"],
  #     org_slug: "acme",
  #     project_slug: "member-portal",
  #   )
  #
  # base_url is OPTIONAL. When omitted it defaults to the public-cloud platform host (a convenience only, never used
  # to parse a host). When the host is a platform host (+api.<apex>+ or +api-staging.<apex>+, any apex) and org_slug
  # is set, the org host +<org_slug>.<host>+ is composed. Any other host passes through unchanged.
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
