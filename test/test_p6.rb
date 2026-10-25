# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/k9o'

# P6 surface-family tests (studio / compute.llms / realtime / org
# default-llm). Net::HTTP is stubbed via a fake http_client to assert
# URL + method composition; pure-logic surfaces (topic builders, replay
# guard, model enum) are tested directly.
class P6Test < Minitest::Test
  # Captures the request and returns a canned JSON response.
  class FakeResponse
    def initialize(code, body)
      @code = code
      @body = body
    end
    attr_reader :code, :body
  end

  class FakeHttp
    attr_reader :last_method, :last_path, :last_body
    attr_accessor :use_ssl, :read_timeout

    def initialize(json)
      @json = json
    end

    def request(req)
      @last_method = req.method
      @last_path = req.path
      @last_body = req.body
      FakeResponse.new('200', @json)
    end
  end

  def project_client(json)
    fake = FakeHttp.new(json)
    c = K9o.create_client(base_url: 'https://acme.api.k9o.io', project_slug: 'portal', http_client: fake)
    [c, fake]
  end

  def test_workflows_trigger
    c, fake = project_client('{"data":{"id":"wfr_1","workflowId":"wfl_x","projectId":"p","status":"pending"},"meta":{}}')
    env = c.studio.workflows.trigger('wfl_x', { 'foo' => 'bar' })
    assert_equal 'POST', fake.last_method
    assert_equal '/@portal/workflows/wfl_x/runs', fake.last_path
    assert_includes fake.last_body, 'bar'
    assert_equal 'pending', env.data['status']
  end

  def test_workflow_runs_cancel
    c, fake = project_client('{"data":{"id":"wfr_1","status":"cancelled"},"meta":{}}')
    c.studio.workflows.runs.cancel('wfl_x', 'wfr_1')
    assert_equal 'POST', fake.last_method
    assert_equal '/@portal/workflows/wfl_x/runs/wfr_1/cancel', fake.last_path
  end

  def test_dashboards_pin
    c, fake = project_client('{"data":{"id":"dsh_x","pinnedToWorkspace":true},"meta":{}}')
    c.studio.dashboards.pin('dsh_x')
    assert_equal '/@portal/dashboards/dsh_x/pin', fake.last_path
  end

  def test_llms_invoke
    c, fake = project_client('{"data":{"completion":"hi","tokensUsed":2,"latencyMs":9},"meta":{}}')
    env = c.compute.llms.invoke('mistral-7b', prompt: 'hello')
    assert_equal 'POST', fake.last_method
    assert_equal '/@portal/compute/llms/mistral-7b/invoke', fake.last_path
    assert_includes fake.last_body, 'hello'
    assert_equal 'hi', env.data['completion']
  end

  def test_org_default_llm_get_and_set
    fake = FakeHttp.new('{"data":"mistral-7b","meta":{}}')
    c = K9o.create_client(base_url: 'https://acme.api.k9o.io', http_client: fake)
    env = c.org.default_llm.get
    assert_equal '/org/default-llm', fake.last_path
    assert_equal 'mistral-7b', env.data
    c.org.default_llm.set('claude-3-5-sonnet')
    assert_equal 'PATCH', fake.last_method
    assert_includes fake.last_body, 'claude-3-5-sonnet'
  end

  def test_realtime_replay_posts_body
    c, fake = project_client('{"data":[],"meta":{}}')
    c.realtime.replay(K9o::Realtime::Topic.workflow_runs, from_sequence: 42, limit: 100)
    assert_equal 'POST', fake.last_method
    assert_equal '/@portal/realtime/replay', fake.last_path
    assert_includes fake.last_body, '42'
  end

  def test_realtime_topic_builders
    assert_equal 'collections.orders.*', K9o::Realtime::Topic.collection('orders')
    assert_equal 'studio.workflows.runs.*', K9o::Realtime::Topic.workflow_runs
    assert_equal 'studio.dashboards.refresh.dsh_x', K9o::Realtime::Topic.dashboard_refresh('dsh_x')
    assert_equal 'forge.functions.invocations.fn_x', K9o::Realtime::Topic.function_invocations('fn_x')
    assert_equal 'audit.org.role_granted', K9o::Realtime::Topic.audit_org('role_granted')
  end

  def test_realtime_replay_rejects_negative_sequence
    c = K9o.create_client(base_url: 'https://acme.api.k9o.io', project_slug: 'portal')
    e = assert_raises(K9o::KError) { c.realtime.replay('studio.workflows.runs.*', from_sequence: -1) }
    assert_equal 'K9O_INVALID_FILTER', e.code
  end

  def test_llm_model_ids_closed_enum
    assert_includes K9o::Compute::LLM_MODEL_IDS, 'mistral-7b'
    assert_includes K9o::Compute::LLM_MODEL_IDS, 'claude-3-5-sonnet'
    assert_equal 9, K9o::Compute::LLM_MODEL_IDS.length
  end

  def test_workflows_require_project_slug
    c = K9o.create_client(base_url: 'https://api.k9o.io')
    e = assert_raises(K9o::KError) { c.studio.workflows.read('wfl_x') }
    assert_equal 'K9O_MISSING_PROJECT_CONTEXT', e.code
  end

  def test_invoke_stream_returns_enumerator
    c = K9o.create_client(base_url: 'https://acme.api.k9o.io', project_slug: 'portal')
    enum = c.compute.llms.invoke_stream('gpt-4o', prompt: 'hi')
    assert_instance_of Enumerator, enum
  end
