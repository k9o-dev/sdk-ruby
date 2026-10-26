# frozen_string_literal: true

module K9o
  # Project lifecycle namespace — k9o.projects.* (Ruby snake_case).
  #
  # All four operations are org-plane: the client needs an org context (an
  # +org_slug+ or a bearer token that carries one). Option names are snake_case
  # spellings of the gateway's body property names.
  class Projects
    CREATE_FIELDS = {
      slug: 'slug', product_scope: 'productScope', region: 'region',
      default_project_region: 'defaultProjectRegion', custody_mode: 'custodyMode',
      processing_contexts: 'processingContexts', exec_seam_confined: 'execSeamConfined',
      showroom_vertical: 'showroomVertical', persona: 'persona', showroom_locale: 'showroomLocale',
      idempotency_key: 'idempotencyKey'
    }.freeze

    UPDATE_FIELDS = {
      slug: 'slug', display_name: 'displayName', description: 'description', region: 'region',
      product_scope: 'productScope', soft_delete_retention_days: 'softDeleteRetentionDays',
      processing_contexts: 'processingContexts'
    }.freeze

    def initialize(config)
      @config = config
    end

    # GET /projects
    def list
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('projects'))
    end

    # POST /projects. +display_name+ is required (1 to 128 characters); the gateway derives a slug from it when
    # +slug+ is omitted. +custody_mode+ is one of PLATFORM_MANAGED, SKR, BYOK, HYOK. +idempotency_key+ makes a
    # retried create return the first result instead of a second project.
    def create(display_name:, **opts)
      body = { 'displayName' => display_name }
      opts.each do |key, value|
        wire = CREATE_FIELDS[key]
        raise ArgumentError, "unknown projects.create option: #{key}" if wire.nil?

        body[wire] = value unless value.nil?
      end
      UrlGrammar.validate_slug(opts[:slug], 'project') unless opts[:slug].nil?
      HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('projects'), body: body)
    end

    # GET /projects/<slug>
    def get(slug)
      UrlGrammar.validate_slug(slug, 'project')
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path("projects/#{slug}"))
    end

    # PATCH /projects/<slug>. Pass only the fields to change; an explicit +nil+ is sent as null
    # (for +description+ that clears it).
    def update(slug, **fields)
      UrlGrammar.validate_slug(slug, 'project')
      patch = {}
      fields.each do |key, value|
        wire = UPDATE_FIELDS[key]
        raise ArgumentError, "unknown projects.update field: #{key}" if wire.nil?

        patch[wire] = value
      end
      HttpTransport.request(config: @config, method: 'PATCH', path: UrlGrammar.org_path("projects/#{slug}"), body: patch)
    end
  end
end
