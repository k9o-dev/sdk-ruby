# frozen_string_literal: true

module K9o
  # Org lifecycle namespace (collection-style) — k9o.orgs.*.
  # Distinct from k9o.org (singular bound-org namespace).
  class Orgs
    def initialize(config)
      @config = config
    end

    def list
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('orgs'))
    end

    def get(org_slug)
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path("orgs/#{enc(org_slug)}"))
    end

    def restore(org_id)
      HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path("orgs/#{enc(org_id)}/restore"))
    end

    def current
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('org'))
    end

    private

    def enc(s)
      ::URI.encode_www_form_component(s)
    end
  end
end
