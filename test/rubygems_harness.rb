# Boots vendored RubyGems under Cora without relying on MRI at runtime.
# Cora's stdlib lives on the default $LOAD_PATH, but vendored libraries remain
# opt-in so harnesses control when they are visible.

require "fileutils"

repo_dir = File.expand_path("..", __dir__)
gem_root = File.join(repo_dir, ".cora", "gems")
spec_cache = File.join(repo_dir, ".cora", "gem-spec-cache")

FileUtils.mkdir_p(gem_root)
FileUtils.mkdir_p(spec_cache)

ENV["GEM_HOME"] ||= gem_root
ENV["GEM_PATH"] ||= gem_root
ENV["GEM_SPEC_CACHE"] ||= spec_cache

$LOAD_PATH.unshift(File.expand_path("../ext/rubygems/lib", __dir__))

require "thread"
require "rubygems/gem_runner"

Gem::GemRunner.new.run(ARGV.clone)
