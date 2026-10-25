# frozen_string_literal: true

module K9o
  # Realtime Subscriptions namespace (ALL-LIVE primitive).
  #
  # Ruby idiom: #subscribe returns an Enumerator iterated via
  # `.each`. Per + the SDK-abstracted-primitive discipline the
  # SDK picks the transport; SPLIT (polling) is the internal fallback. The
  # Net::HTTP-based Ruby SDK uses SSE primary (no stdlib WebSocket);
  # #subscribe_poll exposes the poll fallback. #replay is one-shot catch-up.
  class Realtime
    def initialize(config)
      @config = config
    end

    # Subscribe via SSE transport (primary); returns an
    # Enumerator yielding event hashes.
    def subscribe(topic, filter: nil)
      slug = Studio.require_project_slug(@config, 'realtime')
      q = { 'topic' => topic }
      q['filter'] = JSON.dump(filter) if filter
      HttpTransport.stream_sse(config: @config, method: 'GET',
                               path: UrlGrammar.project_path(slug, 'realtime/subscribe'), query: q)
    end

    # One-shot historical replay (capped 10k server-side).
    def replay(topic, from_sequence:, filter: nil, until_sequence: nil, limit: nil)
      slug = Studio.require_project_slug(@config, 'realtime')
      unless from_sequence.is_a?(Integer) && from_sequence >= 0
        raise KError.new(
          code: 'K9O_INVALID_FILTER',
          message: 'replay from_sequence must be a non-negative integer',
          context: { fromSequence: from_sequence },
          recommendation: 'Pass the highest sequence number you have already observed (or 0 to replay from the start).'
        )
      end
      body = { 'topic' => topic, 'fromSequence' => from_sequence }
      body['filter'] = filter if filter
      body['untilSequence'] = until_sequence if until_sequence
      body['limit'] = limit if limit
      HttpTransport.request(config: @config, method: 'POST',
                            path: UrlGrammar.project_path(slug, 'realtime/replay'), body: body)
    end

    # Poll-transport fallback (SDK-internal SPLIT). Single batch
    # via replay endpoint; caller loops tracking highest observed sequence.
    def subscribe_poll(topic, from_sequence:, filter: nil)
      replay(topic, from_sequence: from_sequence, filter: filter)
    end

    # Typed builders for the 6 closed topic families.
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
