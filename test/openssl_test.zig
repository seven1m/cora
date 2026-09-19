const std = @import("std");

const evalCodeWithOutput = @import("test_helper.zig").evalCodeWithOutput;

test "require lazily registers OpenSSL" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput(
        \\p defined?(OpenSSL)
        \\begin
        \\  OpenSSL
        \\rescue NameError
        \\  puts "missing"
        \\end
        \\p require("openssl")
        \\p defined?(OpenSSL)
        \\puts OpenSSL::Digest.hexdigest("sha1", "abc")
        \\p require("openssl")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("nil\nmissing\ntrue\n\"constant\"\na9993e364706816aba3e25717850c26c9cd0d89d\nfalse\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "Digest subclasses expose Ruby-compatible class helpers" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput(
        \\require "digest/sha1"
        \\puts Digest::SHA1.hexdigest("foo")
        \\puts Digest::SHA1.base64digest("foo")
        \\puts Digest::SHA1.digest("foo").bytesize
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("0beec7b5ea3f0fdbc95d0dd47f3c5bc275da8a33\nC+7Hteo/D9vJXQ3UfzxbwnXaijM=\n20\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}
test "Digest() converter method returns digest class by name" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput(
        \\require "digest"
        \\puts Digest("SHA256").name
        \\puts Digest(:MD5).name
        \\begin
        \\  Digest("Invalid")
        \\rescue NameError
        \\  puts "NameError"
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("Digest::SHA256\nDigest::MD5\nNameError\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}
test "OpenSSL::Cipher accepts RubyGems default cipher names" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput(
        \\require "openssl"
        \\cipher = OpenSSL::Cipher.new("aes-256-cbc")
        \\puts [OpenSSL::Cipher.ciphers.include?("AES-256-CBC"), cipher.name].inspect
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[true, \"AES-256-CBC\"]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "OpenSSL::Cipher supports authenticated encryption" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "openssl"
        \\key = "k" * 32
        \\encryptor = OpenSSL::Cipher.new("aes-256-gcm")
        \\encryptor.encrypt
        \\encryptor.key = key
        \\iv = encryptor.random_iv
        \\encryptor.auth_data = ""
        \\encrypted = encryptor.update("secret") + encryptor.final
        \\tag = encryptor.auth_tag(16)
        \\decryptor = OpenSSL::Cipher.new("aes-256-gcm")
        \\decryptor.decrypt
        \\decryptor.key = key
        \\decryptor.iv = iv
        \\decryptor.auth_tag = tag
        \\decryptor.auth_data = ""
        \\puts [encryptor.authenticated?, encryptor.key_len, encryptor.iv_len, decryptor.update(encrypted) + decryptor.final].inspect
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[true, 32, 12, \"secret\"]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "OpenSSL supports ActiveSupport key generation and message encryption" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "active_support/key_generator"
        \\require "active_support/message_encryptor"
        \\key = ActiveSupport::KeyGenerator.new("password", iterations: 2).generate_key("salt", 32)
        \\old_key = ActiveSupport::KeyGenerator.new("old-password", iterations: 2).generate_key("salt", 32)
        \\encryptor = ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: ActiveSupport::MessageEncryptor::NullSerializer)
        \\token = encryptor.encrypt_and_sign("secret")
        \\old_encryptor = ActiveSupport::MessageEncryptor.new(old_key, cipher: "aes-256-gcm", serializer: ActiveSupport::MessageEncryptor::NullSerializer)
        \\old_token = old_encryptor.encrypt_and_sign("old-secret")
        \\encryptor.rotate(old_key)
        \\puts [key.bytesize, encryptor.decrypt_and_verify(token), encryptor.decrypt_and_verify(old_token)].inspect
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[32, \"secret\", \"old-secret\"]\n", result.stdout);
    try std.testing.expectEqualStrings("cora: applied compatibility patch for concurrent-ruby-1.3.8\n", result.stderr);
}

test "require loads RubyGems security with OpenSSL cipher defaults" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "build/bin/cora",
            "-Ibuild/ext/rubygems/lib",
            "-e",
            "require \"rubygems\"; require \"rubygems/security\"; puts Gem::Security::KEY_CIPHER.name",
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    try std.testing.expectEqualSlices(u8, "AES-256-CBC\n", result.stdout);
}
