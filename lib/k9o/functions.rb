# frozen_string_literal: true

module K9o
  # Function lifecycle namespace — k9o.functions.*.
  #
  # Upload the function's bytes first (+upload_artifact+ returns the +artifactKey+), then +deploy+ references that
  # artifact. Deploy requires PROJECT_ADMIN and returns with status +deploying+; the function is ready when status
  # flips to +active+.
  class Functions
    ARTIFACT_CONTENT_TYPES = { 'wasm' => 'application/wasm', 'tar' => 'application/x-tar' }.freeze

    def initialize(config)
      @config = config
    end

    # POST /@<slug>/functions/artifacts with the raw bytes: a WebAssembly module for the gateway tier (up to 16 MiB,
    # +kind+ 'wasm') or an OCI image archive for the sandbox tier (up to 256 MiB, +kind+ 'tar'). Uploading the same
    # bytes again returns the same key. The envelope's data is { 'artifactKey' => String }.
    def upload_artifact(bytes, kind)
      content_type = ARTIFACT_CONTENT_TYPES[kind.to_s]
      raise ArgumentError, "kind must be 'wasm' or 'tar'" if content_type.nil?

      bytes = bytes.read if bytes.respond_to?(:read)
      raise ArgumentError, 'bytes must be a String or an IO' unless bytes.is_a?(String)

      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'POST',
                            path: UrlGrammar.project_path(slug, 'functions/artifacts'),
                            raw_body: bytes, headers: { 'content-type' => content_type })
    end

    # POST /@<slug>/functions — deploy or redeploy from an uploaded artifact.
    #   runtime: bun python go java kotlin dotnet swift php ruby rust tinygo zig assemblyscript
    #   tier:    'gateway' (WebAssembly) or 'sandbox' (OCI image archive)
    #   artifact_key: the key +upload_artifact+ returned; version: label for this deploy (1 to 64 characters)
    def deploy(name:, runtime:, tier:, artifact_key:, version:, description: nil)
      slug = require_project_slug
      body = { 'name' => name, 'runtime' => runtime, 'tier' => tier, 'artifactKey' => artifact_key,
               'version' => version }
      body['description'] = description unless description.nil?
      HttpTransport.request(config: @config, method: 'POST', path: UrlGrammar.project_path(slug, 'functions'), body: body)
    end

    # GET /@<slug>/functions (cursor pagination).
    def list(status: nil, limit: nil, cursor: nil)
      slug = require_project_slug
      q = {}
      q['status'] = status unless status.nil?
      q['limit'] = limit unless limit.nil?
      q['cursor'] = cursor unless cursor.nil?
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'functions'), query: q)
    end

    def get(name)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, "functions/#{enc(name)}"))
    end

    # Retire a function; its name enters a 24h cooldown.
    def delete(name)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'DELETE', path: UrlGrammar.project_path(slug, "functions/#{enc(name)}"))
    end

    # POST /@<slug>/functions/<name>/invoke. +payload+ is sent as the +payload+ field of the request body and passed
    # to the function runtime verbatim. Optional controls: +background+ (run asynchronously), +delegation+
    # ({ 'token' => ..., 'invokeSessionId' => ... }), +on_behalf_of+, +confined_to+.
    def invoke(name, payload = nil, background: nil, delegation: nil, on_behalf_of: nil, confined_to: nil)
      slug = require_project_slug
      body = {}
      body['payload'] = payload unless payload.nil?
      body['background'] = background unless background.nil?
      body['delegation'] = delegation unless delegation.nil?
      body['onBehalfOf'] = on_behalf_of unless on_behalf_of.nil?
      body['confinedTo'] = confined_to unless confined_to.nil?
      HttpTransport.request(config: @config, method: 'POST',
                            path: UrlGrammar.project_path(slug, "functions/#{enc(name)}/invoke"), body: body)
    end

    private

    def require_project_slug
      Studio.require_project_slug(@config, 'functions')
    end

    def enc(s)
      ::URI.encode_www_form_component(s)
    end
  end
end
