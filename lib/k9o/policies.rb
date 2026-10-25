# frozen_string_literal: true

module K9o
  # Policy bundle lifecycle namespace — k9o.policies.*.
  class Policies
    def initialize(config)
      @config = config
    end

    def current
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'policy'))
    end

    def list(status: nil)
      slug = require_project_slug
      q = status ? { 'status' => status } : nil
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'policies'), query: q)
    end

    def create(name:, rules:)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.project_path(slug, 'policies'),
                            body: { 'name' => name, 'rules' => rules })
    end

    def validate(rules)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.project_path(slug, 'policies/validate'),
                            body: { 'rules' => rules })
    end

    def get(bundle_id)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, "policies/#{enc(bundle_id)}"))
    end

    def update(bundle_id, patch)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'PATCH',
                            path: UrlGrammar.project_path(slug, "policies/#{enc(bundle_id)}"), body: patch)
    end

    def delete(bundle_id)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'DELETE', path: UrlGrammar.project_path(slug, "policies/#{enc(bundle_id)}"))
    end

    def publish(bundle_id)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'POST',
                            path: UrlGrammar.project_path(slug, "policies/#{enc(bundle_id)}/publish"))
    end

    private

    def require_project_slug
      Studio.require_project_slug(@config, 'policies')
    end

    def enc(s)
      ::URI.encode_www_form_component(s)
    end
  end
end
