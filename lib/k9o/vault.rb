# frozen_string_literal: true

require 'base64'
require 'uri'

module K9o
  # `k9o.kibo.vault.secrets.*` — the typed secrets surface
  # (`services/gateway/src/routes/vault-secrets.ts`). Full family: list / get /
  # create / reveal_challenge / reveal / update / rotate / move / delete.
  #
  # Contract live-verified against the real staging gateway (not just the
  # route's OpenAPI schema, which is wrong/incomplete in several places noted
  # below) by the `@k9o/kibo` TS reference build — this wrapper mirrors that
  # verified behavior exactly:
  #
  #   - Every operation on a NAMED secret (everything except `list`) REQUIRES
  #     `region` on the query string. Omitting it fails with
  #     K9O_INVALID_FIELD_VALUE ("this request requires an authoritative
  #     region"). NOT documented in the route's OpenAPI schema. `list` is the
  #     one exception (verified it does NOT need `region`).
  #   - The wire `value` field is base64 in BOTH directions, contradicting the
  #     OpenAPI's plain-language "the plaintext to seal" description (reads
  #     like it should be raw). A raw non-base64 `value` on create/update is
  #     rejected as unparseable. `create`/`update` take plaintext as a normal
  #     Ruby String and base64-encode it here; `reveal` base64-decodes the
  #     wire `value` back to plaintext before returning it — callers never
  #     see base64 on either side.
  #   - `update`/`rotate`/`move` responses are LIVE-VERIFIED NARROWER than (or
  #     entirely undocumented vs.) the OpenAPI's claimed `SecretSummary` — see
  #     the comment on each method below.
  #
  # `data` is returned as the raw wire Hash (camelCase string keys), matching
  # this package's existing convention (Projects/Policies/Studio/etc. all
  # return `envelope.data` untransformed — there is no generic
  # camelCase<->snake_case response transform anywhere in this gem); `reveal`
  # is the one exception, where the `value` key is base64-decoded in place
  # (mirroring the TS reference's own `value`-only transform).
  class VaultSecrets
    def initialize(config)
      @config = config
    end

    # List secrets (metadata only — never lists ciphertext).
    # `GET /@<project_slug>/vault/secrets`.
    # The one secrets operation that does NOT need `region` (live-verified).
    def list(prefix: nil, cursor: nil, limit: nil)
      slug = require_project_slug
      q = {}
      q['prefix'] = prefix if prefix
      q['cursor'] = cursor if cursor
      q['limit'] = limit if limit
      HttpTransport.request(
        config: @config, method: 'GET',
        path: UrlGrammar.project_path(slug, 'vault/secrets'),
        query: q
      )
    end

    # Read a secret's metadata (never its value — use `reveal_challenge` +
    # `reveal` for that).
    # `GET /@<project_slug>/vault/secrets/<name>?region=<region>`.
    #
    # KNOWN LIVE BUG (staging, 2026-09-05): this call currently fails with
    # K9O_REVEAL_CHALLENGE_REQUIRED on every attempt — the gateway does not
    # honor its own documented "no X-K9O-Reveal-Challenge header => return
    # metadata" behavior; it demands a challenge unconditionally. Implemented
    # per the documented contract anyway (this is a backend defect to flag,
    # not something to design around) — `list(prefix: exact_name)` is the
    # current working alternative for a single secret's metadata until the
    # gateway side is fixed.
    def get(name, region:)
      slug = require_project_slug
      HttpTransport.request(
        config: @config, method: 'GET',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: { 'region' => region }
      )
    end

    # Create a secret under the caller's own auth.
    # `POST /@<project_slug>/vault/secrets/<name>?region=<region>` → the full
    # `sec_<base62>` summary.
    #
    # `region` scopes the vault WRITE itself (residency guard) and is
    # REQUIRED — live-verified against staging, not documented in the route's
    # OpenAPI schema.
    #
    # `visibility` (`{'kind' => 'private'}` or
    # `{'kind' => 'shared', 'principals' => [...], 'roles' => [...]}`) and
    # `metadata` (`Hash[String, String]`) are passed through verbatim — their
    # own field names are already single words, so no wire-casing applies.
    def create(name:, value:, region:, visibility: nil, metadata: nil)
      slug = require_project_slug
      body = { 'value' => Base64.strict_encode64(value) }
      body['visibility'] = visibility if visibility
      body['metadata'] = metadata if metadata
      HttpTransport.request(
        config: @config, method: 'POST',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: { 'region' => region },
        body: body
      )
    end

    # Mint a single-use reveal challenge — present it as
    # `X-K9O-Reveal-Challenge` on the immediately-following `reveal` call.
    # `POST .../<name>?op=reveal-challenge&region=<region>`.
    def reveal_challenge(name, region:)
      slug = require_project_slug
      HttpTransport.request(
        config: @config, method: 'POST',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: { 'op' => 'reveal-challenge', 'region' => region }
      )
    end

    # Reveal a secret's plaintext value using a single-use challenge from
    # `reveal_challenge`. `GET .../<name>?region=<region>` with
    # `X-K9O-Reveal-Challenge`. Base64-decodes the wire's `value` back to
    # plaintext (live-verified: the reveal response's `value` is base64,
    # symmetric with `create`'s encode) before returning it to the caller.
    def reveal(name, region:, challenge:)
      slug = require_project_slug
      envelope = HttpTransport.request(
        config: @config, method: 'GET',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: { 'region' => region },
        headers: { 'X-K9O-Reveal-Challenge' => challenge }
      )
      data = envelope.data
      if data.is_a?(Hash) && data.key?('value')
        data = data.merge('value' => Base64.decode64(data['value']))
      end
      Envelope.new(data: data, meta: envelope.meta)
    end

    # Update a secret's value (bumps version) — owner-only.
    # `PUT .../<name>?region=<region>`.
    #
    # LIVE-VERIFIED NARROWER than documented: the gateway returns only
    # `{id, name, version}` on a real PUT, not the full summary the OpenAPI
    # schema claims — call `get` afterward if the full summary is needed.
    def update(name, region:, value:, metadata: nil)
      slug = require_project_slug
      body = { 'value' => Base64.strict_encode64(value) }
      body['metadata'] = metadata if metadata
      HttpTransport.request(
        config: @config, method: 'PUT',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: { 'region' => region },
        body: body
      )
    end

    # Rotate a secret's wrapping key (re-wraps under a fresh `kid`; content
    # unchanged) — owner-only. `POST .../<name>?op=rotate&region=<region>`.
    #
    # LIVE-VERIFIED undocumented shape: `{id, name, version, rotatedAt,
    # ledgerSequenceNumber}` — the route's OpenAPI schema doesn't document
    # this response at all.
    def rotate(name, region:)
      slug = require_project_slug
      HttpTransport.request(
        config: @config, method: 'POST',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: { 'op' => 'rotate', 'region' => region }
      )
    end

    # Move (rename) a secret's hierarchical path — owner-only.
    # `POST .../<name>?op=move&region=<region>` with `{newPath}`.
    #
    # LIVE-VERIFIED undocumented shape: `{id, name, event}` (observed
    # `event: "SECRET_PATH_CHANGED"`; treat as a plain String, not a closed
    # enum — only one sample was observed).
    def move(name, region:, new_path:)
      slug = require_project_slug
      HttpTransport.request(
        config: @config, method: 'POST',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: { 'op' => 'move', 'region' => region },
        body: { 'newPath' => new_path }
      )
    end

    # Retire a secret — owner-only. `DELETE .../<name>?region=<region>` →
    # `204 No Content` (HttpTransport already maps that to `data: nil`).
    def delete(name, region:)
      slug = require_project_slug
      HttpTransport.request(
        config: @config, method: 'DELETE',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: { 'region' => region }
      )
    end

    private

    def require_project_slug
      Studio.require_project_slug(@config, 'kibo.vault.secrets')
    end

    def enc(s)
      ::URI.encode_www_form_component(s)
    end
  end

  # `k9o.kibo.vault.*` — the Kibo vault surface (member-plane, project-scoped).
  # Currently just `secrets`; a `zk_deks` accessor
  # (F.5, `POST vault/zk-deks` / `GET vault/zk-deks/<id>`) would
  # nest here alongside it if/when that surface is built for Ruby — out of
  # scope for this wrapper, which only covers the vault-secrets audit gap.
  class KiboVault
    attr_reader :secrets

    def initialize(config)
      @secrets = VaultSecrets.new(config)
    end
  end

  # `k9o.kibo.*` — per-client namespace root for the Kibo vault REST surface.
  # Distinct from the module-level `K9o::Kibo` (native ZK `encrypt`/`decrypt`
  # FFI bindings, /, called directly as
  # `K9o::Kibo.encrypt`/`.decrypt` since that surface needs no per-client HTTP
  # config): this class exists so `client.kibo.vault.secrets.*` is reachable
  # per client instance, mirroring the TS reference's
  # `client.kibo.vault.{zk_deks, secrets}` shape.
  class KiboNamespace
    attr_reader :vault

    def initialize(config)
      @vault = KiboVault.new(config)
    end
  end
end
