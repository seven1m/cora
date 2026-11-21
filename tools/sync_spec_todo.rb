#!/usr/bin/env ruby
# Sync the porting tracker with ../ruby_spec and local spec files.
# Usage: ruby tools/sync_spec_todo.rb [path/to/ruby_spec]
# Matching files retain their recorded status; this script does not run specs.

abort "Usage: #{$PROGRAM_NAME} [path/to/ruby_spec]" if ARGV.length > 1

root = File.expand_path("..", __dir__)
upstream = File.expand_path(ARGV[0] || "../ruby_spec", root)
local = File.join(root, "spec")
todo = File.join(local, "TODO.md")
abort "Upstream spec directory not found: #{upstream}" unless File.directory?(upstream)

original = File.read(todo)
preamble, body = original.split("## Specs\n", 2)
abort "Missing ## Specs section in #{todo}" unless body
statuses = body.scan(/^- \[([ x-])\] (.+)$/).to_h { |status, path| [path, status] }
paths = Dir.glob("**/*_spec.rb", base: upstream).select do |path|
  File.file?(File.join(upstream, path))
end
abort "No upstream specs found in #{upstream}" if paths.empty?

counts = Hash.new(0)
sections = paths.group_by { |path| File.dirname(path) }.sort.map do |directory, specs|
  entries = specs.sort.map do |path|
    local_path = File.join(local, path)
    status = if !File.file?(local_path)
      " "
    elsif File.binread(local_path) != File.binread(File.join(upstream, path))
      "-"
    else
      # Equality alone cannot establish that a newly discovered spec passes.
      statuses[path] == "x" ? "x" : "-"
    end
    counts[status] += 1
    "- [#{status}] #{path}"
  end
  "### #{directory}\n#{entries.join("\n")}"
end

updated = "#{preamble}## Specs\n#{sections.join("\n\n")}\n"
File.write(todo, updated) unless updated == original
puts "Synced #{paths.length} specs: #{counts['x']} fully passing, " \
     "#{counts['-']} partial, #{counts[' ']} missing."
