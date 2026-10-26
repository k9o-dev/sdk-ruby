# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/k9o'

# client.approvals, client.approval_policies, client.schema.collections: wire shape and client-side validation.
class ApprovalsTest < Minitest::Test
  Resp = Struct.new(:code, :body)

  class Recorder
    attr_reader :reqs
    attr_accessor :use_ssl, :read_timeout, :body

    def initialize
      @reqs = []
      @body = '{"data":{},"meta":{}}'
    end

    def request(req)
      @reqs << req
      Resp.new('200', @body)
    end
  end

  CRITERIA = { 'eq' => ['change.table', 'orders'] }.freeze
  PREDICATE = { 'gt' => ['change.row.amount', 1000] }.freeze

  def setup
    @rec = Recorder.new
  end

  def client(project_slug: 'portal')
    K9o.create_client(base_url: 'https://acme.api-de01.k9o.io', api_key: 'k', project_slug: project_slug,
                      http_client: @rec)
  end

  # [method, path, query hash, body or nil]
  def last
    req = @rec.reqs.last
    u = URI.parse("https://x#{req.path}")
    json = req['content-type'] == 'application/json' && !req.body.to_s.empty?
    [req.method, u.path, URI.decode_www_form(u.query || '').to_h, json ? JSON.parse(req.body) : nil]
  end

  def assert_invalid(&blk)
    @rec = Recorder.new
    e = assert_raises(K9o::KError, &blk)
    assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
    assert_empty @rec.reqs
  end

  def test_list_wire
    c = client
    c.approvals.list
    assert_equal ['GET', '/@portal/pending-approvals', {}, nil], last
    c.approvals.list(status: 'pending_approval', limit: 20)
    assert_equal ['GET', '/@portal/pending-approvals', { 'status' => 'pending_approval', 'limit' => '20' }, nil], last
    c.approvals.list(status: :rejected)
    assert_equal({ 'status' => 'rejected' }, last[2])
  end

  def test_get_wire_and_path_encoding
    c = client
    c.approvals.get('apr_1')
    assert_equal ['GET', '/@portal/pending-approvals/apr_1', {}, nil], last
    c.approvals.get('a/b c')
    assert_equal '/@portal/pending-approvals/a%2Fb%20c', @rec.reqs.last.path
  end

  def test_approve_wire
    c = client
    c.approvals.approve('apr_1')
    assert_equal ['POST', '/@portal/pending-approvals/apr_1/approve', {}, {}], last
    c.approvals.approve('apr_1', reason: 'ok')
    assert_equal ['POST', '/@portal/pending-approvals/apr_1/approve', {}, { 'reason' => 'ok' }], last
  end

  def test_reject_wire
    client.approvals.reject('apr_1', reason: 'duplicate')
    assert_equal ['POST', '/@portal/pending-approvals/apr_1/reject', {}, { 'reason' => 'duplicate' }], last
  end

  def test_bulk_wire
    c = client
    c.approvals.bulk(action: 'approve', criteria: CRITERIA)
    assert_equal ['POST', '/@portal/pending-approvals/bulk', {}, { 'action' => 'approve', 'criteria' => CRITERIA }], last
    c.approvals.bulk(action: :approve, criteria: CRITERIA, reason: 'fine')
    assert_equal({ 'action' => 'approve', 'criteria' => CRITERIA, 'reason' => 'fine' }, last[3])
    c.approvals.bulk(action: 'reject', criteria: CRITERIA, reason: 'stale')
    assert_equal({ 'action' => 'reject', 'criteria' => CRITERIA, 'reason' => 'stale' }, last[3])
  end

  def test_policies_wire
    c = client
    c.approval_policies.list
    assert_equal ['GET', '/@portal/approval-policies', {}, nil], last
    c.approval_policies.create(collection: 'orders', operation: 'update', action: 'queue', predicate: PREDICATE)
    assert_equal ['POST', '/@portal/approval-policies', {},
                  { 'collection' => 'orders', 'operation' => 'update', 'action' => 'queue', 'predicate' => PREDICATE }], last
    c.approval_policies.delete('apo_1')
    assert_equal ['DELETE', '/@portal/approval-policies/apo_1', {}, nil], last
  end

  def test_schema_collections_wire
    c = client
    c.schema.collections.list
    assert_equal ['GET', '/@portal/schema/collections', {}, nil], last
    c.schema.collections.list(limit: 2, cursor: 'dGFza3M')
    assert_equal ['GET', '/@portal/schema/collections', { 'limit' => '2', 'cursor' => 'dGFza3M' }, nil], last
  end

  def test_schema_page_exposes_cursor
    @rec.body = '{"data":[{"name":"orders","rowCount":1}],"meta":{"cursor":{"next":"b3JkZXJz","totalCount":null}}}'
    res = client.schema.collections.list(limit: 1)
    assert_equal 'orders', res.data[0]['name']
    assert_equal 'b3JkZXJz', res.meta.cursor.next
  end

  def test_approve_keeps_pending_status
    @rec.body = '{"data":{"id":"apr_1","status":"pending_approval"},"meta":{}}'
    assert_equal 'pending_approval', client.approvals.approve('apr_1').data['status']
  end

  def test_bad_limits
    [0, 201, -1, 1.5, '10', true].each do |limit|
      c = client
      assert_invalid { c.approvals.list(limit: limit) }
      assert_invalid { c.schema.collections.list(limit: limit) }
    end
    [1, 200].each { |limit| client.approvals.list(limit: limit) }
  end

  def test_bad_cursor
    c = client
    assert_invalid { c.schema.collections.list(cursor: 5) }
  end

  def test_reject_needs_reason
    c = client
    [nil, '', '   ', 5].each { |r| assert_invalid { c.approvals.reject('apr_1', reason: r) } }
  end

  def test_ids_must_be_non_empty_strings
    c = client
    ['', nil, 5].each do |bad|
      assert_invalid { c.approvals.get(bad) }
      assert_invalid { c.approvals.approve(bad) }
      assert_invalid { c.approvals.reject(bad, reason: 'x') }
      assert_invalid { c.approval_policies.delete(bad) }
    end
  end

  def test_bulk_validation
    c = client
    ['', 'delete', nil, 'APPROVE'].each do |a|
      assert_invalid { c.approvals.bulk(action: a, criteria: CRITERIA, reason: 'x') }
    end
    [nil, [], [CRITERIA], 'eq', 5].each { |cr| assert_invalid { c.approvals.bulk(action: 'approve', criteria: cr) } }
    [nil, '', '  '].each { |r| assert_invalid { c.approvals.bulk(action: 'reject', criteria: CRITERIA, reason: r) } }
  end

  def test_policy_validation
    c = client
    ['', '1orders', 'or-ders', 'a b', 'x' * 64, nil, 5].each do |col|
      assert_invalid { c.approval_policies.create(collection: col, operation: 'update', action: 'queue', predicate: PREDICATE) }
    end
    ['', 'upsert', nil, 'UPDATE'].each do |op|
      assert_invalid { c.approval_policies.create(collection: 'orders', operation: op, action: 'queue', predicate: PREDICATE) }
    end
    ['', 'approve', nil].each do |act|
      assert_invalid { c.approval_policies.create(collection: 'orders', operation: 'update', action: act, predicate: PREDICATE) }
    end
    [nil, [], [PREDICATE], 'gt', 5, true].each do |pred|
      assert_invalid { c.approval_policies.create(collection: 'orders', operation: 'update', action: 'queue', predicate: pred) }
    end
  end

  def test_policy_collection_bounds_accepted
    c = client
    %w[_orders Orders1].push('x' * 63).each do |col|
      c.approval_policies.create(collection: col, operation: 'insert', action: 'queue', predicate: PREDICATE)
      assert_equal col, last[3]['collection']
    end
  end

  def test_missing_keyword_is_argument_error
    assert_raises(ArgumentError) { client.approval_policies.create(collection: 'orders') }
    assert_raises(ArgumentError) { client.approvals.reject('apr_1') }
  end

  def test_requires_project_slug
    c = client(project_slug: nil)
    [-> { c.approvals.list }, -> { c.approval_policies.list }, -> { c.schema.collections.list }].each do |call|
      e = assert_raises(K9o::KError, &call)
      assert_equal 'K9O_MISSING_PROJECT_CONTEXT', e.code
    end
    assert_empty @rec.reqs
  end

  def test_every_public_method_is_covered
    assert_equal %i[approve bulk get list reject], K9o::Approvals.public_instance_methods(false).sort
    assert_equal %i[create delete list], K9o::ApprovalPolicies.public_instance_methods(false).sort
    assert_equal %i[list], K9o::SchemaCollections.public_instance_methods(false).sort
  end
end
