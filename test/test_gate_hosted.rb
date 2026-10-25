# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/k9o'

class GateHostedTest < Minitest::Test
  Resp = Struct.new(:code, :body, :headers) do
    def [](k)
      headers[k.to_s.downcase]
    end
  end

  # Stub transport: records every request, answers with a canned response.
  class Fake
    attr_reader :reqs
    attr_accessor :use_ssl, :read_timeout

    def initialize(status, payload)
      @status = status
      @payload = payload
      @reqs = []
    end

    def request(req)
      @reqs << req
      Resp.new(@status, JSON.dump(@payload), {})
    end
  end

  OK = { 'data' => { 'signInUrl' => 'https://login.example.com/', 'rpId' => 'login.example.com' },
         'meta' => {} }.freeze
  NF = { 'code' => 'K9O_PROJECT_NOT_FOUND', 'message' => 'Project not found.' }.freeze

  def mk(fake, **opts)
    K9o.create_client(base_url: 'https://api.k9o.io', project_slug: 'portal', http_client: fake, **opts)
  end

  def test_get_to_gate_hosted
    f = Fake.new('200', OK)
    mk(f).gate.hosted
    assert_equal 1, f.reqs.size
    assert_equal 'GET', f.reqs[0].method
    assert_equal '/@portal/gate/hosted', f.reqs[0].path
  end

  def test_sends_no_credential_even_with_api_key_and_default_headers
    f = Fake.new('200', OK)
    mk(f, api_key: 'secret-key',
          default_headers: { 'Authorization' => 'Bearer other', 'Cookie' => 's=1' }).gate.hosted
    h = f.reqs[0].each_header.to_h
    refute h.key?('authorization')
    refute h.key?('cookie')
    refute_includes f.reqs[0].to_hash.to_s, 'secret-key'
  end

  def test_returns_sign_in_url_and_rp_id
    env = mk(Fake.new('200', OK)).gate.hosted
    assert_equal 'https://login.example.com/', env.data['signInUrl']
    assert_equal 'login.example.com', env.data['rpId']
  end

  def test_uniform_404_surfaces_as_kerror
    e = assert_raises(K9o::KError) { mk(Fake.new('404', NF)).gate.hosted }
    assert_equal 404, e.status
    assert_equal 'K9O_PROJECT_NOT_FOUND', e.code
  end

  def test_missing_project_slug_refused_without_request
    f = Fake.new('200', OK)
    c = K9o.create_client(base_url: 'https://api.k9o.io', http_client: f)
    e = assert_raises(K9o::KError) { c.gate.hosted }
    assert_equal 'K9O_MISSING_PROJECT_CONTEXT', e.code
    assert_empty f.reqs
  end
end
