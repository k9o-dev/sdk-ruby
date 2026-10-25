# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/k9o'

class KErrorTest < Minitest::Test
  def test_constructs_with_required_fields
    e = K9o::KError.new(code: 'K9O_INVALID_FIELD_VALUE', message: 'bad')
    assert_equal 'K9O_INVALID_FIELD_VALUE', e.code
    assert_equal 'bad', e.message
    assert_equal({}, e.context)
    assert_nil e.recommendation
    assert_nil e.status
  end

  def test_is_raisable
    assert_raises(K9o::KError) { raise K9o::KError.new(code: 'X', message: 'y') }
  end

  def test_to_s_includes_status
    e = K9o::KError.new(code: 'K9O_TIER_CAP_HIT', message: 'cap', status: 429)
    s = e.to_s
    assert_includes s, 'K9O_TIER_CAP_HIT'
    assert_includes s, '429'
  end

  def test_with_recommendation
    e = K9o::KError.new(code: 'X', message: 'y').with_recommendation('do this')
    assert_equal 'do this', e.recommendation
  end

  def test_from_wire_rehydration
    e = K9o::KError.from_wire({
      'code' => 'K9O_TIER_CAP_HIT',
      'message' => 'cap',
      'context' => { 'dim' => 'mau' },
      'recommendation' => 'upgrade',
      'requestId' => 'req_x'
    }, 429)
    assert_equal 'K9O_TIER_CAP_HIT', e.code
    assert_equal 429, e.status
    assert_equal 'req_x', e.request_id
    assert_equal({ 'dim' => 'mau' }, e.context)
  end
end
