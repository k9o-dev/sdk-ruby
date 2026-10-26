# frozen_string_literal: true

module K9o
  # Operator-self namespace — k9o.me.*. Cross-org; org-plane routes under /me.
  # Sub-namespaces: profile / sessions / api_tokens.
  class Me
    attr_reader :profile, :sessions, :api_tokens

    def initialize(config)
      @profile = Profile.new(config)
      @sessions = Sessions.new(config)
      @api_tokens = ApiTokens.new(config)
    end

    # k9o.me.profile.*
    class Profile
      PATCH_FIELDS = { display_name: 'displayName', locale: 'locale', timezone: 'timezone' }.freeze

      def initialize(config)
        @config = config
      end

      def get
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('me'))
      end

      # PATCH /me. Pass only the fields to change (display_name, locale, timezone); an explicit +nil+ is sent as
      # null.
      def update(**fields)
        patch = {}
        fields.each do |key, value|
          wire = PATCH_FIELDS[key]
          raise ArgumentError, "unknown profile field: #{key}" if wire.nil?

          patch[wire] = value
        end
        HttpTransport.request(config: @config, method: 'PATCH', path: UrlGrammar.org_path('me'), body: patch)
      end
    end

    # k9o.me.sessions.*
    class Sessions
      def initialize(config)
        @config = config
      end

      def list
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('me/sessions'))
      end

      # POST /auth/sessions/<id>/revoke
      def revoke(session_id)
        HttpTransport.request(config: @config, method: 'POST',
                              path: UrlGrammar.org_path("auth/sessions/#{enc(session_id)}/revoke"))
      end

      # POST /me/sessions/revoke-all
      def revoke_all
        HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('me/sessions/revoke-all'))
      end

      private

      def enc(s)
        ::URI.encode_www_form_component(s)
      end
    end

    # k9o.me.api_tokens.*
    class ApiTokens
      def initialize(config)
        @config = config
      end

      def list
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('me/api-tokens'))
      end

      # POST /me/api-tokens { label, scopeManifest, ttlSeconds? }. +scope_manifest+ is a Hash with the gateway's keys
      # (each may be nil for "no restriction"): 'operations' (read / write / admin), 'projects', 'resourceClasses',
      # 'collections', 'cidrs'. The response carries the token's plaintext once.
      def create(label:, scope_manifest:, ttl_seconds: nil)
        body = { 'label' => label, 'scopeManifest' => scope_manifest }
        body['ttlSeconds'] = ttl_seconds unless ttl_seconds.nil?
        HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('me/api-tokens'), body: body)
      end

      def delete(token_id)
        HttpTransport.request(config: @config, method: 'DELETE',
                              path: UrlGrammar.org_path("me/api-tokens/#{enc(token_id)}"))
      end

      private

      def enc(s)
        ::URI.encode_www_form_component(s)
      end
    end
  end
end
