# frozen_string_literal: true

module K9o
  # Standard envelope returned by every k9o surface on success.
  class Envelope
    attr_reader :data, :meta

    def initialize(data:, meta:)
      @data = data
      @meta = meta
    end

    def self.from_wire(wire)
      Envelope.new(
        data: wire['data'],
        meta: Meta.from_wire(wire['meta'] || {})
      )
    end
  end

  # Meta accessor sugar.
  class Meta
    attr_reader :cursor, :subscription, :idempotency, :warnings, :cost, :timing, :context

    def initialize(cursor: nil, subscription: nil, idempotency: nil, warnings: [], cost: {}, timing: nil, context: nil)
      @cursor = cursor
      @subscription = subscription
      @idempotency = idempotency
      @warnings = warnings
      @cost = cost
      @timing = timing
      @context = context
    end

    def self.from_wire(wire)
      cursor = wire['cursor'] ? MetaCursor.new(next_: wire['cursor']['next'], total_count: wire['cursor']['totalCount']) : nil
      sub = wire['subscription'] ? MetaSubscription.new(is_initial: !!wire['subscription']['isInitial']) : nil
      idem = wire['idempotency'] ? MetaIdempotency.new(replayed: !!wire['idempotency']['replayed']) : nil
      warnings = (wire['warnings'] || []).map { |w| MetaWarning.new(code: w['code'] || '', message: w['message'] || '') }
      timing = wire['timing'] ? MetaTiming.new(total_ms: wire['timing']['totalMs'].to_i) : nil
      context = wire['context'] && wire['context']['requestId'] ? MetaContext.new(request_id: wire['context']['requestId']) : nil
      Meta.new(
        cursor: cursor, subscription: sub, idempotency: idem,
        warnings: warnings, cost: wire['cost'] || {},
        timing: timing, context: context
      )
    end
  end

  class MetaCursor
    attr_reader :next, :total_count

    def initialize(next_:, total_count:)
      @next = next_
      @total_count = total_count
    end
  end

  MetaSubscription = Struct.new(:is_initial, keyword_init: true)
  MetaIdempotency = Struct.new(:replayed, keyword_init: true)
  MetaWarning = Struct.new(:code, :message, keyword_init: true)
  MetaTiming = Struct.new(:total_ms, keyword_init: true)
  MetaContext = Struct.new(:request_id, keyword_init: true)
end
