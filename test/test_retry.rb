# frozen_string_literal: true

require 'minitest/autorun'
require 'k9o'

module K9o
  # Retry + backoff behaviour. Idempotent methods are retried on
  # transient failures (transport / 502 / 503 / 504 / 429); semantic 4xx and
  # non-idempotent methods are not. The retry policy is exercised directly
  # via HttpTransport.retry_with_backoff with a block (no live HTTP).
  class RetryTest < Minitest::Test
    NO_SLEEP = RetryConfig.new(max_retries: 2, backoff: 'none', initial_delay_ms: 0, max_delay_ms: 0)

    def transient
      KError.new(code: 'K9O_UPSTREAM_UNAVAILABLE', message: 'down', status: 503)
    end

    def test_get_retries_transient_then_succeeds
      calls = 0
      result = HttpTransport.retry_with_backoff('GET', NO_SLEEP) do
        calls += 1
        raise transient if calls < 3

        Envelope.new(data: nil, meta: Meta.new)
      end
      assert_equal 3, calls # 2 failures + 1 success
      refute_nil result
    end

    def test_get_exhausts_retries
      calls = 0
      assert_raises(KError) do
        HttpTransport.retry_with_backoff('GET', NO_SLEEP) do
          calls += 1
          raise transient
        end
      end
      assert_equal 3, calls # max_retries (2) + 1 initial
    end

    def test_post_not_retried
      calls = 0
      assert_raises(KError) do
        HttpTransport.retry_with_backoff('POST', NO_SLEEP) do
          calls += 1
          raise transient
        end
      end
      assert_equal 1, calls
    end

    def test_semantic_4xx_not_retried
      calls = 0
      assert_raises(KError) do
        HttpTransport.retry_with_backoff('GET', NO_SLEEP) do
          calls += 1
          raise KError.new(code: 'K9O_NOT_FOUND', message: 'nope', status: 404)
        end
      end
      assert_equal 1, calls
    end

    def test_retryable_matrix
      down = KError.new(code: 'K9O_UPSTREAM_UNAVAILABLE', message: 'down')
      five03 = KError.new(code: 'X', message: 'x', status: 503)
      four04 = KError.new(code: 'K9O_NOT_FOUND', message: 'x', status: 404)
      assert HttpTransport.retryable?(down, 'GET')
      assert HttpTransport.retryable?(five03, 'DELETE')
      refute HttpTransport.retryable?(five03, 'POST')
      refute HttpTransport.retryable?(four04, 'GET')
    end

    def test_compute_delay
      none = RetryConfig.new(backoff: 'none')
      assert_equal 0, HttpTransport.compute_delay_ms(none, 0)

      exp = RetryConfig.new(backoff: 'exponential', initial_delay_ms: 100, max_delay_ms: 5000)
      d = HttpTransport.compute_delay_ms(exp, 0) # base 100, ±25% ⇒ [75, 125]
      assert d >= 75
      assert d <= 125
    end
  end
end
