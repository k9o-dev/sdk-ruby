# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/k9o'

class ClientTest < Minitest::Test
  def test_create_client_constructs_with_minimal_opts
    c = K9o.create_client(base_url: 'https://api.k9o.io')
    assert_equal 'https://api.k9o.io', c.base_url
    refute_nil c.projects
    refute_nil c.gate
  end

  def test_create_client_defaults_base_url_to_apex
    c = K9o.create_client
    assert_equal 'https://api.k9o.io', c.base_url
  end

  def test_create_client_derives_subdomain_from_org_slug
    c = K9o.create_client(org_slug: 'acme')
    assert_equal 'https://acme.api.k9o.io', c.base_url
  end

  def test_create_client_passthrough_explicit_subdomain
    c = K9o.create_client(base_url: 'https://acme.api.k9o.io', org_slug: 'acme')
    assert_equal 'https://acme.api.k9o.io', c.base_url
  end

  def test_create_client_passthrough_self_hosted
    c = K9o.create_client(base_url: 'https://platform.acme.internal', org_slug: 'acme')
    assert_equal 'https://platform.acme.internal', c.base_url
  end

  def test_create_client_normalises_trailing_slash
    c = K9o.create_client(base_url: 'https://api.k9o.io/')
    assert_equal 'https://api.k9o.io', c.base_url
  end

  def test_create_client_rejects_path_bearing_base_url
    e = assert_raises(K9o::KError) { K9o.create_client(base_url: 'https://api.k9o.io/v2') }
    assert_equal 'K9O_INVALID_BASE_URL', e.code
  end

  def test_data_plane_select_requires_project_slug
    c = K9o.create_client(base_url: 'https://api.k9o.io')
    e = assert_raises(K9o::KError) { c.from('posts').select.execute }
    assert_equal 'K9O_MISSING_PROJECT_CONTEXT', e.code
  end

  def test_data_plane_update_requires_id_filter
    c = K9o.create_client(base_url: 'https://api.k9o.io', project_slug: 'member-portal')
    e = assert_raises(K9o::KError) { c.from('posts').update({ 'title' => 'x' }).execute }
    assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
  end

  def test_projects_create_validates_slug
    c = K9o.create_client(base_url: 'https://api.k9o.io', org_slug: 'acme')
    e = assert_raises(K9o::KError) { c.projects.create(display_name: 'x', slug: 'Bad-Slug') }
    assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
  end

  def test_gate_requires_project_slug
    c = K9o.create_client(base_url: 'https://api.k9o.io')
    e = assert_raises(K9o::KError) { c.gate.whoami }
    assert_equal 'K9O_MISSING_PROJECT_CONTEXT', e.code
  end

  def test_collection_name_validation
    c = K9o.create_client(base_url: 'https://api.k9o.io', project_slug: 'member-portal')
    e = assert_raises(K9o::KError) { c.from('Bad-Name').select.execute }
    assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
  end
end
