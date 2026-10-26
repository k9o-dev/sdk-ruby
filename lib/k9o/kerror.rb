# frozen_string_literal: true

module K9o
  # KError — the closed-taxonomy error raised by every k9o surface
  # on non-2xx gateway responses or SDK-side validation failures.
  #
  # Ruby idiomatic shape: raise K9o::KError.
  # Code-narrowing: callers rescue K9o::KError and switch on e.code.
  class KError < StandardError
    attr_reader :code, :context, :recommendation, :status, :request_id

    def initialize(code:, message:, context: {}, recommendation: nil, status: nil, request_id: nil)
      super(message)
      @code = code
      @message_text = message  # avoid infinite recursion in to_s (Exception#message calls to_s)
      @context = context.freeze
      @recommendation = recommendation
      @status = status
      @request_id = request_id
    end

    def with_recommendation(rec)
      KError.new(
        code: @code, message: @message_text,
        context: @context, recommendation: rec,
        status: @status, request_id: @request_id
      )
    end

    # Override message to return the raw text (Exception's default calls to_s
    # which causes infinite recursion since we override to_s).
    def message
      @message_text
    end

    def to_s
      @status ? "[#{@code}] #{@message_text} (status=#{@status})" : "[#{@code}] #{@message_text}"
    end

    # Rehydrate a wire KError payload into a typed K9o::KError.
    def self.from_wire(wire, status)
      KError.new(
        code: wire['code'] || 'K9O_INTERNAL_ERROR',
        message: wire['message'] || '',
        context: wire['context'] || {},
        recommendation: wire['recommendation'],
        status: status,
        request_id: wire['requestId'] || wire['request_id']
      )
    end
  end
end
