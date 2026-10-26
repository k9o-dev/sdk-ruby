# frozen_string_literal: true

module K9o
  # Realtime Subscriptions namespace.
  #
  # Transport: SSE over GET /@<slug>/realtime/subscribe. The gateway serves no WebSocket upgrade and no durable
  # replay, so neither is offered; after an `event: resync` frame the caller re-reads current state from the data
  # plane and resubscribes. #subscribe returns an Enumerator iterated via `.each`.
  class Realtime
    def initialize(config)
      @config = config
    end

    # Subscribe via SSE; returns an Enumerator yielding event hashes
    # { 'topic', 'eventType', 'payload', 'occurredAt' } (the gateway's spelling). Control frames such as `resync`
    # carry no +eventType+ and are skipped.
    def subscribe(topic, filter: nil)
      slug = Studio.require_project_slug(@config, 'realtime')
      q = { 'topic' => topic }
      q['filter'] = JSON.dump(filter) if filter
      frames = HttpTransport.stream_sse(config: @config, method: 'GET',
                                        path: UrlGrammar.project_path(slug, 'realtime/subscribe'), query: q)
      Enumerator.new do |yielder|
        frames.each do |event|
          yielder << event if event.is_a?(Hash) && event['eventType'].is_a?(String)
        end
      end
    end

    module Topic
      module_function

      def collection(collection)
        "collections.#{collection}.*"
      end

      def workflow_runs
        'studio.workflows.runs.*'
      end

      def query_executed(query_id)
        "studio.queries.executed.#{query_id}"
      end

      def dashboard_refresh(dashboard_id)
        "studio.dashboards.refresh.#{dashboard_id}"
      end

      def function_invocations(function_id)
        "forge.functions.invocations.#{function_id}"
      end

      def audit_org(event_family)
        "audit.org.#{event_family}"
      end
    end
  end
end
