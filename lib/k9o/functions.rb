# frozen_string_literal: true

module K9o
  # Function lifecycle namespace — k9o.functions.*.
  class Functions
    def initialize(config)
      @config = config
    end

    def deploy(name:, runtime:, code:, tier: nil, config: nil)
      slug = require_project_slug
      body = { 'name' => name, 'runtime' => runtime, 'code' => code }
      body['tier'] = tier if tier
      body['config'] = config if config
      HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.project_path(slug, 'functions'), body: body)
    end

    def list(status: nil)
      slug = require_project_slug
      q = status ? { 'status' => status } : nil
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'functions'), query: q)
    end

    def get(name)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, "functions/#{enc(name)}"))
    end

    def delete(name)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'DELETE', path: UrlGrammar.project_path(slug, "functions/#{enc(name)}"))
    end

    # Invoke a function; payload passed to the runtime verbatim.
    def invoke(name, payload)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'POST',
                            path: UrlGrammar.project_path(slug, "functions/#{enc(name)}/invoke"), body: payload)
    end

    private

    def require_project_slug
      Studio.require_project_slug(@config, 'functions')
    end

    def enc(s)
      ::URI.encode_www_form_component(s)
    end
  end
end
