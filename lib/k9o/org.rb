# frozen_string_literal: true

module K9o
  # Org-plane bound namespace — k9o.org.*. Singular bound-org namespace (distinct from the k9o.orgs collection):
  # members / groups / smtp / audit_log / gate (roles + idp_providers) + default_llm.
  # Org-plane routes live on the org host without the @<projectSlug>/ prefix.
  class Org
    attr_reader :members, :groups, :smtp, :audit_log, :gate, :default_llm

    def initialize(config)
      @config = config
      @members = Members.new(config)
      @groups = Groups.new(config)
      @smtp = Smtp.new(config)
      @audit_log = AuditLog.new(config)
      @gate = Gate.new(config)
      @default_llm = DefaultLlm.new(config)
    end

    # GET /org — the current org (slug + name + status).
    def get
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('org'))
    end

    def self.enc(str)
      ::URI.encode_www_form_component(str)
    end

    # k9o.org.members.*
    class Members
      def initialize(config)
        @config = config
      end

      # GET /members. +status+ is the stored membership status ('active' or 'suspended'); +acceptance_status+ is
      # 'accepted' or 'pending'.
      def list(user_id: nil, role: nil, acceptance_status: nil, status: nil, state: nil)
        q = {}
        q['userId'] = user_id unless user_id.nil?
        q['role'] = role unless role.nil?
        q['acceptanceStatus'] = acceptance_status unless acceptance_status.nil?
        q['status'] = status unless status.nil?
        q['state'] = state unless state.nil?
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('members'), query: q)
      end

      # POST /members { email, role }
      def invite(email:, role:)
        HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('members'),
                              body: { 'email' => email, 'role' => role })
      end

      def remove(user_id)
        HttpTransport.request(config: @config, method: 'DELETE', path: UrlGrammar.org_path("members/#{Org.enc(user_id)}"))
      end
    end

    # k9o.org.groups.* (read-only: the gateway has no group create or delete)
    class Groups
      def initialize(config)
        @config = config
      end

      # GET /groups — optionally only the groups +user_id+ belongs to.
      def list(user_id: nil)
        q = user_id.nil? ? nil : { 'userId' => user_id }
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('groups'), query: q)
      end

      def get(group_id)
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path("groups/#{Org.enc(group_id)}"))
      end
    end

    # k9o.org.audit_log.* (org-plane; distinct from project Audit). The org audit route reads only +type+ (exact
    # event type) and +limit+ (1 to 500, default 100).
    class AuditLog
      def initialize(config)
        @config = config
      end

      def query(type: nil, limit: nil)
        q = {}
        q['type'] = type unless type.nil?
        q['limit'] = limit unless limit.nil?
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('audit-log'), query: q)
      end
    end

    # k9o.org.gate.*
    class Gate
      attr_reader :roles, :idp_providers

      def initialize(config)
        @roles = Roles.new(config)
        @idp_providers = IdpProviders.new(config)
      end

      # k9o.org.gate.roles.* — org role grants.
      class Roles
        def initialize(config)
          @config = config
        end

        # GET /role-grants (active grants).
        def list
          HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('role-grants'))
        end

        # POST /role-grants { userId, role, decisionReason? }
        def grant(user_id:, role:, decision_reason: nil)
          body = { 'userId' => user_id, 'role' => role }
          body['decisionReason'] = decision_reason unless decision_reason.nil?
          HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('role-grants'), body: body)
        end

        def get(grant_id)
          HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path("role-grants/#{Org.enc(grant_id)}"))
        end

        # DELETE /role-grants/<id> with an optional { decisionReason } body.
        def revoke(grant_id, decision_reason: nil)
          body = decision_reason.nil? ? nil : { 'decisionReason' => decision_reason }
          HttpTransport.request(config: @config, method: 'DELETE',
                                path: UrlGrammar.org_path("role-grants/#{Org.enc(grant_id)}"), body: body)
        end
      end

      # k9o.org.gate.idp_providers.* — the org's identity providers (/identity-providers).
      class IdpProviders
        CREATE_OPTIONAL = {
          redirect_uri: 'redirectUri', metadata_url: 'metadataUrl', attribute_map: 'attributeMap', enabled: 'enabled'
        }.freeze

        def initialize(config)
          @config = config
        end

        def list
          HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('identity-providers'))
        end

        # POST /identity-providers { idpProvider, displayName, clientId, clientSecretRef, tierGating, ... }
        #   idp_provider: google github microsoft oidc saml scim ldap active_directory apple facebook twitter
        #   tier_gating:  'free_tier_ok' or 'ridge_plus'
        #   client_secret_ref: a reference to the stored client secret, never the secret itself
        def create(idp_provider:, display_name:, client_id:, client_secret_ref:, tier_gating:, **opts)
          body = { 'idpProvider' => idp_provider, 'displayName' => display_name, 'clientId' => client_id,
                   'clientSecretRef' => client_secret_ref, 'tierGating' => tier_gating }
          opts.each do |key, value|
            wire = CREATE_OPTIONAL[key]
            raise ArgumentError, "unknown idp_providers.create option: #{key}" if wire.nil?

            body[wire] = value
          end
          HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('identity-providers'), body: body)
        end

        def get(idp_id)
          HttpTransport.request(config: @config, method: 'GET',
                                path: UrlGrammar.org_path("identity-providers/#{Org.enc(idp_id)}"))
        end

        # PATCH /identity-providers/<id>. +patch+ keys are the gateway's: displayName, clientId, clientSecretRef,
        # redirectUri, metadataUrl, attributeMap, enabled.
        def configure(idp_id, patch)
          HttpTransport.request(config: @config, method: 'PATCH',
                                path: UrlGrammar.org_path("identity-providers/#{Org.enc(idp_id)}"), body: patch)
        end

        def delete(idp_id)
          HttpTransport.request(config: @config, method: 'DELETE',
                                path: UrlGrammar.org_path("identity-providers/#{Org.enc(idp_id)}"))
        end
      end
    end

    # k9o.org.smtp.* — the org's SMTP relay, stored in the org record (PATCH /org { smtpConfig }).
    class Smtp
      def initialize(config)
        @config = config
      end

      # PATCH /org { smtpConfig: { host, port, username, passwordRef, fromAddress, fromName? } }.
      # +password_ref+ references the stored SMTP password; it is never the password itself.
      def set(host:, port:, username:, password_ref:, from_address:, from_name: nil)
        smtp = {
          'host' => host, 'port' => port, 'username' => username, 'passwordRef' => password_ref,
          'fromAddress' => from_address
        }
        smtp['fromName'] = from_name unless from_name.nil?
        HttpTransport.request(config: @config, method: 'PATCH', path: UrlGrammar.org_path('org'), body: { 'smtpConfig' => smtp })
      end

      # POST /org/smtp/test-email { to, subject? }
      def test(to:, subject: nil)
        body = { 'to' => to }
        body['subject'] = subject unless subject.nil?
        HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('org/smtp/test-email'), body: body)
      end

      # PATCH /org { smtpConfig: null }
      def unset
        HttpTransport.request(config: @config, method: 'PATCH', path: UrlGrammar.org_path('org'), body: { 'smtpConfig' => nil })
      end
    end

    # k9o.org.default_llm.* (ORG_ADMIN; tier-gated).
    class DefaultLlm
      def initialize(config)
        @config = config
      end

      # GET /default-llm
      def get
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('default-llm'))
      end

      # PATCH /default-llm { modelId }
      def set(model_id)
        HttpTransport.request(config: @config, method: 'PATCH',
                              path: UrlGrammar.org_path('default-llm'), body: { 'modelId' => model_id })
      end
    end
  end
end
