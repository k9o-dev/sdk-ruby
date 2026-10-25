# frozen_string_literal: true

module K9o
  # AI namespace — platform AI primitives.
  # k9o.ai.embed(...)
  #
  # Wire (project-plane):
  #   POST /@<slug>/ai/embeddings  body { model?, input: String | [String] }
  #   -> { data: { embeddings: [[Float]], model:, dimensions: }, meta }
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
  end
end
