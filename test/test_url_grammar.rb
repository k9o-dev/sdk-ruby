# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/k9o'

class UrlGrammarTest < Minitest::Test
  def test_validate_base_url_accepts
    assert_equal 'https://api.k9o.io', K9o::UrlGrammar.validate_base_url('https://api.k9o.io')
    assert_equal 'https://acme.api.k9o.io', K9o::UrlGrammar.validate_base_url('https://acme.api.k9o.io')
    assert_equal 'http://localhost:8080', K9o::UrlGrammar.validate_base_url('http://localhost:8080')
    assert_equal 'https://api.k9o.io', K9o::UrlGrammar.validate_base_url('https://api.k9o.io/')
  end

  def test_validate_base_url_rejects_path
    e = assert_raises(K9o::KError) { K9o::UrlGrammar.validate_base_url('https://api.k9o.io/v2') }
    assert_equal 'K9O_INVALID_BASE_URL', e.code
  end

  def test_validate_base_url_rejects_websocket
    e = assert_raises(K9o::KError) { K9o::UrlGrammar.validate_base_url('wss://api.k9o.io') }
    assert_equal 'K9O_INVALID_BASE_URL', e.code
  end

  def test_validate_base_url_rejects_no_scheme
    assert_raises(K9o::KError) { K9o::UrlGrammar.validate_base_url('api.k9o.io') }
  end

  def test_validate_slug_accepts
    K9o::UrlGrammar.validate_slug('acme', 'org')
    K9o::UrlGrammar.validate_slug('member-portal', 'project')
    K9o::UrlGrammar.validate_slug('a1', 'org')
  end

  def test_validate_slug_rejects
    %w[Acme 1acme -acme acme- a].each do |bad|
      e = assert_raises(K9o::KError) { K9o::UrlGrammar.validate_slug(bad, 'test') }
      assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
    end
  end

  def test_resolve_base_url_defaults_to_apex
    assert_equal 'https://api.k9o.io', K9o::UrlGrammar.resolve_base_url(nil)
  end

  def test_resolve_base_url_derives_subdomain_from_apex_and_org_slug
    assert_equal 'https://acme.api.k9o.io', K9o::UrlGrammar.resolve_base_url(nil, 'acme')
    assert_equal 'https://acme.api.k9o.io', K9o::UrlGrammar.resolve_base_url('https://api.k9o.io', 'acme')
  end

  def test_resolve_base_url_validates_org_slug_when_deriving
    e = assert_raises(K9o::KError) { K9o::UrlGrammar.resolve_base_url(nil, 'Bad-Slug') }
    assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
  end

  def test_resolve_base_url_passthrough_explicit_subdomain
    assert_equal 'https://acme.api.k9o.io',
                 K9o::UrlGrammar.resolve_base_url('https://acme.api.k9o.io', 'acme')
  end

  def test_resolve_base_url_derives_subdomain_from_staging_apex_and_org_slug
    assert_equal 'https://acme.api-staging.k9o.io',
                 K9o::UrlGrammar.resolve_base_url('https://api-staging.k9o.io', 'acme')
  end

  def test_resolve_base_url_passthrough_explicit_staging_subdomain
    assert_equal 'https://acme.api-staging.k9o.io',
                 K9o::UrlGrammar.resolve_base_url('https://acme.api-staging.k9o.io', 'acme')
  end

  def test_resolve_base_url_staging_apex_without_org_slug_unchanged
    assert_equal 'https://api-staging.k9o.io',
                 K9o::UrlGrammar.resolve_base_url('https://api-staging.k9o.io')
  end

  def test_resolve_base_url_validates_org_slug_when_deriving_on_staging
    e = assert_raises(K9o::KError) { K9o::UrlGrammar.resolve_base_url('https://api-staging.k9o.io', 'Bad-Slug') }
    assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
  end

  def test_resolve_base_url_passthrough_self_hosted
    assert_equal 'https://platform.acme.internal',
                 K9o::UrlGrammar.resolve_base_url('https://platform.acme.internal', 'acme')
  end

  def test_resolve_base_url_passthrough_dev_host
    assert_equal 'http://localhost:8080',
                 K9o::UrlGrammar.resolve_base_url('http://localhost:8080', 'acme')
  end

  def test_resolve_base_url_apex_without_org_slug_unchanged
    assert_equal 'https://api.k9o.io', K9o::UrlGrammar.resolve_base_url('https://api.k9o.io')
  end

  def test_resolve_base_url_keeps_validation
    e = assert_raises(K9o::KError) { K9o::UrlGrammar.resolve_base_url('https://api.k9o.io/v2', 'acme') }
    assert_equal 'K9O_INVALID_BASE_URL', e.code
  end

  def test_project_path
    assert_equal '/@member-portal/data/posts',
                 K9o::UrlGrammar.project_path('member-portal', 'data/posts')
    assert_equal '/@acme/project', K9o::UrlGrammar.project_path('acme', '/project')
  end

  def test_org_path
    assert_equal '/projects', K9o::UrlGrammar.org_path('projects')
    assert_equal '/projects', K9o::UrlGrammar.org_path('/projects')
  end
end

# No apex is hardcoded: the org and region come from the host shape, whatever the apex is.
class UrlGrammarApexTest < Minitest::Test
  def test_parse_api_host_reads_org_region_and_apex_from_any_apex
    h = K9o::UrlGrammar.parse_api_host('acme.api-de01.corp.internal')
    assert_equal ['acme', 'api', 'de01', 'corp.internal'], [h.org_slug, h.family, h.region, h.apex]
    h = K9o::UrlGrammar.parse_api_host('api-staging.k9o.example')
    assert_nil h.org_slug
    assert_equal ['api-staging', nil, 'k9o.example'], [h.family, h.region, h.apex]
  end

  def test_parse_api_host_is_nil_for_other_shapes
    ['localhost', '127.0.0.1', 'example.com', 'acme.example.com', 'api', 'a..b'].each do |host|
      assert_nil K9o::UrlGrammar.parse_api_host(host), host
    end
  end

  def test_org_slug_is_composed_onto_a_platform_host_of_any_apex
    assert_equal 'https://acme.api.corp.internal',
                 K9o::UrlGrammar.resolve_base_url('https://api.corp.internal', 'acme')
    assert_equal 'http://acme.api.localhost:8080', K9o::UrlGrammar.resolve_base_url('http://api.localhost:8080', 'acme')
  end

  def test_hosts_that_are_not_platform_hosts_pass_through
    assert_equal 'http://localhost:8080', K9o::UrlGrammar.resolve_base_url('http://localhost:8080', 'acme')
    assert_equal 'https://acme.api.corp.internal', K9o::UrlGrammar.resolve_base_url('https://acme.api.corp.internal', 'other')
    assert_equal 'https://acme.api-de01.corp.internal',
                 K9o::UrlGrammar.resolve_base_url('https://acme.api-de01.corp.internal', 'acme')
  end

  def test_default_base_url_is_only_a_default
    assert_equal 'https://api.k9o.io', K9o::UrlGrammar.resolve_base_url(nil)
    assert_equal 'https://acme.api.k9o.io', K9o::UrlGrammar.resolve_base_url(nil, 'acme')
  end
end
