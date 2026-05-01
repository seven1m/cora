# Boots vendored RubyGems 4.0.11 under Cora without relying on MRI at runtime.
# We start at gem_runner directly so the harness exercises real RubyGems boot
# without first depending on Cora exposing MRI-style $LOAD_PATH behavior.

require_relative "../ext/rubygems/lib/rubygems/gem_runner"

Gem::GemRunner.new.run(ARGV.clone)
