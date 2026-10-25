# frozen_string_literal: true

module K9o
  # Project lifecycle namespace — k9o.projects.* (Ruby snake_case).
  class Projects
    def initialize(config)
      @config = config
    end

    def list
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('projects'))
    end

    def create(slug:, name:, custody_mode: nil)
      UrlGrammar.validate_slug(slug, 'project')
      body = { 'slug' => slug, 'name' => name }
      body['custodyMode'] = custody_mode if custody_mode
      HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('projects'), body: body)
    end

    def get(slug)
      UrlGrammar.validate_slug(slug, 'project')
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'project'))
    end

    def update(slug, name: nil)
      UrlGrammar.validate_slug(slug, 'project')
      patch = {}
      patch['name'] = name if name
      HttpTransport.request(config: @config, method: 'PATCH', path: UrlGrammar.project_path(slug, 'project'), body: patch)
    end
  end
end
