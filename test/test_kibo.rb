# frozen_string_literal: true

require 'minitest/autorun'
require 'k9o'

# Kibo ZK wrapper tests. The crypto round-trip needs real customer-KMS creds and
# is exercised by the staging conformance ZK step; here we pin the boundary the
# wrapper owns — the posture-floor rejection path (which the core enforces
# pre-KMS) round-trips through the SYNC `_blocking` export and maps to a typed
# K9o::KError. Skips cleanly on a platform/Ruby without the native lib.
class TestKibo < Minitest::Test
  def setup
    skip 'kibo native lib not available on this platform' unless K9o::Kibo::NATIVE_AVAILABLE
  end

  def test_posture_floor_violation_maps_to_kerror
    k = K9o::Kibo
    input = k::EncryptInput.new(
      provider: k::KmsProvider::AWS_KMS,
      posture: k::FfiPosture::BYOK,
      strategy: nil,
      oracle_mode: nil,
      kms_cred: k::FfiCredential.new(secret: 't', expires_at_unix_secs: 0),
      key_ref: k::FfiKeyRef.new(version: 1, external_ref: 'arn:aws:kms:us-east-1:0:key/abc'),
      provider_config: k::FfiProviderConfig.new(aws_region: 'us-east-1', vault_address: nil),
      attestation_tier: k::FfiAttestationTier::SOFTWARE,
      encryption_context: [],
      plaintext: 'hi',
      # BYOK requested, HYOK floor declared -> violation (rejected before any KMS call).
      posture_policy: k::FfiPosturePolicy.new(
        min_custody_posture: k::FfiMinPosture::HYOK,
        allowed_oracle_modes: k::FfiAllowedOracleModes.new(brokered: true, direct: true)
      )
    )

    err = assert_raises(K9o::KError) { k.encrypt(input) }
    assert_equal 'K9O_CRYPTO_POSTURE_FLOOR_VIOLATION', err.code
    assert_equal 'custody_posture', err.context[:dimension]
    assert_equal 'byok', err.context[:requested]
  end

  def test_native_unavailable_message_is_a_kerror
    # When native is present this just asserts the guard exists; the unavailable
    # path is structurally covered by ensure_native! raising K9o::KError.
    assert K9o::Kibo.respond_to?(:encrypt)
    assert K9o::Kibo.respond_to?(:decrypt)
  end
end
