# frozen_string_literal: true

require_relative 'kerror'

module K9o
  # Barbican — free, embeddable L2 guardrail. Input normalization -> Aho-Corasick
  # deny-list matching over a signed ruleset -> local verdict, plus a streaming
  # output redactor (buffer-and-scan-before-flush).
  #
  # Thin wrapper over the bound core (`k9o-keep-core`, via uniffi) — mirrors the
  # structural pattern of +K9o::Kibo+ (native-load guard evaluated once at
  # require time; every call forwards typed arguments to the generated binding
  # and maps its error -> +K9o::KError+). ZERO guardrail logic lives here: every
  # normalization pass, deny match, verdict, and redaction decision is the
  # audited native core's.
  #
  # CLAIM BOUNDARY: Barbican is advisory / defense-in-depth (edge filtration).
  # It is never the enforced sandbox boundary.
  #
  # The generated uniffi binding + native lib (+lib/k9o/_ffi/+) are build
  # artifacts (CI-injected per platform; gitignored) — on a platform/Ruby
  # without them, +require+ still succeeds and +Barbican.new+ raises a clear
  # +K9o::KError+, so loading +k9o+ never breaks for the rest of the SDK.
  class Barbican
    # Attempt to load the native binding; never raises at require time.
    NATIVE_AVAILABLE =
      begin
        require_relative '_ffi/k9o_keep_core_ffi_uniffi'
        true
      rescue LoadError
        false
      end

    # +decode_depth+ of 0 uses the core default (3) — a bounded base64/leetspeak
    # de-obfuscation depth (decode-bomb guard).
    def initialize(fail_open: false, leet: true, decode_depth: 0)
      self.class.ensure_native!
      config = K9oKeepCoreFfiUniffi::KeepConfig.new(
        fail_open: fail_open, leet: leet, decode_depth: decode_depth
      )
      @core = K9oKeepCoreFfiUniffi::KeepCore.new(config)
    end

    # Load a static ruleset bundled with your gem (Mode-A path: provenance is
    # vouched for by your package, so signature verification is skipped — the
    # core still enforces anti-rollback, never loading a version <= the current
    # one). +rules+ = an array of {id:, pattern:, severity:} (severity one of
    # low|medium|high|critical; string or symbol keys both accepted). Returns
    # the accepted version.
    def load_ruleset(ruleset_version, rules)
      blob = K9oKeepCoreFfiUniffi::KeepRulesetBlob.new(
        ruleset_version: ruleset_version,
        rules: rules.map { |r| build_rule(r) }
      )
      begin
        @core.load_ruleset_unsigned(blob)
      rescue StandardError => e
        raise self.class.to_kerror(e)
      end
    end

    # Load a Barbican key manifest (compact JWS, +typ k9o.barbican.keys.v1+). The
    # core checks it against the root key compiled into it and, only if it
    # verifies, REPLACES the trusted ruleset-signing keys with the ones it lists.
    # A refusal (wrong signer, rollback, a key changing its public key, a
    # malformed entry) raises +K9O_BARBICAN_RULESET_INVALID+ with
    # +context[:stage] == 'key_manifest'+ and leaves the trusted keys unchanged.
    # Returns the manifest +sequence+.
    def load_key_manifest(jws, now_secs = nil)
      @core.load_key_manifest(jws, now_secs || Time.now.to_i)
    rescue StandardError => e
      raise self.class.to_kerror(e, 'key_manifest')
    end

    # Verify a ruleset manifest (compact JWS) under a trusted key and return its
    # authenticated fields (+ruleset_version+ / +signing_key_kid+ /
    # +artifact_hash+ / +artifact_url+ / +valid_until+).
    def verify_manifest(jws)
      @core.verify_manifest(jws)
    rescue StandardError => e
      raise self.class.to_kerror(e)
    end

    # Load a signed ruleset. The core verifies the Ed25519 signature ITSELF, over
    # its own canonical bytes, under a key from the loaded key manifest: there is
    # no key or verifier to pass. Any failure (no key manifest loaded, unknown
    # key, bad or non-canonical signature, stale version, malformed rules) raises
    # +K9O_BARBICAN_RULESET_INVALID+ with +context[:reason]+ and leaves the
    # current ruleset running. +signature+ is the raw 64-byte binary String.
    # Returns the accepted version.
    def load_ruleset_signed(ruleset_version, rules, signing_key_kid, signature, created_at = 0)
      @core.load_ruleset_signed(signed_blob(ruleset_version, rules, signing_key_kid, signature, created_at))
    rescue StandardError => e
      raise self.class.to_kerror(e)
    end

    # Lowercase hex SHA-256 of a ruleset's canonical signing bytes — the value a
    # manifest's +artifact_hash+ names. A digest only; it decides no trust.
    def ruleset_digest(ruleset_version, rules, signing_key_kid, signature, created_at = 0)
      @core.ruleset_digest(signed_blob(ruleset_version, rules, signing_key_kid, signature, created_at))
    rescue StandardError => e
      raise self.class.to_kerror(e)
    end

    # The +sequence+ of the key manifest in force (0 before one is loaded).
    def key_manifest_sequence
      @core.key_manifest_sequence
    end

    # The highest VERIFIED ruleset version loaded (0 = none): the anti-rollback floor for signed updates. A refresh
    # compares a published version against this, not the version in force.
    def signed_floor
      @core.signed_floor
    end

    # Whether the ruleset in force came from a verified load. +false+ when none is loaded, or when +load_ruleset+
    # (unsigned, host-vouched) replaced a verified one.
    def active_ruleset_is_signed?
      @core.active_ruleset_is_signed
    end

    # The signing kids the loaded key manifest currently trusts, sorted.
    def trusted_kids
      @core.trusted_kids
    end

    # The trusted kids the key manifest flags deprecated, sorted.
    def deprecated_kids
      @core.deprecated_kids
    end

    # +false+ on every shipped build. +true+ means this binding trusts the
    # PUBLISHED TEST root and must never be used outside tests.
    def self.uses_test_trust_root?
      ensure_native!
      K9oKeepCoreFfiUniffi.uses_test_trust_root
    end

    # Inspect an input (normalize -> deny -> local verdict). Obfuscation is
    # peeled BEFORE matching, so static deny-lists aren't defeated by trivial
    # tricks. +waypoint_class+ is the manifest's meter hint — it NEVER gates the
    # decision. Returns the verdict object (+decision+ / +reason+ / +matched+ /
    # +schema_valid+ / +waypoint_class_hint+ / +fail_mode+ / +ruleset_version+ /
    # +core_version+).
    def inspect(text, waypoint_class: nil)
      @core.inspect_input(text, waypoint_class)
    end

    # Local L3 stand-in classification ("clear"|"suspicious"|"malicious"). No
    # receipt — a classification is not an enforcement decision.
    def classify(text)
      @core.classify_local(text)
    end

    # Open an output stream-filter bound to the active ruleset's exfil markers.
    def create_output_filter
      OutputFilter.new(@core.output_filter)
    end

    # The bound core's semver (audit anchor; rides every verdict too).
    def core_version
      @core.core_version
    end

    # Guard: raise a clear KError if the native lib is absent (evaluated BEFORE
    # any reference to the +K9oKeepCoreFfiUniffi+ namespace, which may be
    # undefined).
    def self.ensure_native!
      return if NATIVE_AVAILABLE

      raise K9o::KError.new(
        code: 'K9O_BARBICAN_WASM_ERROR',
        message: 'barbican native library not available for this platform/Ruby; install the platform-specific k9o gem.'
      )
    end

    # Map the bound core's error -> +K9o::KError+. +KeepError::RulesetInvalid+
    # is the only typed variant (bad/stale/malformed ruleset) — its reason token
    # (+version_stale+ / +signature_invalid+ / +malformed+ / an unknown-severity
    # message) rides in +context[:reason]+. Anything else from the native layer
    # (e.g. a Rust panic surfaced as +InternalError+) maps to the generic code.
    def self.to_kerror(e, stage = 'ruleset')
      if e.respond_to?(:reason)
        K9o::KError.new(
          code: 'K9O_BARBICAN_RULESET_INVALID',
          message: e.to_s,
          context: { reason: e.reason, stage: stage }
        )
      else
        K9o::KError.new(code: 'K9O_BARBICAN_WASM_ERROR', message: e.to_s)
      end
    end

    # Accept string or symbol keys ({"id" => ..} or {id: ..}) for ergonomics.
    def build_rule(r)
      K9oKeepCoreFfiUniffi::KeepRule.new(
        id: r[:id] || r['id'],
        pattern: r[:pattern] || r['pattern'],
        severity: r[:severity] || r['severity']
      )
    end
    private :build_rule

    def signed_blob(ruleset_version, rules, signing_key_kid, signature, created_at)
      K9oKeepCoreFfiUniffi::KeepSignedRulesetBlob.new(
        ruleset_version: ruleset_version,
        rules: rules.map { |r| build_rule(r) },
        signing_key_kid: signing_key_kid,
        signature: signature.b,
        created_at: created_at
      )
    end
    private :signed_blob
  end

  # A streaming output redactor. Buffer-and-scan-before-flush: never emits a
  # byte the core has not cleared (no RST-after-leak).
  class OutputFilter
    def initialize(handle)
      @handle = handle
    end

    # Feed a chunk; returns the cleared (redacted) prefix safe to emit now.
    def push(chunk)
      @handle.push(chunk)
    end

    # Flush the residual buffer (also scanned) at end of stream.
    def finish
      @handle.finish
    end

    # Leak report (counts only — never the leaked values): an object with
    # +emails+ / +secrets+ / +markers+ / +total+.
    def report
      @handle.report
    end
  end
end
