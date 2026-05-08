# Boots vendored RubyGems under Cora without relying on MRI at runtime.
# Cora's stdlib lives on the default $LOAD_PATH, but vendored libraries remain
# opt-in so harnesses control when they are visible.

$LOAD_PATH.unshift(File.expand_path("../ext/rubygems/lib", __dir__))

require "rubygems/gem_runner"

Gem::GemRunner.new.run(ARGV.clone)
