# frozen_string_literal: true

require 'base64'
require 'uri'

module K9o
  # `k9o.kibo.vault.secrets.*` - the typed secrets surface
  # (`services/gateway/src/routes/vault-secrets.ts`). Full family: list / get /
  # create / reveal_challenge / reveal / update / rotate / move / delete.
  #
  #   - `region` is OPTIONAL on every named-secret operation: the gateway
  #     ignores any caller-supplied region and uses its own. It is sent on the
  #     query string only when the caller passes one (never by `get`, which
  #     reads the list route).
  #   - The wire `value` field is base64 in BOTH directions. `create`/`update`
  #     take plaintext as a normal Ruby String and base64-encode it here;
  #     `reveal` base64-decodes the wire `value` back to plaintext before
  #     returning it - callers never see base64 on either side.
  #   - `update`/`rotate`/`move` responses are narrower than a full summary -
  #     see the comment on each method below.
  #
  # `data` is returned as the raw wire Hash (camelCase string keys), matching
  # this package's existing convention; `reveal` is the one exception, where
  # the `value` key is base64-decoded in place.
  class VaultSecrets
    MAX_GET_PAGES = 20

    def initialize(config)
      @config = config
    end

    # List secrets (metadata only — never lists ciphertext).
    # `GET /@<project_slug>/vault/secrets`.
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

    # Read a secret's metadata (never its value - use `reveal_challenge` +
    # `reveal` for that).
    #
    # `GET /@<project>/vault/secrets/<name>` is a reveal and always demands an
    # `X-K9O-Reveal-Challenge` header, so metadata is read from the list route:
    # list with the exact name as `prefix` (limit 100, following `nextCursor`
    # for up to MAX_GET_PAGES pages) and return the secret whose `name` equals
    # the argument. Raises `KError` `K9O_NOT_FOUND` (status 404) when none
    # matches. `region` is accepted for symmetry and not sent.
    def get(name, region: nil) # rubocop:disable Lint/UnusedMethodArgument
      cursor = nil
      MAX_GET_PAGES.times do
        env = list(prefix: name, cursor: cursor, limit: 100)
        data = env.data || {}
        secret = (data['secrets'] || []).find { |s| s['name'] == name }
        return Envelope.new(data: secret, meta: env.meta) if secret

        cursor = data['nextCursor']
        break if cursor.nil? || cursor.to_s.empty?
      end
      raise KError.new(
        code: 'K9O_NOT_FOUND',
        message: "No secret named '#{name}' in this project.",
        context: { 'name' => name },
        status: 404
      )
    end

    # Create a secret under the caller's own auth.
    # `POST /@<project_slug>/vault/secrets/<name>` (+ `region` when given) -> the
    # full `sec_<base62>` summary.
    #
    # `visibility` (`{'kind' => 'private'}` or
    # `{'kind' => 'shared', 'principals' => [...], 'roles' => [...]}`) and
    # `metadata` (`Hash[String, String]`) are passed through verbatim.
    def create(name:, value:, region: nil, visibility: nil, metadata: nil)
      slug = require_project_slug
      body = { 'value' => Base64.strict_encode64(value) }
      body['visibility'] = visibility if visibility
      body['metadata'] = metadata if metadata
      HttpTransport.request(
        config: @config, method: 'POST',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: region_query(region),
        body: body
      )
    end

    # Mint a single-use reveal challenge — present it as
    # `X-K9O-Reveal-Challenge` on the immediately-following `reveal` call.
    # `POST .../<name>?op=reveal-challenge`.
    def reveal_challenge(name, region: nil)
      slug = require_project_slug
      HttpTransport.request(
        config: @config, method: 'POST',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: region_query(region, 'op' => 'reveal-challenge')
      )
    end

    # Reveal a secret's plaintext value using a single-use challenge from
    # `reveal_challenge`. `GET .../<name>` with
    # `X-K9O-Reveal-Challenge`. Base64-decodes the wire's `value` back to
    # plaintext (the reveal response's `value` is base64, symmetric with
    # `create`'s encode) before returning it to the caller.
    def reveal(name, challenge:, region: nil)
      slug = require_project_slug
      envelope = HttpTransport.request(
        config: @config, method: 'GET',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: region_query(region),
        headers: { 'X-K9O-Reveal-Challenge' => challenge }
      )
      data = envelope.data
      if data.is_a?(Hash) && data.key?('value')
        data = data.merge('value' => Base64.decode64(data['value']))
      end
      Envelope.new(data: data, meta: envelope.meta)
    end

    # Update a secret's value (bumps version) — owner-only.
    # `PUT .../<name>`.
    #
    # Narrower than a full summary: the gateway returns only
    # `{id, name, version}` on a real PUT, not the full summary the OpenAPI
    # schema claims — call `get` afterward if the full summary is needed.
    def update(name, value:, region: nil, metadata: nil)
      slug = require_project_slug
      body = { 'value' => Base64.strict_encode64(value) }
      body['metadata'] = metadata if metadata
      HttpTransport.request(
        config: @config, method: 'PUT',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: region_query(region),
        body: body
      )
    end

    # Rotate a secret's wrapping key (re-wraps under a fresh `kid`; content
    # unchanged) — owner-only. `POST .../<name>?op=rotate`.
    #
    # Response shape: `{id, name, version, rotatedAt,
    # ledgerSequenceNumber}` — the route's OpenAPI schema doesn't document
    # this response at all.
    def rotate(name, region: nil)
      slug = require_project_slug
      HttpTransport.request(
        config: @config, method: 'POST',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: region_query(region, 'op' => 'rotate')
      )
    end

    # Move (rename) a secret's hierarchical path — owner-only.
    # `POST .../<name>?op=move` with `{newPath}`.
    #
    # Response shape: `{id, name, event}` (observed
    # `event: "SECRET_PATH_CHANGED"`; treat as a plain String, not a closed
    # enum — only one sample was observed).
    def move(name, new_path:, region: nil)
      slug = require_project_slug
      HttpTransport.request(
        config: @config, method: 'POST',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: region_query(region, 'op' => 'move'),
        body: { 'newPath' => new_path }
      )
    end

    # Retire a secret - owner-only. `DELETE .../<name>`; any 2xx is success
    # (204 No Content maps to `data: nil`).
    def delete(name, region: nil)
      slug = require_project_slug
      HttpTransport.request(
        config: @config, method: 'DELETE',
        path: UrlGrammar.project_path(slug, "vault/secrets/#{enc(name)}"),
        query: region_query(region)
      )
    end

    private

    def region_query(region, extra = {})
      q = extra.dup
      q['region'] = region if region
      q
    end

    def require_project_slug
      Studio.require_project_slug(@config, 'kibo.vault.secrets')
    end

    def enc(s)
      ::URI.encode_www_form_component(s)
    end
  end

  # `k9o.kibo.vault.*` — the Kibo vault surface (member-plane, project-scoped).
  # Currently just `secrets` ; a `zk_deks` accessor
  # (`POST vault/zk-deks` / `GET vault/zk-deks/<id>`) would
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
  # FFI bindings, called directly as
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