end

# client.ai.embed — URL, verb, body shape, bound-project guard, error hygiene.
class AiEmbedTest < Minitest::Test
  OK = '{"data":{"embeddings":[[0.1,0.2]],"model":"nomic-embed-text-v1.5","dimensions":2},"meta":{}}'

  def client(json, code = '200', project_slug: 'portal')
    fake = P6Test::FakeHttp.new(json)
    fake.define_singleton_method(:request) do |req|
      @last_method = req.method
      @last_path = req.path
      @last_body = req.body
      P6Test::FakeResponse.new(code, @json)
    end
    [K9o.create_client(base_url: 'https://acme.api.k9o.io', project_slug: project_slug, http_client: fake), fake]
  end

  def test_posts_embeddings_with_string_input
    c, fake = client(OK)
    env = c.ai.embed(input: 'hello')
    assert_equal 'POST', fake.last_method
    assert_equal '/@portal/ai/embeddings', fake.last_path
    assert_equal({ 'input' => 'hello' }, JSON.parse(fake.last_body))
    assert_equal [[0.1, 0.2]], env.data['embeddings']
    assert_equal 2, env.data['dimensions']
  end

  def test_array_input_and_model_sent_as_given
    c, fake = client(OK)
    c.ai.embed(model: 'nomic-embed-text-v1.5', input: ['search_document: a', 'search_document: b'])
    assert_equal({ 'model' => 'nomic-embed-text-v1.5', 'input' => ['search_document: a', 'search_document: b'] },
                 JSON.parse(fake.last_body))
  end

  def test_model_omitted_when_not_given
    c, fake = client(OK)
    c.ai.embed(input: ['x'])
    refute JSON.parse(fake.last_body).key?('model')
  end

  def test_requires_bound_project
    c, = client(OK, project_slug: nil)
    e = assert_raises(K9o::KError) { c.ai.embed(input: 'x') }
    assert_equal 'K9O_MISSING_PROJECT_CONTEXT', e.code
  end

  def test_server_refusal_is_kerror_without_input_text
    err = '{"code":"K9O_MODEL_NOT_DECLARED","message":"model is not a declared embedding model",' \
          '"context":{"declared":["nomic-embed-text-v1.5"]},"recommendation":null}'
    c, = client(err, '400')
    secret = 'the-secret-document-body'
    e = assert_raises(K9o::KError) { c.ai.embed(model: 'other', input: secret) }
    assert_equal 'K9O_MODEL_NOT_DECLARED', e.code
    refute_includes e.to_s, secret
    refute_includes e.context.to_s, secret
  end
end
