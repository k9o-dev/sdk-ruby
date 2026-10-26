# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/k9o'

class StorageTest < Minitest::Test
  Resp = Struct.new(:code, :body, :headers) do
    def [](k)
      headers[k.to_s.downcase]
    end
  end

  # Stub transport: records every request, answers with a canned response.
  class Fake
    attr_reader :reqs
    attr_accessor :use_ssl, :read_timeout

    def initialize(status = '200', payload = { 'data' => nil, 'meta' => {} })
      @status = status
      @payload = payload
      @reqs = []
    end

    def request(req)
      @reqs << req
      Resp.new(@status, JSON.dump(@payload), {})
    end
  end

  ROOT = '/@member-portal/storage/buckets'

  def mk(fake, **opts)
    K9o.create_client(base_url: 'https://api.k9o.io', project_slug: 'member-portal', http_client: fake, **opts)
  end

  def last(fake)
    fake.reqs.last
  end

  def vu(req)
    [req.method, req.path]
  end

  def test_list_buckets
    f = Fake.new
    mk(f).storage.list_buckets
    assert_equal ['GET', ROOT], vu(last(f))
  end

  def test_get_bucket_encodes_name
    f = Fake.new
    mk(f).storage.get_bucket('avatars')
    assert_equal ['GET', "#{ROOT}/avatars"], vu(last(f))
    mk(f).storage.get_bucket('a/b c')
    assert_equal "#{ROOT}/a%2Fb%20c", last(f).path
  end

  def test_create_bucket_posts_json
    f = Fake.new
    mk(f).storage.create_bucket('avatars', public: false, file_size_limit: 10_485_760,
                                           allowed_mime_types: ['image/png'], versioning: true)
    r = last(f)
    assert_equal ['POST', ROOT], vu(r)
    assert_equal({ 'name' => 'avatars', 'public' => false, 'fileSizeLimit' => 10_485_760,
                   'allowedMimeTypes' => ['image/png'], 'versioning' => true }, JSON.parse(r.body))
    assert_equal 'application/json', r['content-type']
  end

  def test_update_bucket_patches_and_nil_clears
    f = Fake.new
    mk(f).storage.update_bucket('avatars', file_size_limit: nil, delete_after_days: 30)
    r = last(f)
    assert_equal ['PATCH', "#{ROOT}/avatars"], vu(r)
    assert_equal({ 'fileSizeLimit' => nil, 'deleteAfterDays' => 30 }, JSON.parse(r.body))
  end

  def test_delete_bucket_empty_query
    f = Fake.new
    s = mk(f).storage
    s.delete_bucket('avatars')
    assert_equal ['DELETE', "#{ROOT}/avatars"], vu(last(f))
    s.delete_bucket('avatars', empty: true)
    assert_equal "#{ROOT}/avatars?empty=true", last(f).path
    s.delete_bucket('avatars', empty: false)
    assert_equal "#{ROOT}/avatars", last(f).path
  end

  def test_upload_is_real_multipart
    f = Fake.new
    mk(f).storage.from('avatars').upload('user/a.jpg', "\x01\x02\x03".b, content_type: 'image/jpeg',
                                                                        upsert: true, metadata: { 'userId' => 'u1' })
    r = last(f)
    assert_equal ['POST', "#{ROOT}/avatars/objects"], vu(r)
    ct = r['content-type']
    refute_includes ct, 'json'
    assert_match(%r{\Amultipart/form-data; boundary=\S+\z}, ct)
    boundary = ct[/boundary=(\S+)/, 1]
    body = r.body
    assert body.start_with?("--#{boundary}\r\n")
    assert body.end_with?("--#{boundary}--\r\n")
    chunks = body.split("--#{boundary}").reject { |c| c.empty? || c == "--\r\n" }
    assert_equal 5, chunks.size
    assert_includes body, %(Content-Disposition: form-data; name="file"; filename="a.jpg"\r\nContent-Type: image/jpeg\r\n\r\n\x01\x02\x03\r\n).b
    assert_includes body, %(name="path"\r\n\r\nuser/a.jpg\r\n)
    assert_includes body, %(name="contentType"\r\n\r\nimage/jpeg\r\n)
    assert_includes body, %(name="upsert"\r\n\r\ntrue\r\n)
    assert_includes body, %(name="metadata"\r\n\r\n{"userId":"u1"}\r\n)
  end

  def test_upload_defaults_and_string_utf8
    f = Fake.new
    mk(f).storage.from('docs').upload('a.txt', 'héllo')
    body = last(f).body
    assert_includes body, %(name="upsert"\r\n\r\nfalse\r\n)
    refute_includes body, 'name="contentType"'
    refute_includes body, 'name="metadata"'
    assert_includes body, "\r\n\r\nhéllo\r\n".b
  end

  def test_upload_accepts_io
    require 'stringio'
    f = Fake.new
    mk(f).storage.from('docs').upload('a.bin', StringIO.new('xyz'))
    assert_includes last(f).body, "\r\n\r\nxyz\r\n"
  end

  def test_signed_url_body_and_bounds
    f = Fake.new
    h = mk(f).storage.from('avatars')
    h.create_signed_url('a.jpg', expires_in: 300, download: true)
    r = last(f)
    assert_equal ['POST', "#{ROOT}/avatars/objects/sign"], vu(r)
    assert_equal({ 'path' => 'a.jpg', 'expiresIn' => 300, 'download' => true }, JSON.parse(r.body))
    [1, 604_800].each do |ok|
      h.create_signed_url('a.jpg', expires_in: ok)
      assert_equal ok, JSON.parse(last(f).body)['expiresIn']
    end
    refute JSON.parse(last(f).body).key?('download')
    before = f.reqs.size
    [0, -1, 604_801, 1.5, 300.0, nil, '300', true].each do |bad|
      err = assert_raises(K9o::KError, bad.inspect) { h.create_signed_url('a.jpg', expires_in: bad) }
      assert_equal 'K9O_INVALID_FIELD_VALUE', err.code
    end
    assert_equal before, f.reqs.size, 'no request on refusal'
  end

  def test_signed_url_requires_expires_in_keyword
    h = mk(Fake.new).storage.from('avatars')
    assert_raises(ArgumentError) { h.create_signed_url('a.jpg') }
  end

  def test_no_signed_put_or_copy
    h = mk(Fake.new).storage.from('avatars')
    refute_respond_to h, :create_signed_upload_url
    refute_respond_to h, :copy
  end

  def test_list_prefix
    f = Fake.new
    h = mk(f).storage.from('avatars')
    h.list
    assert_equal "#{ROOT}/avatars/objects", last(f).path
    h.list(prefix: 'user/ a&b')
    assert_equal "#{ROOT}/avatars/objects?prefix=user%2F+a%26b", last(f).path
  end

  def test_remove_query_encoding
    f = Fake.new
    mk(f).storage.from('avatars').remove('a b&c.jpg')
    assert_equal ['DELETE', "#{ROOT}/avatars/objects?path=a+b%26c.jpg"], vu(last(f))
  end

  def test_dotdot_and_leading_slash_encoded_not_rewritten
    f = Fake.new
    h = mk(f).storage.from('avatars')
    h.remove('../x')
    assert_equal "#{ROOT}/avatars/objects?path=..%2Fx", last(f).path
    h.remove('/abs')
    assert_equal "#{ROOT}/avatars/objects?path=%2Fabs", last(f).path
    mk(f).storage.from('../b').list
    assert_equal "#{ROOT}/..%2Fb/objects", last(f).path
  end

  def test_empty_names_refused_before_request
    f = Fake.new
    c = mk(f)
    [-> { c.storage.from('avatars').upload('', 'x') },
     -> { c.storage.from('avatars').remove('') },
     -> { c.storage.from('avatars').create_signed_url('', expires_in: 60) },
     -> { c.storage.get_bucket('') }].each do |call|
      assert_equal 'K9O_INVALID_FIELD_VALUE', assert_raises(K9o::KError) { call.call }.code
    end
    assert_empty f.reqs
  end

  def test_dot_segment_bucket_names_refused_before_request
    f = Fake.new
    c = mk(f)
    ['.', '..'].each do |n|
      [-> { c.storage.get_bucket(n) },
       -> { c.storage.update_bucket(n, { 'public' => true }) },
       -> { c.storage.delete_bucket(n) },
       -> { c.storage.from(n).upload('p', 'x') },
       -> { c.storage.from(n).create_signed_url('p', expires_in: 60) },
       -> { c.storage.from(n).list },
       -> { c.storage.from(n).remove('p') }].each do |call|
        err = assert_raises(K9o::KError) { call.call }
        assert_equal 'K9O_INVALID_FIELD_VALUE', err.code
        assert_equal 'dot_segment', err.context[:reason]
        assert_equal 'bucket', err.context[:field]
      end
    end
    assert_empty f.reqs
    c.storage.get_bucket('avatars')
    assert_equal 1, f.reqs.size
  end

  def test_missing_slug_refused
    f = Fake.new
    c = K9o.create_client(base_url: 'https://api.k9o.io', http_client: f)
    [-> { c.storage.list_buckets }, -> { c.storage.from('a').list },
     -> { c.storage.from('a').upload('p', 'x') }].each do |call|
      assert_equal 'K9O_MISSING_PROJECT_CONTEXT', assert_raises(K9o::KError) { call.call }.code
    end
    assert_empty f.reqs
  end

  def test_409_passthrough
    f = Fake.new('409', { 'code' => 'K9O_CONFLICT', 'message' => 'bucket_not_empty' })
    err = assert_raises(K9o::KError) { mk(f).storage.delete_bucket('avatars') }
    assert_equal 409, err.status
    assert_includes err.message, 'bucket_not_empty'
  end

  def test_invalid_bucket_name_passthrough_and_no_bytes_in_error
    f = Fake.new('400', { 'code' => 'K9O_INVALID_BUCKET_NAME', 'message' => 'bad name' })
    err = assert_raises(K9o::KError) { mk(f).storage.from('Bad').upload('a.txt', 'TOPSECRETBYTES') }
    assert_equal 'K9O_INVALID_BUCKET_NAME', err.code
    refute_includes err.to_s, 'TOPSECRETBYTES'
    refute_includes err.context.to_s, 'TOPSECRETBYTES'
  end

  def test_bad_data_type_error_has_no_bytes
    err = assert_raises(K9o::KError) { mk(Fake.new).storage.from('a').upload('p', 12_345) }
    assert_equal 'K9O_INVALID_FIELD_VALUE', err.code
  end

  def test_credentials_and_headers_go_with_request
    f = Fake.new
    mk(f, api_key: 'k').storage.from('a').upload('p', 'x')
    assert_equal 'Bearer k', last(f)['authorization']
    assert_equal 'member-portal', last(f)['x-k9o-project-slug']
  end
end
