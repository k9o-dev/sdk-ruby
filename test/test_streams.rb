# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/k9o'

# client.streams.subscribe: SSE resume from the last sequence across server-closed connections, and error mapping.
class StreamsTest < Minitest::Test
  # Answers each connection with the next canned body (or status + JSON error), recording the requests.
  class ScriptedHttp
    attr_accessor :use_ssl, :read_timeout
    attr_reader :reqs

    Resp = Struct.new(:code, :chunks) do
      def read_body(&blk)
        chunks.each(&blk)
      end
    end

    def initialize(responses)
      @responses = responses
      @reqs = []
    end

    def request(req)
      @reqs << req
      resp = @responses[[@reqs.size - 1, @responses.size - 1].min]
      block_given? ? yield(resp) : resp
    end
  end

  def frame(seq, data)
    ev = { 'sequence' => seq, 'subject' => 'k9o.user.x._', 'data' => data, 'publishedAt' => '2026-10-26T00:00:00Z' }
    "id: #{seq}\ndata: #{JSON.generate(ev)}\n\n"
  end

  def ok(*chunks)
    ScriptedHttp::Resp.new('200', ["retry: 1000\n:ok\n\n"] + chunks)
  end

  def client(http)
    K9o.create_client(base_url: 'https://acme.api-de01.k9o.io', api_key: 'k', project_slug: 'portal', http_client: http)
  end

  def setup
    @delay = K9o::Streams.reconnect_delay
    K9o::Streams.reconnect_delay = 0
  end

  def teardown
    K9o::Streams.reconnect_delay = @delay
  end

  def query(req)
    URI.decode_www_form(URI.parse("https://x#{req.path}").query || '').to_h
  end

  def test_subscribe_resumes_from_last_sequence_across_closed_connections
    http = ScriptedHttp.new([ok(frame('1', 'a'), frame('2', 'b')), ok(frame('3', 'c')), ok])
    events = client(http).streams.subscribe('orders-feed').first(3)
    assert_equal %w[1 2 3], events.map { |e| e['sequence'] }
    assert_equal %w[a b c], events.map { |e| e['data'] }
    assert(http.reqs.all? { |r| r.method == 'GET' && URI.parse("https://x#{r.path}").path == '/@portal/data-streams/user/orders-feed/subscribe' })
    assert_equal [{}, { 'fromSequence' => '2' }], http.reqs.map { |r| query(r) }
    assert_equal 'text/event-stream', http.reqs.first['accept']
  end

  def test_subscribe_starts_at_from_sequence_and_keeps_cursor_over_empty_connections
    http = ScriptedHttp.new([ok(frame('8', 'x')), ok, ok(frame('9', 'y'))])
    events = client(http).streams.subscribe('s', from_sequence: 7).first(2)
    assert_equal %w[8 9], events.map { |e| e['sequence'] }
    assert_equal [{ 'fromSequence' => '7' }, { 'fromSequence' => '8' }, { 'fromSequence' => '8' }], http.reqs.map { |r| query(r) }
  end

  def test_subscribe_stops_when_caller_breaks
    http = ScriptedHttp.new([ok(frame('1', 'a'), frame('2', 'b'))])
    seen = []
    client(http).streams.subscribe('s').each do |e|
      seen << e['sequence']
      break
    end
    assert_equal ['1'], seen
    assert_equal 1, http.reqs.size
  end

  def test_subscribe_503_raises_typed_error
    body = JSON.generate('code' => 'K9O_STREAM_UNAVAILABLE', 'message' => 'no plane', 'context' => {})
    http = ScriptedHttp.new([ScriptedHttp::Resp.new('503', [body])])
    err = assert_raises(K9o::KError) { client(http).streams.subscribe('s').first(1) }
    assert_equal 'K9O_STREAM_UNAVAILABLE', err.code
    assert_equal 503, err.status
  end

  def test_requires_project_slug
    c = K9o.create_client(base_url: 'https://acme.api-de01.k9o.io', api_key: 'k', http_client: ScriptedHttp.new([ok]))
    err = assert_raises(K9o::KError) { c.streams.list }
    assert_equal 'K9O_MISSING_PROJECT_CONTEXT', err.code
  end

  def test_publish_503_and_invalid_map_to_kerror
    [['K9O_STREAM_UNAVAILABLE', '503'], ['K9O_STREAM_INVALID', '400']].each do |code, status|
      body = JSON.generate('code' => code, 'message' => 'nope', 'context' => {})
      resp = Struct.new(:code, :body).new(status, body)
      http = Object.new
      http.define_singleton_method(:use_ssl=) { |_| }
      http.define_singleton_method(:read_timeout=) { |_| }
      http.define_singleton_method(:request) { |_req| resp }
      err = assert_raises(K9o::KError) { client(http).streams.publish('s', { 'a' => 1 }, subject: 'Bad') }
      assert_equal code, err.code
      assert_equal status.to_i, err.status
    end
  end
end
