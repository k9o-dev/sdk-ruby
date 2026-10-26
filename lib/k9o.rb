# frozen_string_literal: true

# k9o — Kilimanjaro platform SDK for Ruby.
# Idiomatic: snake_case methods + raise K9o::KError +
# Net::HTTP transport.
#
#   k9o = K9o.create_client(
#     base_url: "https://acme.api.k9o.io",
#     api_key: ENV["K9O_API_KEY"],
#     org_slug: "acme",
#     project_slug: "member-portal",
#   )
#
#   begin
#     response = k9o.from("posts").select.limit(10).execute
#     response.data.each { |row| puts row }
#
#     session = k9o.gate.sign_in(email: "u@x.com", password: "...")
#     puts "signed in: #{session.data['user']['id']}"
#   rescue K9o::KError => e
#     warn "[#{e.code}] #{e.message}: #{e.recommendation}"
#     raise
#   end

require_relative 'k9o/version'
require_relative 'k9o/kerror'
require_relative 'k9o/envelope'
require_relative 'k9o/url_grammar'
require_relative 'k9o/region'
require_relative 'k9o/http_transport'
require_relative 'k9o/data'
require_relative 'k9o/query'
require_relative 'k9o/projects'
require_relative 'k9o/gate'
require_relative 'k9o/studio'
require_relative 'k9o/compute'
require_relative 'k9o/ai'
require_relative 'k9o/storage'
require_relative 'k9o/realtime'
require_relative 'k9o/streams'
require_relative 'k9o/approvals'
require_relative 'k9o/schema'
require_relative 'k9o/migrations'
require_relative 'k9o/functions'
require_relative 'k9o/policies'
require_relative 'k9o/audit'
require_relative 'k9o/orgs'
require_relative 'k9o/me'
require_relative 'k9o/org'
# kibo ZK BYOK/HYOK crypto — self-guards its native binding (LoadError-safe), so
# requiring k9o never breaks on a platform without the kibo native lib.
require_relative 'k9o/kibo'
# kibo vault REST surface (client.kibo.vault.secrets) —.
require_relative 'k9o/vault'
# Barbican guardrail SDK — self-guards its native binding (LoadError-safe), so
# requiring k9o never breaks on a platform without the barbican native lib.
require_relative 'k9o/barbican'
require_relative 'k9o/client'
