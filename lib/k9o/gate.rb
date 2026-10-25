# frozen_string_literal: true

module K9o
  # Gate (Identity-Aware Kernel) namespace. Project-scoped.
  class Gate
    def initialize(config)
      @config = config
    end

    def sign_up(email:, password:, display_name: nil)
      body = { 'email' => email, 'password' => password }
      body['displayName'] = display_name if display_name
      HttpTransport.request(config: @config, method: 'POST', path: gate_path('signup'), body: body)
    end

    def sign_in(email:, password:)
      HttpTransport.request(
        config: @config, method: 'POST', path: gate_path('signin'),
        body: { 'email' => email, 'password' => password }
      )
    end

    def sign_out(refresh_token: nil)
      body = refresh_token ? { 'refreshToken' => refresh_token } : {}
      HttpTransport.request(config: @config, method: 'POST', path: gate_path('signout'), body: body)
    end

    def whoami
      HttpTransport.request(config: @config, method: 'GET', path: gate_path('whoami'))
    end

    def refresh_token(refresh_token:)
      HttpTransport.request(
        config: @config, method: 'POST', path: gate_path('refresh'),
        body: { 'refreshToken' => refresh_token }
      )
    end

    def verify_session
      HttpTransport.request(config: @config, method: 'GET', path: gate_path('verify'))
    end

    # The project's hosted sign-in URL and WebAuthn rpId:
    # GET /@<slug>/gate/hosted. Unauthenticated and cacheable; no credential is
    # sent even when an api_key is configured. Returns an Envelope whose `data`
    # is { 'signInUrl' => String, 'rpId' => String }. Take both values as given:
    # an unknown org, a deleted project and a non-Gate project all answer the
    # same 404 K9O_PROJECT_NOT_FOUND.
    def hosted
      HttpTransport.request(config: @config, method: 'GET', path: gate_path('hosted'), authenticated: false)
    end

    private

    def gate_path(action)
      raise KError.new(
        code: 'K9O_MISSING_PROJECT_CONTEXT',
        message: 'k9o.gate operations require project_slug bound on the client',
        context: {}
      ) if @config.project_slug.nil? || @config.project_slug.empty?
      UrlGrammar.project_path(@config.project_slug, "gate/#{action}")
    end
  end
end
