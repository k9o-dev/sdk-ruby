# frozen_string_literal: true

module K9o
  # Compute namespace (Compute LLMs registry).
  # k9o.compute.llms.*
  class Compute
    # Curated 9-model closed enum (extensible v2.x).
    LLM_MODEL_IDS = %w[
      mistral-7b mistral-8x7b llama-3-8b llama-3-70b
      claude-3-5-sonnet gpt-4o gpt-4o-mini
      text-embedding-3-small text-embedding-3-large
    ].freeze

    attr_reader :llms

    def initialize(config)
      @llms = Llms.new(config)
    end

    # k9o.compute.llms.*.
    class Llms
      def initialize(config)
        @config = config
      end

      def list(modality: nil)
        slug = Studio.require_project_slug(@config, 'compute.llms')
        q = modality ? { 'modality' => modality } : nil
        HttpTransport.request(config: @config, method: 'GET',
                              path: UrlGrammar.project_path(slug, 'compute/llms'), query: q)
      end

      def read(model_id)
        slug = Studio.require_project_slug(@config, 'compute.llms')
        HttpTransport.request(config: @config, method: 'GET',
                              path: UrlGrammar.project_path(slug, "compute/llms/#{enc(model_id)}"))
      end

      # Synchronous inference (PROJECT_AUTHOR/ADMIN).
      def invoke(model_id, prompt:, params: nil)
        slug = Studio.require_project_slug(@config, 'compute.llms')
        body = { 'prompt' => prompt }
        body['params'] = params if params
        HttpTransport.request(config: @config, method: 'POST',
                              path: UrlGrammar.project_path(slug, "compute/llms/#{enc(model_id)}/invoke"), body: body)
      end

      # Streaming inference (SSE per-token). Returns an
      # Enumerator of chunk hashes (Ruby idiom). Consume with
      # `.each { |chunk| ... }`.
      def invoke_stream(model_id, prompt:, params: nil)
        slug = Studio.require_project_slug(@config, 'compute.llms')
        body = { 'prompt' => prompt }
        body['params'] = params if params
        HttpTransport.stream_sse(config: @config, method: 'POST',
                                 path: UrlGrammar.project_path(slug, "compute/llms/#{enc(model_id)}/invoke-stream"),
                                 body: body)
      end

      private

      def enc(s)
        ::URI.encode_www_form_component(s)
      end
    end
  end
end
