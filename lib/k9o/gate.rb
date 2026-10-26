# frozen_string_literal: true

module K9o
  # Gate (Identity-Aware Kernel) namespace. Project-scoped; the gateway closes each body to the fields shown.
  class Gate
    def initialize(config)
      @config = config
    end

    # POST /@<slug>/gate/signup { email, password, displayName? }
    def sign_up(email:, password:, display_name: nil)
      body = { 'email' => email, 'password' => password }
      body['displayName'] = display_name if display_name
      HttpTransport.request(config: @config, method: 'POST', path: gate_path('signup'), body: body)
    end

    # POST /@<slug>/gate/signin { email, password }
    def sign_in(email:, password:)
      HttpTransport.request(
        config: @config, method: 'POST', path: gate_path('signin'),
        body: { 'email' => email, 'password' => password }
      )
    end

    # POST /@<slug>/gate/signout { refreshToken } — the refresh token is required (the gateway answers 400 without it).
    def sign_out(refresh_token:)
      HttpTransport.request(config: @config, method: 'POST', path: gate_path('signout'),
                            body: { 'refreshToken' => refresh_token })
    end

    # GET /@<slug>/gate/whoami
    def whoami
      HttpTransport.request(config: @config, method: 'GET', path: gate_path('whoami'))
    end

    # POST /@<slug>/gate/refresh { refreshToken }
    def refresh_token(refresh_token:)
      HttpTransport.request(
        config: @config, method: 'POST', path: gate_path('refresh'),
        body: { 'refreshToken' => refresh_token }
      )
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
