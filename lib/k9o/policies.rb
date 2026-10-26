# frozen_string_literal: true

module K9o
  # Policy bundle lifecycle namespace — k9o.policies.*.
  #
  # The policy document is a Hash of sections keyed by resource kind ('collections', 'storage', 'tools',
  # 'functions', 'secrets', 'streams', 'analytics'; other keys are allowed). Only authoring roles write policy and
  # only custodian roles publish; +validate+ is read-only.
  class Policies
    EDITOR_MODES = %w[visual json unspecified].freeze

    def initialize(config)
      @config = config
    end

    # GET /@<slug>/policy — the currently active policy (data is nil when none is published).
    def current
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'policy'))
    end

    def list(status: nil)
      slug = require_project_slug
      q = status ? { 'status' => status } : nil
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'policies'), query: q)
    end

    # POST /@<slug>/policies — create a draft bundle from a policy document.
    def create(policy:, rules: nil, editor_mode: nil)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.project_path(slug, 'policies'),
                            body: policy_body(policy, rules, editor_mode))
    end

    # POST /@<slug>/policies/validate — lint a candidate policy document without persisting.
    def validate(policy:, rules: nil)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.project_path(slug, 'policies/validate'),
                            body: policy_body(policy, rules, nil))
    end

    def get(bundle_id)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, "policies/#{enc(bundle_id)}"))
    end

    # PATCH /@<slug>/policies/<id> — replace a draft bundle's policy document. Published bundles cannot be patched.
    def update(bundle_id, policy:, rules: nil, editor_mode: nil)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'PATCH',
                            path: UrlGrammar.project_path(slug, "policies/#{enc(bundle_id)}"),
                            body: policy_body(policy, rules, editor_mode))
    end

    # Delete a draft bundle. Published bundles cannot be deleted.
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

    def policy_body(policy, rules, editor_mode)
      body = { 'policy' => policy }
      body['rules'] = rules unless rules.nil?
      body['editorMode'] = editor_mode unless editor_mode.nil?
      body
    end

    def require_project_slug
      Studio.require_project_slug(@config, 'policies')
    end

    def enc(s)
      ::URI.encode_www_form_component(s)
    end
  end
end
