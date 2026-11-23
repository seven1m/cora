const std = @import("std");
const test_helper = @import("../test_helper.zig");

const evalCode = test_helper.evalCode;

test "ENV.replace observes source deletions and updates during key coercion" {
    const result = try evalCode(
        \\original = ENV.to_hash
        \\begin
        \\  source = {}
        \\  key = Object.new
        \\  key.define_singleton_method(:to_str) do
        \\    source.delete("skip")
        \\    source["later"] = "updated"
        \\    "kept"
        \\  end
        \\  source[key] = "first"
        \\  source["skip"] = "ignored"
        \\  source["later"] = "old"
        \\  ENV.replace(source)
        \\  ENV.to_hash == {"kept" => "first", "later" => "updated"}
        \\ensure
        \\  ENV.replace(original)
        \\end
    );
    try std.testing.expect(result.toBool());
}

test "ENV.replace preserves earlier writes and releases hash iteration on coercion error" {
    const result = try evalCode(
        \\original = ENV.to_hash
        \\begin
        \\  ENV["cora_replace_stale"] = "retained"
        \\  source = {"cora_replace_first" => "applied"}
        \\  key = Object.new
        \\  key.define_singleton_method(:to_str) do
        \\    source["new_key"] = "rejected"
        \\    "never"
        \\  end
        \\  source[key] = "value"
        \\  rejected = begin
        \\    ENV.replace(source)
        \\    false
        \\  rescue RuntimeError
        \\    true
        \\  end
        \\  source["after_error"] = "allowed"
        \\  rejected && ENV["cora_replace_stale"] == "retained" &&
        \\    ENV["cora_replace_first"] == "applied" && !ENV.key?("new_key")
        \\ensure
        \\  ENV.replace(original)
        \\end
    );
    try std.testing.expect(result.toBool());
}

test "ENV.replace preserves variables added by hash coercion and handles nil deletion" {
    const result = try evalCode(
        \\original = ENV.to_hash
        \\begin
        \\  ENV["cora_replace_stale"] = "removed"
        \\  ENV["cora_replace_nil"] = "removed"
        \\  source = Object.new
        \\  def source.to_hash
        \\    ENV["cora_replace_during_coercion"] = "preserved"
        \\    {"cora_replace_nil" => nil, "cora_replace_kept" => "value"}
        \\  end
        \\  ENV.replace(source)
        \\  preserved = ENV.to_hash == {
        \\    "cora_replace_during_coercion" => "preserved",
        \\    "cora_replace_kept" => "value"
        \\  }
        \\  preserved && ENV.replace(ENV).equal?(ENV) &&
        \\    ENV["cora_replace_kept"] == "value"
        \\ensure
        \\  ENV.replace(original)
        \\end
    );
    try std.testing.expect(result.toBool());
}
