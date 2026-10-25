# frozen_string_literal: true

module K9o
  # Org-plane bound namespace — k9o.org.*. Singular
  # bound-org namespace (distinct from k9o.orgs collection): members /
  # groups / smtp / audit_log / gate (roles + idp_providers) + default_llm.
  # Org-plane URL grammar routes against the org subdomain
  # without the @<projectSlug>/ prefix.
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

    # Read the current org (slug + name + status + settings).
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

      def list(status: nil)
        q = status ? { 'status' => status } : nil
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('members'), query: q)
      end

      def invite(email:, role:)
        HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('members'),
                              body: { 'email' => email, 'role' => role })
      end

      def get(user_id)
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path("members/#{Org.enc(user_id)}"))
      end

      def remove(user_id)
        HttpTransport.request(config: @config, method: 'DELETE', path: UrlGrammar.org_path("members/#{Org.enc(user_id)}"))
      end
    end

    # k9o.org.groups.*
    class Groups
      def initialize(config)
        @config = config
      end

      def list
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('groups'))
      end

      def create(name:)
        HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('groups'), body: { 'name' => name })
      end

      def get(group_id)
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path("groups/#{Org.enc(group_id)}"))
      end

      def delete(group_id)
        HttpTransport.request(config: @config, method: 'DELETE', path: UrlGrammar.org_path("groups/#{Org.enc(group_id)}"))
      end
    end

    # k9o.org.audit_log.* (org-plane; distinct from project Audit).
    class AuditLog
      def initialize(config)
        @config = config
      end

      def query(since: nil, until_: nil, type: nil, actor_id: nil, target_kind: nil, target_id: nil, limit: nil, cursor: nil)
        q = {}
        q['since'] = since if since
        q['until'] = until_ if until_
        q['type'] = type if type
        q['actorId'] = actor_id if actor_id
        q['targetKind'] = target_kind if target_kind
        q['targetId'] = target_id if target_id
        q['limit'] = limit if limit
        q['cursor'] = cursor if cursor
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

      # k9o.org.gate.roles.*
      class Roles
        def initialize(config)
          @config = config
        end

        def list(user_id: nil, role: nil)
          q = {}
          q['userId'] = user_id if user_id
          q['role'] = role if role
          HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('org-role-grants'), query: q)
        end

        def grant(user_id:, role:)
          HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('org-role-grants'),
                                body: { 'userId' => user_id, 'role' => role })
        end

        def get(grant_id)
          HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path("org-role-grants/#{Org.enc(grant_id)}"))
        end

        def revoke(grant_id)
          HttpTransport.request(config: @config, method: 'DELETE', path: UrlGrammar.org_path("org-role-grants/#{Org.enc(grant_id)}"))
        end
      end

      # k9o.org.gate.idp_providers.*
      class IdpProviders
        def initialize(config)
          @config = config
        end

        def list
          HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('idp-providers'))
        end

        def create(name:, kind:, config:)
          HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('idp-providers'),
                                body: { 'name' => name, 'kind' => kind, 'config' => config })
        end

        def get(idp_id)
          HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path("idp-providers/#{Org.enc(idp_id)}"))
        end

        def configure(idp_id, patch)
          HttpTransport.request(config: @config, method: 'PATCH',
                                path: UrlGrammar.org_path("idp-providers/#{Org.enc(idp_id)}"), body: patch)
        end

        def delete(idp_id)
          HttpTransport.request(config: @config, method: 'DELETE', path: UrlGrammar.org_path("idp-providers/#{Org.enc(idp_id)}"))
        end
      end
    end

    # k9o.org.smtp.*
    class Smtp
      def initialize(config)
        @config = config
      end

      def get
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('org/smtp'))
      end

      def set(host:, port:, username:, password:, from_email:, from_name:, encryption:, reply_to_email: nil)
        smtp = {
          'host' => host, 'port' => port, 'username' => username, 'password' => password,
          'fromEmail' => from_email, 'fromName' => from_name, 'encryption' => encryption
        }
        smtp['replyToEmail'] = reply_to_email if reply_to_email
        HttpTransport.request(config: @config, method: 'PATCH', path: UrlGrammar.org_path('org'), body: { 'smtpConfig' => smtp })
      end

      def test(to:, from_override: nil)
        body = { 'to' => to }
        body['fromOverride'] = from_override if from_override
        HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('org/smtp/test-email'), body: body)
      end

      def unset
        HttpTransport.request(config: @config, method: 'PATCH', path: UrlGrammar.org_path('org'), body: { 'smtpConfig' => nil })
      end
    end

    # k9o.org.default_llm.* (ORG_ADMIN; tier-gated).
    class DefaultLlm
      def initialize(config)
        @config = config
      end

      # Read the org-default LLM model id (nil when unset → mistral-7b).
      def get
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('org/default-llm'))
      end

      # Set the org-default LLM (ORG_ADMIN; tier-gated).
      def set(model_id)
        HttpTransport.request(config: @config, method: 'PATCH',
                              path: UrlGrammar.org_path('org/default-llm'), body: { 'modelId' => model_id })
      end
    end
  end
end
