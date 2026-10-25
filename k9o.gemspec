# frozen_string_literal: true

require_relative 'lib/k9o/version'

Gem::Specification.new do |spec|
  spec.name        = 'k9o'
  spec.version     = K9o::VERSION
  spec.authors     = ['Kilimanjaro']
  spec.email       = ['engineering@kilimanjaro.dev']

  spec.summary     = 'Kilimanjaro platform SDK for Ruby'
  spec.description = 'Idiomatic Ruby SDK — create_client + data DSL + projects + KError. snake_case + raise K9o::KError.'
  spec.homepage    = 'https://kilimanjaro.dev'
  spec.license     = 'Apache-2.0'

  spec.required_ruby_version = '>= 3.2.0'

  # Platform gems: the publish pipeline sets K9O_GEM_PLATFORM (e.g. arm64-darwin,
  # x86_64-linux) when building a gem that bundles the kibo ZK native lib for that
  # platform. Unset → the pure-Ruby gem (the universal fallback; `k9o.kibo` is
  # simply unavailable where no platform gem matches).
  if (gem_plat = ENV['K9O_GEM_PLATFORM']) && !gem_plat.empty?
    spec.platform = gem_plat
  end

  spec.metadata = {
    'homepage_uri' => 'https://kilimanjaro.dev',
    'documentation_uri' => 'https://docs.kilimanjaro.dev',
    'source_code_uri' => 'https://github.com/k9o-dev/sdk-ruby',
    'changelog_uri' => 'https://github.com/k9o-dev/sdk-ruby/blob/main/CHANGELOG.md'
  }

  # Ruby sources + the CI-injected kibo native lib (one per platform gem; the
  # generated uniffi binding under lib/k9o/_ffi/ is picked up by the .rb glob).
  spec.files = Dir.glob('lib/**/*.rb') +
               Dir.glob('lib/k9o/_ffi/*.{dylib,so,bundle,dll}') +
               Dir.glob('sig/**/*.rbs') +
               %w[README.md CHANGELOG.md LICENSE NOTICE k9o.gemspec]
  spec.require_paths = ['lib']

  spec.add_development_dependency 'minitest', '~> 5.20'
end
