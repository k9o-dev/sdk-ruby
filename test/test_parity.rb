# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/k9o'

# Full-coverage parity tests for the namespaces bringing Ruby to TS
# surface parity: migrations / functions / policies / audit / orgs / me /
# full org. Net::HTTP stubbed via a fake http_client to assert URL +
# method composition.
class ParityTest < Minitest::Test
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

  def org_client(json)
    fake = FakeHttp.new(json)
    c = K9o.create_client(base_url: 'https://acme.api.k9o.io', http_client: fake)
    [c, fake]
  end

  def test_migrations_apply
    c, fake = project_client('{"data":{"applied":[]},"meta":{}}')
    b = K9o::Migrations::Build
    migration = b.migration(
      version: 1, slug: 'init',
      up: [
        b.create_table(
          name: 'posts',
          columns: [
            b.column(name: 'id', type: 'uuid', primary_key: true),
            b.column(name: 'email', type: 'text', not_null: true,
                     encrypted: b.column_encryption(store: 'vault', searchable: true)),
            b.column(name: 'author_id', type: 'uuid',
                     references: b.references(collection: 'users', on: 'id', on_delete: 'CASCADE'))
          ],
          indexes: [b.index(columns: %w[author_id], name: 'posts_author_idx')]
        )
      ],
      down: [b.drop_table('posts')]
    )
    c.migrations.apply([migration])

    assert_equal 'POST', fake.last_method
    assert_equal '/@portal/migrations/apply', fake.last_path

    body = JSON.parse(fake.last_body)
    mig = body['migrations'].first
    assert_equal 1, mig['version']
    assert_equal 'init', mig['slug']

    ct = mig['up'].first['create_table']
    assert_equal 'posts', ct['name']
    # encrypted object form with NESTED searchable (not a sibling).
    email_col = ct['columns'].find { |col| col['name'] == 'email' }
    assert_equal({ 'store' => 'vault', 'searchable' => true }, email_col['encrypted'])
    refute email_col.key?('searchable'), 'searchable must be nested inside encrypted, not a sibling'
    # snake_case wire keys.
    pk_col = ct['columns'].find { |col| col['name'] == 'id' }
    assert_equal true, pk_col['primary_key']
    fk = ct['columns'].find { |col| col['name'] == 'author_id' }['references']
    assert_equal 'CASCADE', fk['on_delete']
    # key-tagged down op.
    assert_equal 'posts', mig['down'].first['drop_table']
  end

  def test_functions_invoke
    c, fake = project_client('{"data":{"ok":true},"meta":{}}')
    c.functions.invoke('greet', { 'name' => 'World' })
    assert_equal '/@portal/functions/greet/invoke', fake.last_path
    assert_includes fake.last_body, 'World'
  end

  def test_policies_publish
    c, fake = project_client('{"data":{"id":"pol_x"},"meta":{}}')
    c.policies.publish('pol_x')
    assert_equal 'POST', fake.last_method
    assert_equal '/@portal/policies/pol_x/publish', fake.last_path
  end

  def test_audit_query
    c, fake = project_client('{"data":[],"meta":{}}')
    c.audit.query(event_type: 'data.write.access.insert', limit: 50)
    assert_includes fake.last_path, '/@portal/audit-log'
    assert_includes fake.last_path, 'eventType=data.write.access.insert'
  end

  def test_orgs_collection
    c, fake = org_client('{"data":{"id":"org_x","slug":"acme"},"meta":{}}')
    c.orgs.restore('org_x')
    assert_equal 'POST', fake.last_method
    assert_equal '/orgs/org_x/restore', fake.last_path
  end

  def test_me_namespaces
    c, fake = org_client('{"data":{},"meta":{}}')
    c.me.profile.get
    assert_equal '/me', fake.last_path
    c.me.sessions.revoke_all
    assert_equal 'POST', fake.last_method
    assert_equal '/me/sessions/revoke-all', fake.last_path
    c.me.api_tokens.create(label: 'ci', scope_manifest: { 'operations' => ['read'] })
    assert_equal '/me/api-tokens', fake.last_path
  end

  def test_org_full_surfaces
    c, fake = org_client('{"data":"mistral-7b","meta":{}}')
    c.org.members.invite(email: 'x@y.com', role: 'ORG_MEMBER')
    assert_equal 'POST', fake.last_method
    assert_equal '/members', fake.last_path
    c.org.gate.roles.grant(user_id: 'u_a', role: 'ORG_ADMIN')
    assert_equal '/role-grants', fake.last_path
    c.org.smtp.set(host: 'smtp.x.com', port: 587, username: 'u', password_ref: 'ref_1',
                   from_address: 'n@x.com', from_name: 'X')
    assert_equal 'PATCH', fake.last_method
    assert_includes fake.last_body, 'smtpConfig'
    c.org.default_llm.get
    assert_equal '/default-llm', fake.last_path
  end

  def test_migrations_require_project_slug
    c = K9o.create_client(base_url: 'https://api.k9o.io')
    e = assert_raises(K9o::KError) { c.migrations.list }
    assert_equal 'K9O_MISSING_PROJECT_CONTEXT', e.code
  end
end
