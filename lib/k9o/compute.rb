# frozen_string_literal: true

module K9o
  # Compute namespace (Compute LLMs registry).
  # k9o.compute.llms.*
  class Compute
    # The curated model ids (closed enum).
    LLM_MODEL_IDS = %w[
      mistral-7b mistral-8x7b llama-3-8b llama-3-70b
      claude-3-5-sonnet gpt-4o gpt-4o-mini
      text-embedding-3-small text-embedding-3-large
    ].freeze

    # Inference parameters the gateway reads (top-level body fields next to +prompt+). Snake_case spellings map to
    # the gateway's.
    PARAM_FIELDS = {
      'max_tokens' => 'maxTokens', 'maxTokens' => 'maxTokens',
      'temperature' => 'temperature',
      'usage_type' => 'usageType', 'usageType' => 'usageType'
    }.freeze

    attr_reader :llms

    def initialize(config)
      @llms = Llms.new(config)
    end

    # k9o.compute.llms.*
    class Llms
      def initialize(config)
        @config = config
      end

      # GET /@<slug>/compute/llms
      def list
        slug = Studio.require_project_slug(@config, 'compute.llms')
        HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'compute/llms'))
      end

      def read(model_id)
        slug = Studio.require_project_slug(@config, 'compute.llms')
        HttpTransport.request(config: @config, method: 'GET',
                              path: UrlGrammar.project_path(slug, "compute/llms/#{enc(model_id)}"))
      end

      # Synchronous inference: POST /@<slug>/compute/llms/<id>/invoke { prompt, maxTokens?, temperature?,
      # usageType? }. +params+ takes max_tokens / temperature / usage_type (the gateway's spellings also work).
      # The envelope's data is { 'modelId', 'content', 'finishReason', 'usage' => { 'promptTokens',
      # 'completionTokens', 'totalTokens' }, 'usageType' }.
      def invoke(model_id, prompt:, params: nil)
        slug = Studio.require_project_slug(@config, 'compute.llms')
        HttpTransport.request(config: @config, method: 'POST',
                              path: UrlGrammar.project_path(slug, "compute/llms/#{enc(model_id)}/invoke"),
                              body: invoke_body(prompt, params))
      end

      # Streaming inference (SSE per-token). Returns an Enumerator of chunk hashes. Consume with
      # `.each { |chunk| ... }`.
      def invoke_stream(model_id, prompt:, params: nil)
        slug = Studio.require_project_slug(@config, 'compute.llms')
        HttpTransport.stream_sse(config: @config, method: 'POST',
                                 path: UrlGrammar.project_path(slug, "compute/llms/#{enc(model_id)}/invoke-stream"),
                                 body: invoke_body(prompt, params))
      end

      private

      def invoke_body(prompt, params)
        body = { 'prompt' => prompt }
        (params || {}).each do |key, value|
          wire = PARAM_FIELDS[key.to_s]
          raise ArgumentError, "unknown inference parameter: #{key}" if wire.nil?

          body[wire] = value unless value.nil?
        end
        body
      end

      def enc(s)
        ::URI.encode_www_form_component(s)
      end
    end
  end
end
