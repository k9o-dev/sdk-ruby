# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/k9o'

# client.query, client.search, select.text_search / vector_search: wire shape, shared vectors, validation.
class QuerySearchTest < Minitest::Test
  Resp = Struct.new(:code, :body)

  class Recorder
    attr_reader :reqs
    attr_accessor :use_ssl, :read_timeout

    def initialize
      @reqs = []
    end

    def request(req)
      @reqs << req
      Resp.new('200', '{"data":[{"id":"u1"}],"meta":{"rawQuery":{"intent":"read","rowCount":1}}}')
    end
  end

  def client
    @rec = Recorder.new
    K9o.create_client(base_url: 'https://acme.api-de01.k9o.io', api_key: 'k', project_slug: 'demo', http_client: @rec)
  end

  def last
    req = @rec.reqs.last
    u = URI.parse("https://x#{req.path}")
    [req.method, u.path, URI.decode_www_form(u.query || '').to_h, req.body.to_s.empty? ? nil : JSON.parse(req.body)]
  end

  def translate(sql, named)
    K9o::Query.translate_named_params(sql, named)
  end

  def test_shared_vectors
    {
      1 => ["SELECT * FROM users WHERE data->>'role' = :role", { role: 'admin' },
            "SELECT * FROM users WHERE data->>'role' = $1", ['admin']],
      2 => ['SELECT :a, :b, :a', { a: 1, b: 2 }, 'SELECT $1, $2, $1', [1, 2]],
      3 => ["SELECT ':not_a_param', \":also_not\", x::int FROM t WHERE y = :y", { y: true },
            "SELECT ':not_a_param', \":also_not\", x::int FROM t WHERE y = $1", [true]],
      4 => ["SELECT 'it''s :no' , :v -- :comment\nFROM t", { v: nil },
            "SELECT 'it''s :no' , $1 -- :comment\nFROM t", [nil]],
      5 => ['SELECT /* :c /* :d */ :e */ :f', { f: 1 }, 'SELECT /* :c /* :d */ :e */ $1', [1]],
      6 => ['SELECT $$ :x $$, $q$ :y $q$, :z', { z: 's' }, 'SELECT $$ :x $$, $q$ :y $q$, $1', ['s']],
      7 => ['SELECT arr[1:2], a:b, :n', { n: 5 }, 'SELECT arr[1:2], a:b, $1', [5]]
    }.each do |num, (sql, named, out, params)|
      assert_equal [out, params], translate(sql, named), "vector #{num}"
    end
  end

  def test_string_keys_extra_keys_and_escape_strings
    assert_equal ['SELECT E\'a\\\' :x\', $1', [1]], translate("SELECT E'a\\' :x', :y", { 'y' => 1, 'z' => 2 })
  end

  def test_vector_8_missing_value
    e = assert_raises(K9o::KError) { translate('SELECT :missing', {}) }
    assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
    assert_includes e.message, ':missing'
  end

  def test_vector_9_non_bindable_value
    e = assert_raises(K9o::KError) { translate('SELECT :a', { a: {} }) }
    assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
  end

  def test_query_named_params_wire
    r = client.query("SELECT * FROM users WHERE data->>'role' = :role", { role: 'admin' })
    assert_equal ['POST', '/@demo/query', {},
                  { 'sql' => "SELECT * FROM users WHERE data->>'role' = $1", 'params' => ['admin'] }], last
    assert_equal [{ 'id' => 'u1' }], r.data
  end

  def test_query_hash_without_braces
    client.query('SELECT :a', a: 1)
    assert_equal({ 'sql' => 'SELECT $1', 'params' => [1] }, last[3])
  end

  def test_vector_10_list_params_unchanged
    client.query('SELECT $1', ['x'])
    assert_equal({ 'sql' => 'SELECT $1', 'params' => ['x'] }, last[3])
  end

  def test_vector_11_no_params_key
    client.query('SELECT 1')
    assert_equal({ 'sql' => 'SELECT 1' }, last[3])
  end

  def test_query_bad_values_raise_before_any_request
    c = client
    e = assert_raises(K9o::KError) { c.query('SELECT $1', [{}]) }
    assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
    assert_raises(K9o::KError) { c.query('SELECT :nope', { a: 1 }) }
    assert_empty @rec.reqs
  end

  def test_text_search_defaults_omitted
    client.from('articles').select.text_search('body', 'climate resilience').limit(5).execute
    assert_equal ['GET', '/@demo/data/articles', { 'textSearch' => 'body:climate resilience', 'limit' => '5' }, nil], last
  end

  def test_text_search_language_and_type
    client.from('articles').select.text_search('body', 'a b', language: 'french', type: 'websearch').execute
    q = last[2]
    assert_equal 'french', q['textSearchLanguage']
    assert_equal 'websearch', q['textSearchType']
  end

  def test_vector_search_wire
    client.from('articles').select.vector_search('embedding', [0.1, 0.2], metric: 'dot', limit: 10).execute
    assert_equal({ 'vectorSearch' => 'embedding:[0.1,0.2]', 'vectorMetric' => 'dot', 'vectorLimit' => '10' }, last[2])
  end

  def test_vector_search_defaults_omitted
    client.from('articles').select.vector_search('embedding', [1, 2]).execute
    assert_equal({ 'vectorSearch' => 'embedding:[1,2]' }, last[2])
  end

  def test_validation_errors
    s = client.from('articles').select
    [
      -> { s.text_search('bad col', 'x') },
      -> { s.text_search('body', '') },
      -> { s.text_search('body', 'x', language: 'fr-ench') },
      -> { s.text_search('body', 'x', type: 'fuzzy') },
      -> { s.vector_search('embedding', []) },
      -> { s.vector_search('embedding', ['a']) },
      -> { s.vector_search('embedding', [1], limit: 1001) },
      -> { s.vector_search('embedding', [1], limit: 0) },
      -> { s.vector_search('embedding', [1], metric: 'manhattan') }
    ].each_with_index do |call, i|
      e = assert_raises(K9o::KError, "case #{i}") { call.call }
      assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
    end
    assert_empty @rec.reqs
  end

  def test_search_full_text_paged
    r = client.search('articles', column: 'body', q: 'climate resilience', language: 'french', limit: 5, cursor: 'c1')
    assert_equal ['GET', '/@demo/data/articles',
                  { 'textSearch' => 'body:climate resilience', 'textSearchLanguage' => 'french', 'limit' => '5',
                    'cursor' => 'c1' }, nil], last
    assert_equal [{ 'id' => 'u1' }], r.data
  end

  def test_search_bad_column_raises_before_request
    c = client
    e = assert_raises(K9o::KError) { c.search('articles', column: 'bad col', q: 'x') }
    assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
    assert_empty @rec.reqs
    assert_raises(ArgumentError) { c.search('articles', q: 'x') }
  end
end
