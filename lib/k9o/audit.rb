# frozen_string_literal: true

module K9o
  # Project-plane audit log namespace — k9o.audit.*.
  # Distinct from k9o.org.audit_log.
  class Audit
    def initialize(config)
      @config = config
    end

    # GET /@<slug>/audit-log — reverse-chronological; filters AND-compose. Requires the AUDIT_READER role.
    #   event_type: audit-event name prefix (e.g. 'data.write.access')    actor_id: filter by actor
    #   after / before: ISO 8601 bounds (events after / before this instant)
    #   limit: page size (bounded server-side)    cursor: from the prior response's meta.cursor.next
    def query(event_type: nil, actor_id: nil, after: nil, before: nil, limit: nil, cursor: nil)
      slug = Studio.require_project_slug(@config, 'audit')
      q = {}
      q['eventType'] = event_type unless event_type.nil?
      q['actorId'] = actor_id unless actor_id.nil?
      q['after'] = after unless after.nil?
      q['before'] = before unless before.nil?
      q['limit'] = limit unless limit.nil?
      q['cursor'] = cursor unless cursor.nil?
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'audit-log'), query: q)
    end
  end
end
