# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/k9o'

# Wire contract: every method that sends a body, plus every method whose path or query was corrected to the gateway's
# routes, is checked for the exact HTTP method, path, query and JSON body it sends. The expected values are the
# gateway's (services/gateway/openapi.json and the route handlers), not the SDK's own.
class ContractTest < Minitest::Test
  Resp = Struct.new(:code, :body)

  # Records every request; answers an empty success envelope.
  class Recorder
    attr_reader :reqs
    attr_accessor :use_ssl, :read_timeout

    def initialize
      @reqs = []
    end

    def request(req)
      @reqs << req
      Resp.new('200', '{"data":{},"meta":{}}')
    end
  end

  def client
    @rec = Recorder.new
    K9o.create_client(base_url: 'https://acme.api-de01.k9o.io', api_key: 'k', project_slug: 'portal', http_client: @rec)
  end

  # Runs the call and returns [method, path, query-hash, parsed body or nil, request].
  def sent
    req = @rec.reqs.last
    u = URI.parse("https://x#{req.path}")
    json = req['content-type'] == 'application/json' && !req.body.to_s.empty?
    body = json ? JSON.parse(req.body) : nil
    [req.method, u.path, URI.decode_www_form(u.query || '').to_h, body, req]
  end

  def assert_sent(method, path, query: {}, body: nil)
    m, p, q, b, = sent
    assert_equal [method, path], [m, p]
    assert_equal query, q
    if body.nil?
      assert_nil b
    else
      assert_equal body, b
    end
  end

  # projects --------------------------------------------------------------------------------------------------------

  def test_projects_create_sends_display_name_and_wire_options
    client.projects.create(display_name: 'Demo', slug: 'demo', custody_mode: 'PLATFORM_MANAGED', region: 'de01',
                           idempotency_key: 'k1', processing_contexts: %w[a b])
    assert_sent('POST', '/projects', body: { 'displayName' => 'Demo', 'slug' => 'demo', 'custodyMode' => 'PLATFORM_MANAGED',
                                              'region' => 'de01', 'idempotencyKey' => 'k1',
                                              'processingContexts' => %w[a b] })
  end

  def test_projects_create_rejects_unknown_option_and_old_name_keyword
    assert_raises(ArgumentError) { client.projects.create(display_name: 'x', bogus: 1) }
    assert_raises(ArgumentError) { client.projects.create(slug: 'demo', name: 'x') }
  end

  def test_projects_get_and_update_use_the_projects_routes
    c = client
    c.projects.get('demo')
    assert_sent('GET', '/projects/demo')
    c.projects.update('demo', display_name: 'Renamed', description: nil)
    assert_sent('PATCH', '/projects/demo', body: { 'displayName' => 'Renamed', 'description' => nil })
  end

  # functions -------------------------------------------------------------------------------------------------------

  def test_functions_upload_artifact_sends_raw_bytes_with_the_artifact_content_type
    client.functions.upload_artifact("\x00asm".b, 'wasm')
    m, p, q, _b, req = sent
    assert_equal ['POST', '/@portal/functions/artifacts', {}], [m, p, q]
    assert_equal "\x00asm".b, req.body.b
    assert_equal 'application/wasm', req['content-type']
    client.functions.upload_artifact('tar-bytes', 'tar')
    assert_equal 'application/x-tar', sent.last['content-type']
    assert_raises(ArgumentError) { client.functions.upload_artifact('x', 'zip') }
  end

  def test_functions_deploy_references_an_uploaded_artifact
    client.functions.deploy(name: 'hello', runtime: 'bun', tier: 'sandbox', artifact_key: 'functions/p/abc.tar',
                            version: '1', description: 'd')
    assert_sent('POST', '/@portal/functions',
                body: { 'name' => 'hello', 'runtime' => 'bun', 'tier' => 'sandbox', 'artifactKey' => 'functions/p/abc.tar',
                        'version' => '1', 'description' => 'd' })
    assert_raises(ArgumentError) { client.functions.deploy(name: 'h', runtime: 'bun', code: 'x') }
  end

  def test_functions_list_query
    client.functions.list(status: 'active', limit: 10, cursor: 'c')
    assert_sent('GET', '/@portal/functions', query: { 'status' => 'active', 'limit' => '10', 'cursor' => 'c' })
  end

  def test_functions_invoke_wraps_the_payload
    c = client
    c.functions.invoke('hello', { 'a' => 1 })
    assert_sent('POST', '/@portal/functions/hello/invoke', body: { 'payload' => { 'a' => 1 } })
    c.functions.invoke('hello', { 'a' => 1 }, background: true, on_behalf_of: 'u_1', confined_to: 'f',
                                              delegation: { 'token' => 't' })
    assert_sent('POST', '/@portal/functions/hello/invoke',
                body: { 'payload' => { 'a' => 1 }, 'background' => true, 'delegation' => { 'token' => 't' },
                        'onBehalfOf' => 'u_1', 'confinedTo' => 'f' })
  end

  # policies --------------------------------------------------------------------------------------------------------

  def test_policies_bodies_carry_a_policy_document
    c = client
    c.policies.create(policy: { 'collections' => {} }, editor_mode: 'json')
    assert_sent('POST', '/@portal/policies', body: { 'policy' => { 'collections' => {} }, 'editorMode' => 'json' })
    c.policies.validate(policy: { 'collections' => {} })
    assert_sent('POST', '/@portal/policies/validate', body: { 'policy' => { 'collections' => {} } })
    c.policies.update('pol_1', policy: { 'collections' => {} }, rules: [1])
    assert_sent('PATCH', '/@portal/policies/pol_1', body: { 'policy' => { 'collections' => {} }, 'rules' => [1] })
    assert_raises(ArgumentError) { c.policies.create(name: 'n', rules: {}) }
  end

  # audit -----------------------------------------------------------------------------------------------------------

  def test_audit_query_uses_the_gateway_filter_names
    client.audit.query(event_type: 'auth.sign_in', actor_id: 'u_1', after: '2026-01-01', before: '2026-02-01', limit: 5,
                       cursor: 'c')
    assert_sent('GET', '/@portal/audit-log',
                query: { 'eventType' => 'auth.sign_in', 'actorId' => 'u_1', 'after' => '2026-01-01',
                         'before' => '2026-02-01', 'limit' => '5', 'cursor' => 'c' })
  end

  def test_org_audit_log_sends_only_what_the_route_reads
    client.org.audit_log.query(type: 'org.updated', limit: 10)
    assert_sent('GET', '/audit-log', query: { 'type' => 'org.updated', 'limit' => '10' })
    assert_raises(ArgumentError) { client.org.audit_log.query(since: 'x') }
  end

  # orgs and org ----------------------------------------------------------------------------------------------------

  def test_orgs_get_validates_the_slug
    c = client
    c.orgs.get('acme')
    assert_sent('GET', '/orgs/acme')
    assert_raises(K9o::KError) { c.orgs.get('Bad Slug') }
  end

  def test_org_members_and_groups
    c = client
    c.org.members.list(status: 'active', acceptance_status: 'accepted', user_id: 'u', role: 'ORG_ADMIN', state: 's')
    assert_sent('GET', '/members', query: { 'userId' => 'u', 'role' => 'ORG_ADMIN', 'acceptanceStatus' => 'accepted',
                                            'status' => 'active', 'state' => 's' })
    c.org.members.invite(email: 'a@b.co', role: 'ORG_MEMBER')
    assert_sent('POST', '/members', body: { 'email' => 'a@b.co', 'role' => 'ORG_MEMBER' })
    c.org.groups.list(user_id: 'u_1')
    assert_sent('GET', '/groups', query: { 'userId' => 'u_1' })
  end

  def test_org_role_grants_use_the_role_grants_route
    c = client
    c.org.gate.roles.list
    assert_sent('GET', '/role-grants')
    c.org.gate.roles.grant(user_id: 'u_1', role: 'ORG_ADMIN', decision_reason: 'r')
    assert_sent('POST', '/role-grants', body: { 'userId' => 'u_1', 'role' => 'ORG_ADMIN', 'decisionReason' => 'r' })
    c.org.gate.roles.get('g_1')
    assert_sent('GET', '/role-grants/g_1')
    c.org.gate.roles.revoke('g_1')
    assert_sent('DELETE', '/role-grants/g_1')
    c.org.gate.roles.revoke('g_1', decision_reason: 'r')
    assert_sent('DELETE', '/role-grants/g_1', body: { 'decisionReason' => 'r' })
  end

  def test_org_identity_providers_use_the_identity_providers_route
    c = client
    c.org.gate.idp_providers.list
    assert_sent('GET', '/identity-providers')
    c.org.gate.idp_providers.create(idp_provider: 'saml', display_name: 'Okta', client_id: 'cid',
                                    client_secret_ref: 'ref_1', tier_gating: 'free_tier_ok', enabled: true)
    assert_sent('POST', '/identity-providers',
                body: { 'idpProvider' => 'saml', 'displayName' => 'Okta', 'clientId' => 'cid',
                        'clientSecretRef' => 'ref_1', 'tierGating' => 'free_tier_ok', 'enabled' => true })
    c.org.gate.idp_providers.get('idp_1')
    assert_sent('GET', '/identity-providers/idp_1')
    c.org.gate.idp_providers.configure('idp_1', { 'enabled' => false })
    assert_sent('PATCH', '/identity-providers/idp_1', body: { 'enabled' => false })
    c.org.gate.idp_providers.delete('idp_1')
    assert_sent('DELETE', '/identity-providers/idp_1')
  end

  def test_org_smtp_sends_password_ref_and_from_address
    c = client
    c.org.smtp.set(host: 'smtp.x.io', port: 587, username: 'u', password_ref: 'ref_1', from_address: 'a@b.co',
                   from_name: 'A')
    assert_sent('PATCH', '/org',
                body: { 'smtpConfig' => { 'host' => 'smtp.x.io', 'port' => 587, 'username' => 'u',
                                          'passwordRef' => 'ref_1', 'fromAddress' => 'a@b.co', 'fromName' => 'A' } })
    c.org.smtp.test(to: 'a@b.co', subject: 's')
    assert_sent('POST', '/org/smtp/test-email', body: { 'to' => 'a@b.co', 'subject' => 's' })
    c.org.smtp.unset
    assert_sent('PATCH', '/org', body: { 'smtpConfig' => nil })
  end

  def test_org_default_llm_uses_the_default_llm_route
    c = client
    c.org.default_llm.get
    assert_sent('GET', '/default-llm')
    c.org.default_llm.set('llama-3-8b')
    assert_sent('PATCH', '/default-llm', body: { 'modelId' => 'llama-3-8b' })
  end

  # me --------------------------------------------------------------------------------------------------------------

  def test_me_profile_update_sends_only_given_fields
    c = client
    c.me.profile.update(display_name: 'A')
    assert_sent('PATCH', '/me', body: { 'displayName' => 'A' })
    c.me.profile.update(display_name: nil, timezone: 'Europe/Berlin')
    assert_sent('PATCH', '/me', body: { 'displayName' => nil, 'timezone' => 'Europe/Berlin' })
    assert_raises(ArgumentError) { c.me.profile.update(nickname: 'x') }
  end

  def test_me_sessions_use_the_post_revoke_routes
    c = client
    c.me.sessions.revoke('s_1')
    assert_sent('POST', '/auth/sessions/s_1/revoke')
    c.me.sessions.revoke_all
    assert_sent('POST', '/me/sessions/revoke-all')
  end

  def test_me_api_tokens_create_sends_label_and_scope_manifest
    scope = { 'operations' => ['read'], 'projects' => ['portal'], 'resourceClasses' => nil, 'collections' => nil, 'cidrs' => nil }
    client.me.api_tokens.create(label: 'ci', scope_manifest: scope, ttl_seconds: 3600)
    assert_sent('POST', '/me/api-tokens', body: { 'label' => 'ci', 'scopeManifest' => scope, 'ttlSeconds' => 3600 })
    assert_raises(ArgumentError) { client.me.api_tokens.create(name: 'ci') }
  end

  def test_removed_methods_are_gone
    c = client
    refute_respond_to c.me, :notifications
    refute_respond_to c.me, :audit_log
    refute_respond_to c.me, :data_export
    refute_respond_to c.gate, :hosted
    refute_respond_to c.gate, :verify_session
    refute_respond_to c.realtime, :replay
    refute_respond_to c.org.groups, :create
    refute_respond_to c.org.groups, :delete
    refute_respond_to c.org.members, :get
    refute_respond_to c.org.smtp, :get
  end

  # gate ------------------------------------------------------------------------------------------------------------

  def test_gate_bodies
    c = client
    c.gate.sign_up(email: 'a@b.co', password: 'pw', display_name: 'A')
    assert_sent('POST', '/@portal/gate/signup', body: { 'email' => 'a@b.co', 'password' => 'pw', 'displayName' => 'A' })
    c.gate.sign_in(email: 'a@b.co', password: 'pw')
    assert_sent('POST', '/@portal/gate/signin', body: { 'email' => 'a@b.co', 'password' => 'pw' })
    c.gate.sign_out(refresh_token: 'refresh-token-1')
    assert_sent('POST', '/@portal/gate/signout', body: { 'refreshToken' => 'refresh-token-1' })
    c.gate.refresh_token(refresh_token: 'refresh-token-1')
    assert_sent('POST', '/@portal/gate/refresh', body: { 'refreshToken' => 'refresh-token-1' })
    c.gate.whoami
    assert_sent('GET', '/@portal/gate/whoami')
    assert_raises(ArgumentError) { c.gate.sign_out }
  end

  # compute, studio, realtime ---------------------------------------------------------------------------------------

  def test_llms_invoke_puts_params_beside_the_prompt
    c = client
    c.compute.llms.list
    assert_sent('GET', '/@portal/compute/llms')
    c.compute.llms.invoke('llama-3-8b', prompt: 'hi', params: { max_tokens: 10, temperature: 0.2, usage_type: 'u' })
    assert_sent('POST', '/@portal/compute/llms/llama-3-8b/invoke',
                body: { 'prompt' => 'hi', 'maxTokens' => 10, 'temperature' => 0.2, 'usageType' => 'u' })
    c.compute.llms.invoke('llama-3-8b', prompt: 'hi', params: { 'maxTokens' => 3 })
    assert_sent('POST', '/@portal/compute/llms/llama-3-8b/invoke', body: { 'prompt' => 'hi', 'maxTokens' => 3 })
    assert_raises(ArgumentError) { c.compute.llms.invoke('llama-3-8b', prompt: 'hi', params: { top_k: 1 }) }
  end

  def test_llms_invoke_stream_sends_the_same_body
    c = client
    c.compute.llms.invoke_stream('llama-3-8b', prompt: 'hi', params: { max_tokens: 4 }).to_a
    assert_sent('POST', '/@portal/compute/llms/llama-3-8b/invoke-stream', body: { 'prompt' => 'hi', 'maxTokens' => 4 })
  end

  def test_workflows_trigger_wraps_trigger_context
    c = client
    c.studio.workflows.trigger('wfl_1', { 'k' => 'v' })
    assert_sent('POST', '/@portal/workflows/wfl_1/runs', body: { 'triggerContext' => { 'k' => 'v' } })
    c.studio.workflows.trigger('wfl_1')
    assert_sent('POST', '/@portal/workflows/wfl_1/runs', body: { 'triggerContext' => {} })
  end

  def test_workflow_list_filters_are_the_ones_the_route_reads
    c = client
    c.studio.workflows.list(status: 'active', limit: 3, cursor: 'c')
    assert_sent('GET', '/@portal/workflows', query: { 'status' => 'active', 'limit' => '3', 'cursor' => 'c' })
    assert_raises(ArgumentError) { c.studio.workflows.list(trigger_type: 'manual') }
    c.studio.workflows.runs.list('wfl_1', limit: 2, cursor: 'c')
    assert_sent('GET', '/@portal/workflows/wfl_1/runs', query: { 'limit' => '2', 'cursor' => 'c' })
    assert_raises(ArgumentError) { c.studio.workflows.runs.list('wfl_1', status: 'failed') }
  end

  def test_dashboards_list_filters
    client.studio.dashboards.list(status: 'active', pinned_only: true, limit: 2, cursor: 'c')
    assert_sent('GET', '/@portal/dashboards',
                query: { 'status' => 'active', 'pinnedOnly' => 'true', 'limit' => '2', 'cursor' => 'c' })
  end

  def test_workflow_and_dashboard_bodies_pass_through_unchanged
    c = client
    wf = { 'name' => 'w', 'triggerType' => 'manual', 'triggerConfig' => {},
           'actions' => [{ 'index' => 0, 'action_type' => 'branch', 'config' => {} }] }
    c.studio.workflows.create(wf)
    assert_sent('POST', '/@portal/workflows', body: wf)
    dash = { 'name' => 'd', 'widgets' => [{ 'id' => 'w1', 'widget_type' => 'kpi_card',
                                             'data_source' => { 'mode' => 'view', 'config' => {} } }] }
    c.studio.dashboards.create(dash)
    assert_sent('POST', '/@portal/dashboards', body: dash)
  end

  # migrations, storage, ai, vault ----------------------------------------------------------------------------------

  def test_migrations_bodies
    c = client
    migs = [{ 'version' => 1, 'slug' => 'init', 'up' => [], 'down' => [] }]
    c.migrations.apply(migs)
    assert_sent('POST', '/@portal/migrations/apply', body: { 'migrations' => migs })
    c.migrations.queue(migs)
    assert_sent('POST', '/@portal/migrations/queue', body: { 'migrations' => migs })
    c.migrations.reject_pending('pm_1', reason: 'no')
    assert_sent('POST', '/@portal/migrations/pending/pm_1/reject', body: { 'reason' => 'no' })
  end

  def test_storage_bodies
    c = client
    c.storage.create_bucket('docs', public: false, file_size_limit: 5)
    assert_sent('POST', '/@portal/storage/buckets', body: { 'name' => 'docs', 'public' => false, 'fileSizeLimit' => 5 })
    c.storage.from('docs').create_signed_url('a.txt', expires_in: 600, download: true)
    assert_sent('POST', '/@portal/storage/buckets/docs/objects/sign',
                body: { 'path' => 'a.txt', 'expiresIn' => 600, 'download' => true })
  end

  def test_ai_embed_body
    client.ai.embed(input: %w[a b], model: 'nomic-embed-text-v1.5')
    assert_sent('POST', '/@portal/ai/embeddings', body: { 'input' => %w[a b], 'model' => 'nomic-embed-text-v1.5' })
  end

  def test_vault_secret_bodies
    c = client
    c.kibo.vault.secrets.create(name: 'db/pw', value: 'x', region: 'de01')
    m, p, q, b, = sent
    assert_equal ['POST', '/@portal/vault/secrets/db%2Fpw', { 'region' => 'de01' }, { 'value' => 'eA==' }], [m, p, q, b]
    c.kibo.vault.secrets.move('db/pw', region: 'de01', new_path: 'z')
    assert_sent('POST', '/@portal/vault/secrets/db%2Fpw', query: { 'op' => 'move', 'region' => 'de01' },
                                                          body: { 'newPath' => 'z' })
  end

  # realtime --------------------------------------------------------------------------------------------------------

  class SseHttp
    attr_accessor :use_ssl, :read_timeout
    attr_reader :req

    def request(req)
      @req = req
      yield R.new
    end

    class R
      def code
        '200'
      end

      def read_body
        yield "event: resync\ndata: {\"reason\":\"cursor-evicted\",\"action\":\"reread-source\"}\n\n"
        yield "id: 1\nevent: row_inserted\ndata: {\"topic\":\"collections.x.*\",\"eventType\":\"row_inserted\",\"payload\":{},\"occurredAt\":\"t\"}\n\n"
      end
    end
  end

  def test_realtime_subscribe_sends_topic_and_filter_and_skips_resync_frames
    http = SseHttp.new
    c = K9o.create_client(base_url: 'https://acme.api-de01.k9o.io', project_slug: 'portal', http_client: http)
    events = c.realtime.subscribe('collections.x.*', filter: { 'a' => 1 }).to_a
    u = URI.parse("https://x#{http.req.path}")
    assert_equal '/@portal/realtime/subscribe', u.path
    assert_equal({ 'topic' => 'collections.x.*', 'filter' => '{"a":1}' }, URI.decode_www_form(u.query).to_h)
    assert_equal ['row_inserted'], events.map { |e| e['eventType'] }
  end
end
