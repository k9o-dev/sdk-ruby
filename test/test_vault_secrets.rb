# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/k9o'

# `client.kibo.vault.secrets.*` wire-shape tests - the full family:
# list / get / create / reveal_challenge / reveal / update / rotate / move /
# delete. Verifies URL/query/method/body against the LIVE-VERIFIED contract
# (not just the documented OpenAPI schema, which is inaccurate for
# update/rotate/move's response shape), including:
#   - `region` required on every named-secret op except `list`
#   - `value` base64-encoded on write, base64-decoded on reveal
#   - the `X-K9O-Reveal-Challenge` header on `reveal`
#
# Net::HTTP is stubbed via a fake http_client (same pattern as test_p6.rb) —
# no real network calls.
class VaultSecretsTest < Minitest::Test
  class FakeResponse
    def initialize(code, body)
      @code = code
      @body = body
    end
    attr_reader :code, :body
  end

  class FakeHttp
    attr_reader :last_method, :last_path, :last_body, :last_request, :paths
    attr_accessor :use_ssl, :read_timeout

    def initialize(json, status: '200')
      @json = json
      @status = status
      @paths = []
    end

    def request(req)
      @last_method = req.method
      @last_path = req.path
      @paths << req.path if req.path.start_with?('/@')
      @last_body = req.body
      @last_request = req
      return FakeResponse.new('204', nil) if @status == '204'

      json = @json
      json = (json.length > 1 ? json.shift : json.first) if json.is_a?(Array) && req.path.start_with?('/@')
      json = json.first if json.is_a?(Array)
      FakeResponse.new(@status, json)
    end
  end

  SUMMARY = {
    'id' => 'sec_abc', 'name' => 'db/pw', 'ownerId' => 'usr_1',
    'visibility' => { 'kind' => 'private' }, 'version' => 1,
    'kid' => 'vkey_1', 'createdAt' => 't', 'createdBy' => 'usr_1',
    'updatedAt' => 't', 'updatedBy' => 'usr_1',
    'rotatedAt' => nil, 'retiredAt' => nil, 'metadata' => {}
  }.freeze

  def client_and_fake(json, status: '200')
    fake = FakeHttp.new(json, status: status)
    c = K9o.create_client(base_url: 'https://acme.api.k9o.io', project_slug: 'member-portal', http_client: fake)
    [c, fake]
  end

  def test_list_gets_vault_secrets_with_prefix_cursor_limit_no_region
    c, fake = client_and_fake(JSON.dump({ 'data' => { 'secrets' => [SUMMARY], 'nextCursor' => nil }, 'meta' => {} }))
    env = c.kibo.vault.secrets.list(prefix: 'db/', limit: 10)
    assert_equal 'GET', fake.last_method
    assert_equal '/@member-portal/vault/secrets?prefix=db%2F&limit=10', fake.last_path
    assert_equal 'sec_abc', env.data['secrets'][0]['id']
  end

  def test_list_omits_query_entirely_when_no_filters_given
    c, fake = client_and_fake(JSON.dump({ 'data' => { 'secrets' => [], 'nextCursor' => nil }, 'meta' => {} }))
    c.kibo.vault.secrets.list
    assert_equal '/@member-portal/vault/secrets', fake.last_path
  end

  def page(secrets, cursor = nil)
    JSON.dump({ 'data' => { 'secrets' => secrets, 'nextCursor' => cursor }, 'meta' => {} })
  end

  def test_get_reads_metadata_from_the_list_route_exact_name
    c, fake = client_and_fake(page([SUMMARY.merge('name' => 'db/pw-old'), SUMMARY]))
    env = c.kibo.vault.secrets.get('db/pw')
    assert_equal 'GET', fake.last_method
    assert_equal '/@member-portal/vault/secrets?prefix=db%2Fpw&limit=100', fake.last_path
    assert_equal 'db/pw', env.data['name']
    refute(fake.paths.any? { |p| p.start_with?('/@member-portal/vault/secrets/') })
  end

  def test_get_does_not_send_region_even_when_given
    c, fake = client_and_fake(page([SUMMARY]))
    c.kibo.vault.secrets.get('db/pw', region: 'us01')
    refute_includes fake.last_path, 'region'
  end

  def test_get_follows_next_cursor
    c, fake = client_and_fake([page([SUMMARY.merge('name' => 'db/pw-old')], 'cur1'), page([SUMMARY])])
    env = c.kibo.vault.secrets.get('db/pw')
    assert_equal 2, fake.paths.length
    assert_equal '/@member-portal/vault/secrets?prefix=db%2Fpw&cursor=cur1&limit=100', fake.paths[1]
    assert_equal 'sec_abc', env.data['id']
  end

  def test_get_not_found_is_404
    c, fake = client_and_fake(page([SUMMARY.merge('name' => 'db/pw-old')]))
    e = assert_raises(K9o::KError) { c.kibo.vault.secrets.get('db/pw') }
    assert_equal 'K9O_NOT_FOUND', e.code
    assert_equal 404, e.status
    assert_equal "No secret named 'db/pw' in this project.", e.message
    assert_equal 1, fake.paths.length
  end

  def test_get_stops_after_max_pages
    c, fake = client_and_fake(page([], 'again'))
    e = assert_raises(K9o::KError) { c.kibo.vault.secrets.get('db/pw') }
    assert_equal 'K9O_NOT_FOUND', e.code
    assert_equal 20, fake.paths.length
  end

  def test_create_posts_with_region_query_and_base64_encoded_value
    c, fake = client_and_fake(JSON.dump({ 'data' => SUMMARY, 'meta' => {} }))
    c.kibo.vault.secrets.create(name: 'db/pw', value: 'hunter2', region: 'us01',
                                 visibility: { 'kind' => 'private' })
    assert_equal 'POST', fake.last_method
    assert_equal '/@member-portal/vault/secrets/db%2Fpw?region=us01', fake.last_path
    body = JSON.parse(fake.last_body)
    assert_equal Base64.strict_encode64('hunter2'), body['value']
    refute_equal 'hunter2', body['value']
    assert_equal({ 'kind' => 'private' }, body['visibility'])
  end

  def test_reveal_challenge_posts_op_reveal_challenge_with_region
    c, fake = client_and_fake(JSON.dump({ 'data' => { 'challenge' => 'rvc_1', 'expiresAt' => 't' }, 'meta' => {} }))
    env = c.kibo.vault.secrets.reveal_challenge('db/pw', region: 'us01')
    assert_equal 'POST', fake.last_method
    assert_includes fake.last_path, 'op=reveal-challenge'
    assert_includes fake.last_path, 'region=us01'
    assert_equal 'rvc_1', env.data['challenge']
  end

  def test_reveal_gets_with_challenge_header_and_decodes_base64_value
    wire_value = Base64.strict_encode64('hunter2')
    payload = {
      'id' => 'sec_abc', 'name' => 'db/pw', 'version' => 1, 'value' => wire_value,
      'revealedAt' => 't', 'attestationTier' => { 'urn' => 'u', 'operator' => 'platform', 'verified' => true }
    }
    c, fake = client_and_fake(JSON.dump({ 'data' => payload, 'meta' => {} }))
    env = c.kibo.vault.secrets.reveal('db/pw', region: 'us01', challenge: 'rvc_1')
    assert_equal 'GET', fake.last_method
    assert_equal 'rvc_1', fake.last_request['X-K9O-Reveal-Challenge']
    assert_equal 'hunter2', env.data['value']
    assert_equal 'platform', env.data['attestationTier']['operator']
  end

  def test_update_puts_with_region_query_and_base64_value_returns_narrow_shape
    c, fake = client_and_fake(JSON.dump({ 'data' => { 'id' => 'sec_abc', 'name' => 'db/pw', 'version' => 2 }, 'meta' => {} }))
    env = c.kibo.vault.secrets.update('db/pw', region: 'us01', value: 'newpw')
    assert_equal 'PUT', fake.last_method
    assert_equal '/@member-portal/vault/secrets/db%2Fpw?region=us01', fake.last_path
    assert_equal Base64.strict_encode64('newpw'), JSON.parse(fake.last_body)['value']
    assert_equal 2, env.data['version']
  end

  def test_rotate_posts_op_rotate_with_region_no_body
    c, fake = client_and_fake(JSON.dump({
                                           'data' => { 'id' => 'sec_abc', 'name' => 'db/pw', 'version' => 2,
                                                       'rotatedAt' => 't', 'ledgerSequenceNumber' => 2 },
                                           'meta' => {}
                                         }))
    env = c.kibo.vault.secrets.rotate('db/pw', region: 'us01')
    assert_equal 'POST', fake.last_method
    assert_includes fake.last_path, 'op=rotate'
    assert_nil fake.last_body
    assert_equal 2, env.data['ledgerSequenceNumber']
  end

  def test_move_posts_op_move_with_new_path_body
    c, fake = client_and_fake(JSON.dump({ 'data' => { 'id' => 'sec_abc', 'name' => 'db/pw2', 'event' => 'SECRET_PATH_CHANGED' }, 'meta' => {} }))
    env = c.kibo.vault.secrets.move('db/pw', region: 'us01', new_path: 'db/pw2')
    assert_equal 'POST', fake.last_method
    assert_includes fake.last_path, 'op=move'
    assert_equal({ 'newPath' => 'db/pw2' }, JSON.parse(fake.last_body))
    assert_equal 'SECRET_PATH_CHANGED', env.data['event']
  end

  def test_delete_deletes_with_region_and_handles_204
    c, fake = client_and_fake(nil, status: '204')
    env = c.kibo.vault.secrets.delete('db/pw', region: 'us01')
    assert_equal 'DELETE', fake.last_method
    assert_equal '/@member-portal/vault/secrets/db%2Fpw?region=us01', fake.last_path
    assert_nil env.data
  end

  def test_secrets_require_project_slug
    c = K9o.create_client(base_url: 'https://api.k9o.io')
    e = assert_raises(K9o::KError) { c.kibo.vault.secrets.get('db/pw') }
    assert_equal 'K9O_MISSING_PROJECT_CONTEXT', e.code
  end

  def test_region_is_optional_and_omitted_when_not_given
    c, fake = client_and_fake(JSON.dump({ 'data' => SUMMARY, 'meta' => {} }))
    sec = c.kibo.vault.secrets
    sec.create(name: 'db/pw', value: 'x')
    assert_equal '/@member-portal/vault/secrets/db%2Fpw', fake.last_path
    sec.update('db/pw', value: 'x')
    assert_equal '/@member-portal/vault/secrets/db%2Fpw', fake.last_path
    sec.reveal_challenge('db/pw')
    assert_equal '/@member-portal/vault/secrets/db%2Fpw?op=reveal-challenge', fake.last_path
    sec.rotate('db/pw')
    assert_equal '/@member-portal/vault/secrets/db%2Fpw?op=rotate', fake.last_path
    sec.move('db/pw', new_path: 'z')
    assert_equal '/@member-portal/vault/secrets/db%2Fpw?op=move', fake.last_path
    sec.reveal('db/pw', challenge: 'rvc_1')
    assert_equal '/@member-portal/vault/secrets/db%2Fpw', fake.last_path
  end

  def test_delete_without_region_and_accepts_200
    c, fake = client_and_fake(JSON.dump({ 'data' => { 'id' => 'sec_abc' }, 'meta' => {} }))
    env = c.kibo.vault.secrets.delete('db/pw')
    assert_equal 'DELETE', fake.last_method
    assert_equal '/@member-portal/vault/secrets/db%2Fpw', fake.last_path
    assert_equal 'sec_abc', env.data['id']
  end
end
