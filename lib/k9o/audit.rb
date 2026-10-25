# frozen_string_literal: true

module K9o
  # Project-plane audit log namespace — k9o.audit.*.
  # Distinct from k9o.org.audit_log + k9o.me.audit_log.
  class Audit
    def initialize(config)
      @config = config
    end

    # Query the audit log (reverse-chronological; filters AND-compose).
    # Accepts keyword filters: since/until/type/actor_id/target_kind/
    # target_id/limit/cursor (wire camelCase mapping applied here).
    def query(since: nil, until_: nil, type: nil, actor_id: nil,
              target_kind: nil, target_id: nil, limit: nil, cursor: nil)
      slug = Studio.require_project_slug(@config, 'audit')
      q = {}
      q['since'] = since if since
      q['until'] = until_ if until_
      q['type'] = type if type
      q['actorId'] = actor_id if actor_id
      q['targetKind'] = target_kind if target_kind
      q['targetId'] = target_id if target_id
      q['limit'] = limit if limit
      q['cursor'] = cursor if cursor
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'audit-log'), query: q)
    end
  end
end
