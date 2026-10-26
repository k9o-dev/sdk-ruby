# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/k9o'

# Regional host resolution: one unauthenticated HEAD to the region-free org
# host, 308 Location validation, caching, and that a credential only ever
# reaches a validated regional host. Same fixtures as packages/core/test/region.test.ts.
class RegionTest < Minitest::Test
  Resp = Struct.new(:code, :body, :headers) do
    def [](k)
      headers[k.to_s.downcase]
    end
  end

  Call = Struct.new(:method, :host, :path, :headers)

  class Fake
    attr_reader :calls
    attr_accessor :use_ssl, :read_timeout

    def initialize(head_location: nil, head_status: '308', head_fail_first: false)
      @calls = []
      @loc = head_location
      @status = head_status
      @fail_first = head_fail_first
      @heads = 0
    end

    def heads
      @calls.count { |c| c.method == 'HEAD' }
    end

    def request(req)
      @calls << Call.new(req.method, nil, req.path, req.each_header.to_h)
      if req.method == 'HEAD'
        @heads += 1
        raise 'offline' if @fail_first && @heads == 1

        return Resp.new(@status, nil, @loc ? { 'location' => @loc } : {})
      end
      resp = Resp.new('500', 'nope', {})
      return resp unless block_given?

      def resp.read_body
        yield body
      end
      yield resp
    end
  end

  def mk(fake, base = 'https://acme.api.k9o.io')
    K9o.create_client(base_url: base, project_slug: 'portal', api_key: 'secret-key',
                      default_headers: { 'x-extra' => '1' }, http_client: fake)
  end

  # The URL a credentialed call was actually sent to (the fake answers 500, so
  # the KError context carries the URL the transport built).
  def sent_url(client)
    client.gate.whoami
    flunk 'expected KError'
  rescue K9o::KError => e
    e.context[:url]
  end

  def test_probe_first_head_no_credentials_then_regional
    f = Fake.new(head_location: 'https://acme.api-de01.k9o.io/')
    c = mk(f)
    assert_equal 'https://acme.api-de01.k9o.io/@portal/gate/whoami', sent_url(c)
    assert_equal 'HEAD', f.calls[0].method
    assert_equal '/', f.calls[0].path
    keys = f.calls[0].headers.keys.map(&:downcase)
    refute_includes keys, 'authorization'
    refute_includes keys, 'x-extra'
    refute_includes keys, 'cookie'
    assert_equal 'GET', f.calls[1].method
    assert_includes f.calls[1].headers['authorization'], 'secret-key'
    assert_equal 'https://acme.api-de01.k9o.io', c.config.regional_origin
  end

  def test_caches_one_probe_for_two_calls
    f = Fake.new(head_location: 'https://acme.api-staging-de01.k9o.io/')
    c = mk(f, 'https://acme.api-staging.k9o.io')
    u1 = sent_url(c)
    u2 = sent_url(c)
    assert_equal 1, f.heads
    assert_equal 'https://acme.api-staging-de01.k9o.io/@portal/gate/whoami', u1
    assert_equal u1, u2
  end

  def test_no_redirect_keeps_configured_and_caches
    f = Fake.new(head_status: '200')
    c = mk(f)
    assert_equal 'https://acme.api.k9o.io/@portal/gate/whoami', sent_url(c)
    sent_url(c)
    assert_equal 1, f.heads
  end

  def test_never_probes_regional_custom_or_selfhosted
    ['https://acme.api-de01.k9o.io', 'https://api.example.com', 'https://k9o.internal.corp',
     'https://api.k9o.io', 'https://acme.api-staging-de01.k9o.io'].each do |base|
      f = Fake.new(head_location: 'https://evil.example/')
      c = mk(f, base)
      assert_equal "#{base}/@portal/gate/whoami", sent_url(c), base
      assert_equal 0, f.heads, base
      assert_equal 1, f.calls.size, base
    end
  end

  def test_refuses_hostile_locations
    [
      'https://evil.example/',
      'https://acme.api-de01.evil.example/',
      'https://other.api-de01.k9o.io/',
      'https://acme.api-staging-de01.k9o.io/',
      'http://acme.api-de01.k9o.io/',
      'https://user:pw@acme.api-de01.k9o.io/',
      'https://acme.api-de01.k9o.io:8443/',
      'https://acme.api-germany.k9o.io/'
    ].each do |loc|
      f = Fake.new(head_location: loc)
      c = mk(f)
      assert_equal 'https://acme.api.k9o.io/@portal/gate/whoami', sent_url(c), loc
    end
  end

  def test_non_308_status_with_location_is_ignored
    f = Fake.new(head_location: 'https://acme.api-de01.k9o.io/', head_status: '301')
    c = mk(f)
    assert_equal 'https://acme.api.k9o.io/@portal/gate/whoami', sent_url(c)
  end

  def test_probe_network_failure_not_cached
    f = Fake.new(head_location: 'https://acme.api-de01.k9o.io/', head_fail_first: true)
    c = mk(f)
    assert_equal 'https://acme.api.k9o.io/@portal/gate/whoami', sent_url(c)
    assert_equal 'https://acme.api-de01.k9o.io/@portal/gate/whoami', sent_url(c)
    assert_equal 2, f.heads
  end

  def test_origin_from_location_pure
    base = 'https://acme.api.k9o.io'
    assert_equal 'https://acme.api-de01.k9o.io',
                 K9o::Region.origin_from_location('acme.api.k9o.io', 'https://acme.api-de01.k9o.io/x', base)
    assert_nil K9o::Region.origin_from_location('acme.api.k9o.io', '/relative', base)
    assert_equal 'https://acme.api-staging-de01.k9o.io',
                 K9o::Region.origin_from_location('acme.api-staging.k9o.io', 'https://acme.api-staging-de01.k9o.io/', base)
    assert_nil K9o::Region.origin_from_location('api.example.com', 'https://acme.api-de01.k9o.io/', base)
  end

  def test_stream_path_resolves_regional_origin
    f = Fake.new(head_location: 'https://acme.api-de01.k9o.io/')
    c = mk(f)
    e = assert_raises(K9o::KError) { K9o::HttpTransport.stream_sse(config: c.config, method: 'GET', path: '/x').to_a }
    assert_equal 'https://acme.api-de01.k9o.io/x', e.context[:url]
    assert_equal 'HEAD', f.calls[0].method
  end
end

# The regional origin is learned for any apex, never only the public cloud's.
class RegionApexTest < Minitest::Test
  def test_internal_apex_location_is_accepted
    assert_equal 'https://acme.api-de01.corp.internal',
                 K9o::Region.origin_from_location('acme.api.corp.internal', 'https://acme.api-de01.corp.internal/',
                                                  'https://acme.api.corp.internal')
  end

  def test_other_org_other_apex_or_other_family_is_refused
    base = 'https://acme.api.corp.internal'
    [
      'https://evil.api-de01.corp.internal/', 'https://acme.api-de01.k9o.io/',
      'https://acme.api-staging-de01.corp.internal/', 'https://acme.api-de01.corp.internal:8443/',
      'http://acme.api-de01.corp.internal/', 'https://acme.api-xx.corp.internal/'
    ].each do |loc|
      assert_nil K9o::Region.origin_from_location('acme.api.corp.internal', loc, base), loc
    end
  end

  def test_a_regional_or_platform_host_has_no_origin_to_learn
    assert_nil K9o::Region.origin_from_location('acme.api-de01.corp.internal', 'https://acme.api-fr01.corp.internal/', 'x')
    assert_nil K9o::Region.origin_from_location('api.corp.internal', 'https://acme.api-de01.corp.internal/', 'x')
  end
end
