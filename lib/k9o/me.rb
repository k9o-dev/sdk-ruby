# frozen_string_literal: true

module K9o
  # Operator-self namespace — k9o.me.*. Cross-org;
  # org-plane routes under /me. Sub-namespaces: profile / sessions /
  # api_tokens / notifications / audit_log / data_export.
  class Me
    attr_reader :profile, :sessions, :api_tokens, :notifications, :audit_log, :data_export

    def initialize(config)
      @profile = Profile.new(config)
      @sessions = Sessions.new(config)
      @api_tokens = ApiTokens.new(config)
      @notifications = Notifications.new(config)
      @audit_log = AuditLog.new(config)
      @data_export = DataExport.new(config)
    end

    # k9o.me.profile.*
    class Profile
      def initialize(config)
        @config = config
      end

      def get
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('me'))
      end

      def update(display_name: nil)
        HttpTransport.request(config: @config, method: 'PATCH', path: UrlGrammar.org_path('me'),
                              body: { 'displayName' => display_name })
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

      def revoke(session_id)
        HttpTransport.request(config: @config, method: 'DELETE',
                              path: UrlGrammar.org_path("me/sessions/#{enc(session_id)}"))
      end

      def revoke_all
        HttpTransport.request(config: @config, method: 'DELETE', path: UrlGrammar.org_path('me/sessions'))
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

      def create(name:, expires_in_days: nil, scope: nil)
        body = { 'name' => name }
        body['expiresInDays'] = expires_in_days if expires_in_days
        body['scope'] = scope if scope
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

    # k9o.me.notifications.*
    class Notifications
      def initialize(config)
        @config = config
      end

      def list(unread_only: nil, limit: nil, cursor: nil)
        q = {}
        q['unreadOnly'] = unread_only unless unread_only.nil?
        q['limit'] = limit if limit
        q['cursor'] = cursor unless cursor.nil?
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('me/notifications'), query: q)
      end

      def mark_read(notification_id)
        HttpTransport.request(config: @config, method: 'PATCH',
                              path: UrlGrammar.org_path("me/notifications/#{enc(notification_id)}"), body: { 'read' => true })
      end

      def mark_all_read
        HttpTransport.request(config: @config, method: 'PATCH', path: UrlGrammar.org_path('me/notifications'),
                              body: { 'read' => true })
      end

      private

      def enc(s)
        ::URI.encode_www_form_component(s)
      end
    end

    # k9o.me.audit_log.*
    class AuditLog
      def initialize(config)
        @config = config
      end

      def query(since: nil, until_: nil, type: nil, limit: nil, cursor: nil)
        q = {}
        q['since'] = since if since
        q['until'] = until_ if until_
        q['type'] = type if type
        q['limit'] = limit if limit
        q['cursor'] = cursor if cursor
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path('me/audit-log'), query: q)
      end
    end

    # k9o.me.data_export.*
    class DataExport
      def initialize(config)
        @config = config
      end

      def request(format: 'json')
        HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.org_path('me/data-export'),
                              body: { 'format' => format })
      end

      def status(job_id)
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.org_path("me/data-export/#{enc(job_id)}"))
      end

      private

      def enc(s)
        ::URI.encode_www_form_component(s)
      end
    end
  end
end
