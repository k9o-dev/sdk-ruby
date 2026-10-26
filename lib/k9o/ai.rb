# frozen_string_literal: true

module K9o
  # AI namespace — platform AI primitives.
  # k9o.ai.embed(...)
  #
  # Wire (project-plane):
  #   POST /@<slug>/ai/embeddings  body { model?, input: String | [String] }
  #   -> { data: { embeddings: [[Float]], model:, dimensions: }, meta }
  #   POST /@<slug>/ai/generate    body { prompt:, model?, maxTokens?, temperature?, usageType? }
  #   -> { data: { modelId:, content:, finishReason:, usage:, usageType: }, meta }
  #
  # Bounds are enforced by the gateway, not here. The SDK sends `input`
  # exactly as given and never puts it in an error.
  class Ai
    def initialize(config)
      @config = config
    end

    # POST /@<slug>/ai/embeddings — embed one string or an array of strings.
    # `model` is omitted from the body when nil (server default).
    def embed(input:, model: nil)
      slug = Studio.require_project_slug(@config, 'ai')
      body = { 'input' => input }
      body['model'] = model unless model.nil?
      HttpTransport.request(config: @config, method: 'POST',
                            path: UrlGrammar.project_path(slug, 'ai/embeddings'), body: body)
    end

    # POST /@<slug>/ai/generate — one synchronous text generation (verb sugar over compute.llms.invoke).
    # Only the fields given are sent; without `model` the gateway uses the org's default LLM.
    def generate(prompt, model: nil, max_tokens: nil, temperature: nil, usage_type: nil)
      slug = Studio.require_project_slug(@config, 'ai')
      body = { 'prompt' => prompt }
      body['model'] = model unless model.nil?
      body['maxTokens'] = max_tokens unless max_tokens.nil?
      body['temperature'] = temperature unless temperature.nil?
      body['usageType'] = usage_type unless usage_type.nil?
      HttpTransport.request(config: @config, method: 'POST',
                            path: UrlGrammar.project_path(slug, 'ai/generate'), body: body)
    end
  end
end
