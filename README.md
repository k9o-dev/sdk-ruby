# k9o

The Kilimanjaro platform SDK for Ruby.

Kilimanjaro is the AI-native foundation for building critical applications.
Its products are:

- Keep: AI Security and Governance
- Pulse: Data Intelligence
- Gate: Customer Identity and Access Management
- Kibo: Keys and Secrets Management

## Contents

- [Links](#links)
- [Install](#install)
- [Quick start](#quick-start)
- [Authentication and project context](#authentication-and-project-context)
- [Running queries](#running-queries)
- [Handling errors](#handling-errors)
- [Appendix](#appendix)
- [License](#license)

## Links

- Website: <https://kilimanjaro.dev>
- Documentation / Developer Hub: <https://docs.kilimanjaro.dev>
- Platform API: <https://api.k9o.io>
- Platform Console: <https://console.k9o.io>

## Install

```bash
gem install k9o
```

Or add it to your `Gemfile`:

```ruby
gem "k9o"
```

Requires Ruby 3.2 or newer. See [requirements](#requirements) for details.

## Quick start

The examples use a `tasks` collection with `title` and `done` fields.

### Create the client

```ruby
require "k9o"

k9o = K9o.create_client(
  org_slug: "acme",
  project_slug: "task-app",
  api_key: ENV.fetch("K9O_API_KEY")
)
```

### Add a task

```ruby
new_task = { "title" => "Write the README", "done" => false }
created = k9o.from("tasks").insert(new_task)
puts "created: #{created.data['title']}"
```

```text
created: Write the README
```

### List tasks

```ruby
response = k9o.from("tasks").select.eq("done", false).limit(10).execute
response.data.each do |task|
  puts "#{task['title']} #{task['done']}"
end
```

```text
Write the README false
```

### Update and delete a task

Both calls need an `eq("id", ...)` filter.

```ruby
task_id = created.data["id"]

patch = { "done" => true }
k9o.from("tasks").update(patch).eq("id", task_id).execute

k9o.from("tasks").delete.eq("id", task_id).execute
```

## Authentication and project context

The client needs a key and, for project calls, an org and project.

| Option | What it does |
|---|---|
| `api_key:` | Bearer token sent with every request. |
| `org_slug:` | Organization. The SDK builds `https://<org_slug>.<host>` from the platform host. |
| `project_slug:` | Project. Required by every project-scoped namespace. |

See [client options](#client-options) for every option.

### Choose a host

The API host always comes from the base URL. Pick one of two forms.

- Default public host: pass the org slug, project slug and key.
- Any other platform, internal or air-gapped host: pass its `base_url` as well.

```ruby
k9o = K9o.create_client(
  base_url: "https://api.corp.internal",
  org_slug: "acme",
  project_slug: "task-app",
  api_key: ENV.fetch("K9O_API_KEY")
)
```

This client talks to `https://acme.api.corp.internal`. See [regional hosts](#regional-hosts) for the rules.

## Running queries

Chain filters on `select`, then call `execute`. The result carries rows in `data` and details in `meta`.

| Call | What it does |
|---|---|
| `eq(column, value)` | Keep rows where the column equals the value. |
| `limit(n)` | Return at most `n` rows. |
| `cursor(token)` | Continue from `meta.cursor.next`. |

See [filters](#filters) and [paging](#paging) for all calls, and [response metadata](#response-metadata) for every `meta` field.

A sub-object the server did not send is `nil`, so use `&.` when it may be absent.

```ruby
request_id = response.meta.context.request_id
total = response.meta.cursor.total_count
puts "#{request_id} #{total}"
```

```text
req_01H... 1
```

## Handling errors

Failures raise `K9o::KError`, a subclass of `StandardError`. Branch on `code`.

```ruby
begin
  k9o.from("missing").select.execute
rescue K9o::KError => error
  puts "#{error.code} #{error.status} #{error.request_id}"
  puts error.message
end
```

```text
K9O_NOT_FOUND 404 req_01H...
Collection not found
```

- See [error attributes](#error-attributes) for every field.
- See [error codes](#error-codes) for the codes the SDK raises.
- See [retries](#retries) for automatic retry rules.

## Appendix

### Requirements

| Requirement | Version |
|---|---|
| `Ruby` | 3.2 or newer |
| `Runtime gems` | None (uses `Net::HTTP`, `json` and `uri` from the standard library) |

### Client options

| Option | What it does |
|---|---|
| `api_key:` | Bearer token sent with every request. |
| `org_slug:` | Organization. Prefixed to a platform host (`api.<apex>`) to form the org host. |
| `project_slug:` | Project. Required by every project-scoped namespace. |
| `base_url:` | Scheme and host only. Defaults to the public host `https://api.k9o.io`. |
| `default_headers:` | Extra headers added to every request. |
| `http_client:` | A `Net::HTTP`-compatible object used instead of the default connection. |

`org_slug` and `project_slug` are also sent as the `x-k9o-org-slug` and `x-k9o-project-slug` headers.

### Methods by namespace

Every method is called on the client, for example `k9o.projects.list`. Return values are `Envelope` objects.

#### Data

`k9o.from(collection)` reads and writes rows in one collection of the active project.

| Method | What it does |
|---|---|
| `select` | Start a query. Finish with `execute`. |
| `insert(record)` | Add one row and return it. |
| `update(patch)` | Change one row. Needs `eq("id", ...)`. |
| `delete` | Remove one row. Needs `eq("id", ...)`. |

##### Filters

Chain filters before `execute`. Values are matched against one column.

| Method | What it does |
|---|---|
| `eq(column, value)` | Equal to value. |
| `neq(column, value)` | Not equal to value. |
| `gt(column, value)` | Greater than value. |
| `gte(column, value)` | Greater than or equal. |
| `lt(column, value)` | Less than value. |
| `lte(column, value)` | Less than or equal. |
| `in_(column, values)` | Equal to any value in the list. |
| `not_in(column, values)` | Equal to none of the values. |
| `like(column, pattern)` | Case-sensitive pattern match. |
| `ilike(column, pattern)` | Case-insensitive pattern match. |
| `is(column, value)` | Match `null`, `true` or `false`. |
| `filter(column, op, value)` | Generic form with an explicit operator name. |

##### Paging

| Method | What it does |
|---|---|
| `limit(n)` | Maximum rows to return. |
| `cursor(token)` | Continue from `meta.cursor.next`. |
| `count(mode)` | Row count mode: `none`, `exact` or `estimated`. |

#### Projects

`k9o.projects` manages projects in the active organization.

| Method | What it does |
|---|---|
| `k9o.projects.list` | List projects you can access. |
| `k9o.projects.create` | Create a project from `display_name:` (optional `slug:`, `region:`, `custody_mode:`, more). |
| `k9o.projects.get` | Read a project by slug. |
| `k9o.projects.update` | Change a project by slug: `display_name:`, `slug:` (rename), `description:`, `region:`, more. |

```ruby
project = k9o.projects.create(display_name: "Task app", slug: "task-app")
puts project.data["slug"]
```

```text
task-app
```

#### Gate (end-user sign-in)

`k9o.gate` signs in the active project's end users and needs `project_slug`.

| Method | What it does |
|---|---|
| `k9o.gate.sign_up` | Create an end user from email and password. |
| `k9o.gate.sign_in` | Sign in with email and password. |
| `k9o.gate.sign_out` | Revoke a session. Requires `refresh_token:`. |
| `k9o.gate.whoami` | Return the signed-in identity. |
| `k9o.gate.refresh_token` | Exchange a refresh token for a new access token. |

```ruby
session = k9o.gate.sign_in(email: "ada@example.com", password: "correct-horse")
user = session.data["user"]
puts user["email"]
```

```text
ada@example.com
```

#### Storage

`k9o.storage` manages buckets and the objects inside them.

##### Buckets

| Method | What it does |
|---|---|
| `k9o.storage.create_bucket` | Create a bucket by name. |
| `k9o.storage.get_bucket` | Read one bucket. |
| `k9o.storage.list_buckets` | List buckets. |
| `k9o.storage.update_bucket` | Change bucket settings. |
| `k9o.storage.delete_bucket` | Delete a bucket. Pass `empty` to purge its objects first. |

##### Objects

`k9o.storage.from(bucket)` returns a handle for one bucket.

| Method | What it does |
|---|---|
| `k9o.storage.from(bucket).upload` | Store bytes at a path. Existing paths are kept unless `upsert` is true. |
| `k9o.storage.from(bucket).create_signed_url` | Create a time-limited download link. |
| `k9o.storage.from(bucket).list` | List objects, optionally under a `prefix`. |
| `k9o.storage.from(bucket).remove` | Delete the object at a path. |

`expires_in` is required, in seconds from 1 to 604800.

```ruby
avatars = k9o.storage.from("avatars")
avatars.upload("ada.png", "...image bytes...", content_type: "image/png")
signed = avatars.create_signed_url("ada.png", expires_in: 300)
```

#### Functions

`k9o.functions` deploys and runs server-side functions.

| Method | What it does |
|---|---|
| `k9o.functions.upload_artifact` | Upload the build (`bytes`, `kind` of `"wasm"` or `"tar"`). Returns `artifactKey`. |
| `k9o.functions.deploy` | Deploy from `name:`, `runtime:`, `tier:`, `artifact_key:`, `version:`, optional `description:`. |
| `k9o.functions.list` | List functions. Options: `status:`, `limit:`, `cursor:`. |
| `k9o.functions.get` | Read one function by name. |
| `k9o.functions.delete` | Remove a function. |
| `k9o.functions.invoke` | Run a function. The `payload` argument is sent as `{payload}`. |

`tier:` is `"gateway"` (WebAssembly, `"wasm"`) or `"sandbox"` (OCI image archive, `"tar"`).

```ruby
artifact = k9o.functions.upload_artifact(File.binread("hello.wasm"), "wasm")

k9o.functions.deploy(
  name: "hello",
  runtime: "bun",
  tier: "gateway",
  artifact_key: artifact.data["artifactKey"],
  version: "1.0.0"
)
result = k9o.functions.invoke("hello", { "name" => "Ada" })
puts result.data["greeting"]
```

```text
Hello, Ada
```

#### Migrations

`k9o.migrations` changes the project's schema.

| Method | What it does |
|---|---|
| `k9o.migrations.apply` | Apply migrations now. |
| `k9o.migrations.list` | List applied migrations. |
| `k9o.migrations.get` | Read one migration by version. |
| `k9o.migrations.queue` | Queue migrations for approval. |
| `k9o.migrations.list_pending` | List queued migrations. |
| `k9o.migrations.apply_pending` | Apply one queued migration. |
| `k9o.migrations.reject_pending` | Reject one queued migration. |
| `k9o.migrations.delete_pending` | Delete one queued migration. |

#### Policies

`k9o.policies` manages access policy bundles.

| Method | What it does |
|---|---|
| `k9o.policies.current` | Read the published bundle. |
| `k9o.policies.list` | List bundles. Only option: `status:`. |
| `k9o.policies.create` | Create a bundle from a `policy:` document (optional `rules:`, `editor_mode:`). |
| `k9o.policies.validate` | Check a `policy:` document (and optional `rules:`) without saving. |
| `k9o.policies.get` | Read one bundle. |
| `k9o.policies.update` | Replace a bundle's `policy:` (optional `rules:`, `editor_mode:`). |
| `k9o.policies.delete` | Remove a bundle. |
| `k9o.policies.publish` | Make a bundle current. |

#### Audit

`k9o.audit` reads the project's audit events.

| Method | What it does |
|---|---|
| `k9o.audit.query` | Filter by `event_type:`, `actor_id:`, `after:`, `before:`, `limit:`, `cursor:`. |

`after:` and `before:` are ISO 8601 timestamps.

#### AI embeddings

`k9o.ai` creates text embeddings.

| Method | What it does |
|---|---|
| `k9o.ai.embed(input:, model: nil)` | Embed one string or a list of strings. |

#### Language models

`k9o.compute.llms` lists and calls hosted models.

| Method | What it does |
|---|---|
| `k9o.compute.llms.list` | List available models. |
| `k9o.compute.llms.read` | Read one model. |
| `k9o.compute.llms.invoke` | Send a prompt and get the reply. |
| `k9o.compute.llms.invoke_stream` | Stream the reply chunk by chunk (returns an `Enumerator`). |

Pass settings in `params:` (`max_tokens`, `temperature`, `usage_type`). The result `data` has `content` and `usage`.

```ruby
reply = k9o.compute.llms.invoke("llama-3-8b", prompt: "Say hi", params: { max_tokens: 20 })
puts "#{reply.data['content']} #{reply.data['usage']['totalTokens']}"
```

```text
Hi there! 14
```

#### Realtime

`k9o.realtime` delivers live events for a topic.

| Method | What it does |
|---|---|
| `k9o.realtime.subscribe` | Stream live events over SSE (returns an `Enumerator`). |

`K9o::Realtime::Topic` builds topic names, for example `Topic.collection("tasks")`.

#### Studio

`k9o.studio` manages workflows and dashboards.

##### Workflows

| Method | What it does |
|---|---|
| `k9o.studio.workflows.list` | List workflows. |
| `k9o.studio.workflows.create` | Create a workflow. |
| `k9o.studio.workflows.read` | Read one workflow. |
| `k9o.studio.workflows.update` | Change a workflow. |
| `k9o.studio.workflows.delete` | Delete a workflow. |
| `k9o.studio.workflows.trigger` | Start a run, with an optional context hash. |
| `k9o.studio.workflows.runs.list` | List a workflow's runs. |
| `k9o.studio.workflows.runs.read` | Read one run. |
| `k9o.studio.workflows.runs.cancel` | Cancel a run. |

##### Dashboards

| Method | What it does |
|---|---|
| `k9o.studio.dashboards.list` | List dashboards. |
| `k9o.studio.dashboards.create` | Create a dashboard. |
| `k9o.studio.dashboards.read` | Read one dashboard. |
| `k9o.studio.dashboards.update` | Change a dashboard. |
| `k9o.studio.dashboards.delete` | Delete a dashboard. |
| `k9o.studio.dashboards.pin` | Pin to the workspace. |
| `k9o.studio.dashboards.unpin` | Remove from the workspace. |

#### Current user

`k9o.me` covers the signed-in account.

| Method | What it does |
|---|---|
| `k9o.me.profile.get` | Read the profile. |
| `k9o.me.profile.update` | Change `display_name:`, `locale:` or `timezone:` (only those given). |
| `k9o.me.sessions.list` | List active sessions. |
| `k9o.me.sessions.revoke` | End one session. |
| `k9o.me.sessions.revoke_all` | End all sessions. |
| `k9o.me.api_tokens.list` | List API tokens. |
| `k9o.me.api_tokens.create` | Create a token from `label:` and `scope_manifest:` (optional `ttl_seconds:`). |
| `k9o.me.api_tokens.delete` | Delete an API token. |

#### Organization

`k9o.orgs` lists organizations and `k9o.org` administers the active one.

##### Organizations

| Method | What it does |
|---|---|
| `k9o.orgs.list` | List your organizations. |
| `k9o.orgs.get` | Read one by slug. |
| `k9o.orgs.current` | Read the active organization. |
| `k9o.orgs.restore` | Restore a deleted organization. |

##### Administration

| Method | What it does |
|---|---|
| `k9o.org.get` | Read the active organization. |
| `k9o.org.members.list` | List members. Options: `user_id:`, `role:`, `acceptance_status:`, `status:`, `state:`. |
| `k9o.org.members.invite` | Invite a member by email and role. |
| `k9o.org.members.remove` | Remove a member. |
| `k9o.org.groups.list` | List groups, optionally for one `user_id:`. |
| `k9o.org.groups.get` | Read one group. |
| `k9o.org.audit_log.query` | Search organization audit events by `type:` and `limit:`. |
| `k9o.org.gate.roles.list` | List role grants. |
| `k9o.org.gate.roles.grant` | Grant a role to a user (`user_id:`, `role:`, optional `decision_reason:`). |
| `k9o.org.gate.roles.get` | Read one grant. |
| `k9o.org.gate.roles.revoke` | Revoke a grant. |
| `k9o.org.gate.idp_providers.list` | List identity providers. |
| `k9o.org.gate.idp_providers.create` | Add a provider: `idp_provider:`, `display_name:`, `client_id:`, `client_secret_ref:`, `tier_gating:`. |
| `k9o.org.gate.idp_providers.get` | Read one provider. |
| `k9o.org.gate.idp_providers.configure` | Change a provider. |
| `k9o.org.gate.idp_providers.delete` | Remove a provider. |
| `k9o.org.smtp.set` | Save the mail server: `host:`, `port:`, `username:`, `password_ref:`, `from_address:`. |
| `k9o.org.smtp.test` | Send a test email to `to:`, with an optional `subject:`. |
| `k9o.org.smtp.unset` | Remove the mail server settings. |
| `k9o.org.default_llm.get` | Read the default model. |
| `k9o.org.default_llm.set` | Set the default model from a model id. |

#### Vault secrets

`k9o.kibo.vault.secrets` stores and reveals secrets in the project's vault.

| Method | What it does |
|---|---|
| `k9o.kibo.vault.secrets.list` | List secrets by prefix. |
| `k9o.kibo.vault.secrets.get` | Read a secret by name (`region:` is required). |
| `k9o.kibo.vault.secrets.create` | Store a new secret. |
| `k9o.kibo.vault.secrets.reveal_challenge` | Get a one-time challenge for revealing. |
| `k9o.kibo.vault.secrets.reveal` | Reveal the value using the challenge. |
| `k9o.kibo.vault.secrets.update` | Replace the value. |
| `k9o.kibo.vault.secrets.rotate` | Rotate the secret. |
| `k9o.kibo.vault.secrets.move` | Move to a new path. |
| `k9o.kibo.vault.secrets.delete` | Delete the secret. |

### Response metadata

| Field | What it holds |
|---|---|
| `meta.cursor` | Pagination: `next` and `total_count`. |
| `meta.context` | Request tracing: `request_id`. |
| `meta.timing` | Server time: `total_ms`. |
| `meta.warnings` | List of non-fatal warnings, each with `code` and `message`. |
| `meta.idempotency` | `replayed` flag for repeated requests. |
| `meta.subscription` | `is_initial` flag for streamed events. |
| `meta.cost` | Usage cost details as a hash. |

### Error attributes

| Attribute | Meaning |
|---|---|
| `code` | Error code such as `K9O_NOT_FOUND`. |
| `message` | Human-readable explanation. |
| `recommendation` | Suggested next step, or `nil`. |
| `status` | HTTP status, or `nil` if no request was made. |
| `request_id` | Server trace id. Quote it when contacting support. |
| `context` | Read-only details for the error. |

The server may send codes not listed here, so keep a fallback branch.

### Error codes

| Code | When |
|---|---|
| `K9O_INVALID_BASE_URL` | `base_url` has a path, query or bad scheme. |
| `K9O_MISSING_PROJECT_CONTEXT` | A project call was made without `project_slug`. |
| `K9O_INVALID_FIELD_VALUE` | An argument failed validation before sending. |
| `K9O_UPSTREAM_UNAVAILABLE` | Network failure reaching the gateway. |
| `K9O_INTERNAL_ERROR` | The response could not be read. |

`error.to_s` reads like `[K9O_NOT_FOUND] Collection not found (status=404)`.

### Retries

- GET, HEAD, OPTIONS and DELETE are retried on network errors.
- They are also retried on 429, 502, 503 and 504.
- The default is 3 retries with exponential backoff.
- Other methods are never retried.

### Regional hosts

- A platform host is `api.<apex>` or `api-staging.<apex>`, on any apex.
- With `org_slug`, the SDK builds the org host `<org_slug>.<host>`.
- A region-free org host gets one credential-free `HEAD` request to learn its region.
- Later requests go to the regional host, which must share the org, family and apex.
- Any other base URL (internal, air-gapped, localhost) is used exactly as given.
- `https://api.k9o.io` is only the default when `base_url:` is omitted.

### Related packages

| Package | What it is |
|---|---|
| `@k9o/core` | TypeScript SDK |
| `@k9o/cli` | Command-line tool |

## License

Apache-2.0 © Formelo Inc. See `LICENSE` and `NOTICE`.
