# frozen_string_literal: true

require_relative 'kerror'

module K9o
  # Zero-Knowledge BYOK/HYOK vault crypto — +K9o::Kibo.encrypt+ / +.decrypt+.
  #
  # Thin wrapper over the bound core (+kibo-kms-rest-ffi+, piece C) via uniffi.
  # ZERO crypto here: every wrap/unwrap, envelope framing, posture-floor
  # enforcement, and KMS round-trip lives in the audited Rust core.
  #
  # Ruby has no async runtime, so this calls the SYNC +zk_encrypt_blocking+ /
  # +zk_decrypt_blocking+ exports — which drive the SAME canonical async op to
  # completion on a process-wide tokio runtime inside the core (crypto-identical
  # to the async exports the async-native languages use; W7C-confirmed neutral).
  #
  # The generated uniffi binding + native lib (+lib/k9o/_ffi/+) are build
  # artifacts (CI-injected per platform; gitignored). On a platform/Ruby without
  # the lib, +require+ still succeeds and +encrypt+/+decrypt+ raise a clear
  # +K9o::KError+ — so loading +k9o+ never breaks for the rest of the SDK.
  module Kibo
    # Attempt to load the native binding; never raises at require time.
    NATIVE_AVAILABLE =
      begin
        require_relative '_ffi/kibo_kms_rest_ffi'
        true
      rescue LoadError
        false
      end

    # Re-export the binding's input/output + enum types for ergonomic use
    # (+K9o::Kibo::EncryptInput+, +K9o::Kibo::FfiPosture::BYOK+, …).
    if NATIVE_AVAILABLE
      EncryptInput          = KiboKmsRestFfi::EncryptInput
      DecryptInput          = KiboKmsRestFfi::DecryptInput
      EncryptOutput         = KiboKmsRestFfi::EncryptOutput
      DecryptOutput         = KiboKmsRestFfi::DecryptOutput
      FfiCredential         = KiboKmsRestFfi::FfiCredential
      FfiKeyRef             = KiboKmsRestFfi::FfiKeyRef
      FfiProviderConfig     = KiboKmsRestFfi::FfiProviderConfig
      FfiKvPair             = KiboKmsRestFfi::FfiKvPair
      FfiPosturePolicy      = KiboKmsRestFfi::FfiPosturePolicy
      FfiAllowedOracleModes = KiboKmsRestFfi::FfiAllowedOracleModes
      FfiPosture            = KiboKmsRestFfi::FfiPosture
      FfiStrategy           = KiboKmsRestFfi::FfiStrategy
      FfiOracleMode         = KiboKmsRestFfi::FfiOracleMode
      FfiAttestationTier    = KiboKmsRestFfi::FfiAttestationTier
      FfiMinPosture         = KiboKmsRestFfi::FfiMinPosture
      KmsProvider           = KiboKmsRestFfi::KmsProvider

      # uniffi-ruby's error variants are +< StandardError+ namespaced under the
      # +ZkFfiUniffiError+ module but do NOT +include+ it, so +rescue+-ing the
      # module misses them — rescue the concrete variant classes instead.
      FFI_ERRORS = [
        KiboKmsRestFfi::ZkFfiUniffiError::Platform,
        KiboKmsRestFfi::ZkFfiUniffiError::UpstreamKms,
        KiboKmsRestFfi::ZkFfiUniffiError::PostureViolation
      ].freeze
    end

    # Encrypt +input.plaintext+ via the customer KMS, client-side. Returns the
    # opaque ZKFE envelope (+EncryptOutput+). Raises +K9o::KError+ on failure.
    def self.encrypt(input)
      ensure_native!
      begin
        KiboKmsRestFfi.zk_encrypt_blocking(input)
      rescue *FFI_ERRORS => e
        raise to_kerror(e)
      end
    end

    # Decrypt a ZKFE +input.envelope+. +strategy+, +attestation_tier+, and
    # +encryption_context+ MUST match the encrypt-time values (AAD-bound).
    def self.decrypt(input)
      ensure_native!
      begin
        KiboKmsRestFfi.zk_decrypt_blocking(input)
      rescue *FFI_ERRORS => e
        raise to_kerror(e)
      end
    end

    # Guard: raise a clear KError if the native lib is absent (evaluated BEFORE
    # any reference to the +KiboKmsRestFfi+ namespace, which may be undefined).
    def self.ensure_native!
      return if NATIVE_AVAILABLE

      raise K9o::KError.new(
        code: 'KIBO_NATIVE_UNAVAILABLE',
        message: 'kibo ZK native library not available for this platform/Ruby; install the platform-specific k9o gem.'
      )
    end
    private_class_method :ensure_native!

    # Map the bound core's uniffi error -> +K9o::KError+, codes passed through.
    def self.to_kerror(e)
      case e
      when KiboKmsRestFfi::ZkFfiUniffiError::PostureViolation
        K9o::KError.new(
          code: e.code, message: e.detail,
          context: { dimension: e.dimension, requested: e.requested, declared: e.declared }
        )
      when KiboKmsRestFfi::ZkFfiUniffiError::Platform
        K9o::KError.new(code: e.code, message: e.detail)
      when KiboKmsRestFfi::ZkFfiUniffiError::UpstreamKms
        # Customer's own KMS failed — no K9O_* code (outside the platform error namespace).
        K9o::KError.new(code: 'UPSTREAM_KMS_ERROR', message: e.detail)
      else
        K9o::KError.new(code: 'KIBO_FFI_ERROR', message: e.message)
      end
    end
    private_class_method :to_kerror
  end
end
