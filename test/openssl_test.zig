const std = @import("std");

const evalCode = @import("test_helper.zig").evalCode;
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

test "OpenSSL::Digest subclasses expose Ruby-compatible class helpers" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;

    const result = evalCodeWithOutput(
        \\require "openssl"
        \\puts OpenSSL::Digest::SHA256.hexdigest("abc")
        \\puts OpenSSL::Digest::SHA256.digest("abc").bytesize
        \\puts OpenSSL::Digest::SHA256.method(:hexdigest).arity
        \\puts OpenSSL::Digest.hexdigest("SHA256", "abc")
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n32\n1\nba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "OpenSSL::Digest::MD5 exposes class and instance digests" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "openssl"
        \\puts OpenSSL::Digest::MD5.hexdigest("abc")
        \\puts OpenSSL::Digest::MD5.new("abc").hexdigest
    , &stdout_buf, &stderr_buf);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("900150983cd24fb0d6963f7d28e17f72\n900150983cd24fb0d6963f7d28e17f72\n", result.stdout);
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

test "OpenSSL::Cipher#iv_len= overrides the IV length" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "openssl"
        \\key = "k" * 32
        \\encryptor = OpenSSL::Cipher.new("aes-256-gcm")
        \\encryptor.encrypt
        \\encryptor.key = key
        \\encryptor.iv_len = 16
        \\iv = encryptor.random_iv
        \\encryptor.auth_data = "ad"
        \\encrypted = encryptor.update("secret") + encryptor.final
        \\tag = encryptor.auth_tag
        \\decryptor = OpenSSL::Cipher.new("aes-256-gcm")
        \\decryptor.decrypt
        \\decryptor.key = key
        \\decryptor.iv_len = 16
        \\decryptor.iv = iv
        \\decryptor.auth_tag = tag
        \\decryptor.auth_data = "ad"
        \\puts [encryptor.iv_len, iv.bytesize, decryptor.update(encrypted) + decryptor.final].inspect
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("[16, 16, \"secret\"]\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "OpenSSL::Cipher#iv_len= rejects non-AEAD ciphers" {
    var stdout_buf: [1024]u8 = undefined;
    var stderr_buf: [1024]u8 = undefined;
    const result = evalCodeWithOutput(
        \\require "openssl"
        \\cipher = OpenSSL::Cipher.new("aes-256-cbc")
        \\begin
        \\  cipher.iv_len = 16
        \\rescue OpenSSL::Cipher::CipherError => e
        \\  puts e.message
        \\end
    , &stdout_buf, &stderr_buf);

    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("cipher does not support AEAD\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "require loads RubyGems security with OpenSSL cipher defaults" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const result = try std.process.run(allocator, threaded.io(), .{
        .argv = &.{
            "zig-out/bin/cora",
            "-Izig-out/ext/rubygems/lib",
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

test "Digest copies own independent native contexts and algorithm metadata" {
    const result = try evalCode(
        \\require "digest"
        \\original = Digest::SHA1.new
        \\original << "a"
        \\hidden = original.instance_variables.empty?
        \\copy = original.dup
        \\clone = original.clone
        \\original << "bc"
        \\copy << "x"
        \\original.instance_variable_set(:@algorithm_name, "MD5")
        \\original.reset
        \\hidden && original.name == "SHA1" && original.hexdigest == Digest::SHA1.hexdigest("") &&
        \\  copy.hexdigest == Digest::SHA1.hexdigest("ax") && clone.hexdigest == Digest::SHA1.hexdigest("a")
    );
    try std.testing.expect(result.isTrue());
}

test "Digest SHA2 preserves variant selection when creating reset copies" {
    const result = try evalCode(
        \\require "digest/sha2"
        \\[256, 384, 512].all? do |bits|
        \\  digest = Digest::SHA2.new(bits)
        \\  digest << "abc"
        \\  expected = OpenSSL::Digest.hexdigest("SHA#{bits}", "abc")
        \\  digest.hexdigest == expected && Digest::SHA2.hexdigest("abc", bits) == expected &&
        \\    digest.new.digest_length == bits / 8 && digest.new.hexdigest == OpenSSL::Digest.hexdigest("SHA#{bits}", "") &&
        \\    digest.hexdigest == expected
        \\end
    );
    try std.testing.expect(result.isTrue());
}
