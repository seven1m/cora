const std = @import("std");
const enc = @import("../encoding.zig");
const io_builtin = @import("io.zig");
const vm_mod = @import("../vm.zig");
const value = @import("../value.zig");
const c = @cImport({
    @cInclude("openssl/err.h");
    @cInclude("openssl/evp.h");
    @cInclude("openssl/pem.h");
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/x509_vfy.h");
});

const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const Block = vm_mod.Block;
const Value = value.Value;
const ClassObject = value.ClassObject;
const ModuleObject = value.ModuleObject;

const binary_encoding = enc.Encoding{ .ascii_8bit = .{} };

const NativeSslSocket = struct {
    ssl_ctx: *c.SSL_CTX,
    ssl: *c.SSL,
};

const DigestAlgorithm = enum {
    md5,
    sha1,
    sha256,
    sha384,
    sha512,
};

pub fn register(vm: *VM) !void {
    const openssl_name = try vm.intern("OpenSSL");
    if (vm.object_class.module.constants.contains(openssl_name)) return;
    const openssl_val = try vm.newModule(openssl_name);
    const openssl_mod = openssl_val.toModuleObject();
    try vm.object_class.module.constants.put(openssl_name, .{ .value = openssl_val });

    const openssl_error_name = try vm.intern("OpenSSLError");
    const openssl_error_val = try vm.newClass(openssl_error_name, vm.standard_error_class);
    try openssl_mod.constants.put(openssl_error_name, .{ .value = openssl_error_val });

    const openssl_singleton = try vm.getOrCreateSingletonClass(openssl_val);
    const fixed_length_secure_compare_sym = try vm.intern("fixed_length_secure_compare");
    try openssl_singleton.module.methods.put(
        fixed_length_secure_compare_sym,
        value.MethodEntry.builtin(&builtinOpenSSLFixedLengthSecureCompare, .{ .exact = 2 }),
    );
    try openssl_singleton.module.methods.put(try vm.intern("__ssl_socket_connect"), value.MethodEntry.builtin(&builtinOpenSSLSslSocketConnect, .{ .exact = 3 }));
    try openssl_singleton.module.methods.put(try vm.intern("__ssl_socket_read_nonblock"), value.MethodEntry.builtin(&builtinOpenSSLSslSocketReadNonblock, .{ .exact = 4 }));
    try openssl_singleton.module.methods.put(try vm.intern("__ssl_socket_write_nonblock"), value.MethodEntry.builtin(&builtinOpenSSLSslSocketWriteNonblock, .{ .exact = 3 }));
    try openssl_singleton.module.methods.put(try vm.intern("__ssl_socket_close"), value.MethodEntry.builtin(&builtinOpenSSLSslSocketClose, .{ .exact = 1 }));
    try openssl_singleton.module.methods.put(try vm.intern("__ssl_socket_eof"), value.MethodEntry.builtin(&builtinOpenSSLSslSocketEof, .{ .exact = 1 }));
    try openssl_singleton.module.methods.put(try vm.intern("__ssl_socket_ssl_version"), value.MethodEntry.builtin(&builtinOpenSSLSslSocketSslVersion, .{ .exact = 1 }));
    try openssl_singleton.module.methods.put(try vm.intern("__ssl_socket_cipher"), value.MethodEntry.builtin(&builtinOpenSSLSslSocketCipher, .{ .exact = 1 }));
    try openssl_singleton.module.methods.put(try vm.intern("__ssl_socket_peer_cert_pem"), value.MethodEntry.builtin(&builtinOpenSSLSslSocketPeerCertPem, .{ .exact = 1 }));
    try openssl_singleton.module.methods.put(try vm.intern("__ssl_socket_post_connection_check"), value.MethodEntry.builtin(&builtinOpenSSLSslSocketPostConnectionCheck, .{ .exact = 2 }));

    const digest_name = try vm.intern("Digest");
    const digest_val = try vm.newClass(digest_name, vm.object_class);
    const digest_class = digest_val.toClassObject();
    try openssl_mod.constants.put(digest_name, .{ .value = digest_val });

    const digest_error_name = try vm.intern("DigestError");
    const digest_error_val = try vm.newClass(digest_error_name, openssl_error_val.toClassObject());
    try digest_class.module.constants.put(digest_error_name, .{ .value = digest_error_val });

    const digest_initialize_sym = try vm.intern("initialize");
    try digest_class.module.methods.put(
        digest_initialize_sym,
        value.MethodEntry.builtinWithVisibility(&builtinOpenSSLDigestInitialize, .{ .variadic = 1 }, .private),
    );

    const digest_update_sym = try vm.intern("update");
    try digest_class.module.methods.put(digest_update_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestUpdate, .{ .exact = 1 }));

    const digest_append_sym = try vm.intern("<<");
    try digest_class.module.methods.put(digest_append_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestUpdate, .{ .exact = 1 }));

    const digest_reset_sym = try vm.intern("reset");
    try digest_class.module.methods.put(digest_reset_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestReset, .{ .exact = 0 }));

    const digest_digest_sym = try vm.intern("digest");
    try digest_class.module.methods.put(digest_digest_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestDigest, .{ .exact = 0 }));

    const digest_hexdigest_sym = try vm.intern("hexdigest");
    try digest_class.module.methods.put(digest_hexdigest_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestHexdigest, .{ .exact = 0 }));

    const digest_hexdigest_bang_sym = try vm.intern("hexdigest!");
    try digest_class.module.methods.put(digest_hexdigest_bang_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestHexdigestBang, .{ .exact = 0 }));

    const digest_base64digest_sym = try vm.intern("base64digest");
    try digest_class.module.methods.put(digest_base64digest_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestBase64digest, .{ .exact = 0 }));

    const digest_name_sym = try vm.intern("name");
    try digest_class.module.methods.put(digest_name_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestName, .{ .exact = 0 }));

    const digest_length_sym = try vm.intern("digest_length");
    try digest_class.module.methods.put(digest_length_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestLength, .{ .exact = 0 }));

    const digest_block_length_sym = try vm.intern("block_length");
    try digest_class.module.methods.put(digest_block_length_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestBlockLength, .{ .exact = 0 }));

    const digest_singleton = try vm.getOrCreateSingletonClass(digest_val);
    try digest_singleton.module.methods.put(digest_digest_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestSingletonDigest, .{ .exact = 2 }));
    try digest_singleton.module.methods.put(digest_hexdigest_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestSingletonHexdigest, .{ .exact = 2 }));
    try digest_singleton.module.methods.put(digest_base64digest_sym, value.MethodEntry.builtin(&builtinOpenSSLDigestSingletonBase64digest, .{ .exact = 2 }));

    const hmac_name = try vm.intern("HMAC");
    const hmac_val = try vm.newClass(hmac_name, vm.object_class);
    try openssl_mod.constants.put(hmac_name, .{ .value = hmac_val });

    const hmac_error_name = try vm.intern("HMACError");
    const hmac_error_val = try vm.newClass(hmac_error_name, openssl_error_val.toClassObject());
    try openssl_mod.constants.put(hmac_error_name, .{ .value = hmac_error_val });

    const hmac_singleton = try vm.getOrCreateSingletonClass(hmac_val);
    try hmac_singleton.module.methods.put(digest_digest_sym, value.MethodEntry.builtin(&builtinOpenSSLHMACDigest, .{ .exact = 3 }));
    try hmac_singleton.module.methods.put(digest_hexdigest_sym, value.MethodEntry.builtin(&builtinOpenSSLHMACHexdigest, .{ .exact = 3 }));

    const random_name = try vm.intern("Random");
    const random_val = try vm.newModule(random_name);
    const random_mod = random_val.toModuleObject();
    try openssl_mod.constants.put(random_name, .{ .value = random_val });

    const random_error_name = try vm.intern("RandomError");
    const random_error_val = try vm.newClass(random_error_name, openssl_error_val.toClassObject());
    try random_mod.constants.put(random_error_name, .{ .value = random_error_val });

    const random_singleton = try vm.getOrCreateSingletonClass(random_val);
    const random_bytes_sym = try vm.intern("random_bytes");
    try random_singleton.module.methods.put(random_bytes_sym, value.MethodEntry.builtin(&builtinOpenSSLRandomBytes, .{ .exact = 1 }));
    const pseudo_bytes_sym = try vm.intern("pseudo_bytes");
    try random_singleton.module.methods.put(pseudo_bytes_sym, value.MethodEntry.builtin(&builtinOpenSSLRandomBytes, .{ .exact = 1 }));

    const kdf_name = try vm.intern("KDF");
    const kdf_val = try vm.newModule(kdf_name);
    const kdf_mod = kdf_val.toModuleObject();
    try openssl_mod.constants.put(kdf_name, .{ .value = kdf_val });

    const kdf_error_name = try vm.intern("KDFError");
    const kdf_error_val = try vm.newClass(kdf_error_name, openssl_error_val.toClassObject());
    try kdf_mod.constants.put(kdf_error_name, .{ .value = kdf_error_val });

    const kdf_singleton = try vm.getOrCreateSingletonClass(kdf_val);
    const pbkdf2_sym = try vm.intern("pbkdf2_hmac");
    try kdf_singleton.module.methods.put(pbkdf2_sym, value.MethodEntry.builtin(&builtinOpenSSLKDFPbkdf2Hmac, .{ .variadic = 1 }));
    const scrypt_sym = try vm.intern("scrypt");
    try kdf_singleton.module.methods.put(scrypt_sym, value.MethodEntry.builtin(&builtinOpenSSLKDFScrypt, .{ .variadic = 1 }));
}

fn opensslModule(vm: *VM) VMError!*ModuleObject {
    const openssl_name = try vm.intern("OpenSSL");
    const entry = vm.object_class.module.constants.get(openssl_name) orelse return error.Fatal;
    return entry.value.toModuleObject();
}

fn opensslErrorClass(vm: *VM) VMError!*ClassObject {
    const mod = try opensslModule(vm);
    const name = try vm.intern("OpenSSLError");
    const entry = mod.constants.get(name) orelse return error.Fatal;
    return entry.value.toClassObject();
}

fn digestClass(vm: *VM) VMError!*ClassObject {
    const mod = try opensslModule(vm);
    const name = try vm.intern("Digest");
    const entry = mod.constants.get(name) orelse return error.Fatal;
    return entry.value.toClassObject();
}

fn digestErrorClass(vm: *VM) VMError!*ClassObject {
    const klass = try digestClass(vm);
    const name = try vm.intern("DigestError");
    const entry = klass.module.constants.get(name) orelse return error.Fatal;
    return entry.value.toClassObject();
}

fn kdfModule(vm: *VM) VMError!*ModuleObject {
    const mod = try opensslModule(vm);
    const name = try vm.intern("KDF");
    const entry = mod.constants.get(name) orelse return error.Fatal;
    return entry.value.toModuleObject();
}

fn kdfErrorClass(vm: *VM) VMError!*ClassObject {
    const mod = try kdfModule(vm);
    const name = try vm.intern("KDFError");
    const entry = mod.constants.get(name) orelse return error.Fatal;
    return entry.value.toClassObject();
}

fn sslErrorClass(vm: *VM) VMError!*ClassObject {
    const val = (try vm.resolveConstantPath("OpenSSL::SSL::SSLError")) orelse return opensslErrorClass(vm);
    return val.toClassObject();
}

fn raiseSslError(vm: *VM, message: []const u8) VMError {
    return vm.raiseExceptionFmt(try sslErrorClass(vm), "{s}", .{message});
}

fn raiseCurrentSslError(vm: *VM, prefix: []const u8) VMError {
    var buffer: [256]u8 = undefined;
    const err_code = c.ERR_get_error();
    if (err_code != 0) {
        c.ERR_error_string_n(err_code, &buffer, buffer.len);
        const len = std.mem.indexOfScalar(u8, &buffer, 0) orelse buffer.len;
        return vm.raiseExceptionFmt(try sslErrorClass(vm), "{s}: {s}", .{ prefix, buffer[0..len] });
    }
    return vm.raiseExceptionFmt(try sslErrorClass(vm), "{s}", .{prefix});
}

fn sslStateFromReceiver(vm: *VM, receiver: Value) VMError!?*NativeSslSocket {
    const handle_value = try vm.getInstanceVariable(receiver, "@__ssl_native");
    if (handle_value.isNil()) return null;
    if (!handle_value.isInteger()) return error.Fatal;
    const ptr_value = handle_value.toInteger();
    if (ptr_value <= 0) return error.Fatal;
    return @ptrFromInt(@as(usize, @intCast(ptr_value)));
}

fn setSslStateOnReceiver(vm: *VM, receiver: Value, state: ?*NativeSslSocket) VMError!void {
    const value_to_set = if (state) |ptr|
        Value.integer(@intCast(@intFromPtr(ptr)))
    else
        Value.nil();
    try vm.setInstanceVariable(receiver, "@__ssl_native", value_to_set);
}

fn sslReceiverIo(vm: *VM, receiver: Value) VMError!*value.IoObject {
    const io_value = try vm.getInstanceVariable(receiver, "@io");
    if (!io_value.isIo()) {
        return vm.raiseExceptionFmt(vm.type_error_class, "SSL socket is not wrapping an IO", .{});
    }
    return io_value.toIoObject();
}

fn sslReceiverContext(vm: *VM, receiver: Value) VMError!Value {
    return vm.getInstanceVariable(receiver, "@context");
}

fn contextStringIvar(vm: *VM, context: Value, name: []const u8) VMError!?[]const u8 {
    const value_arg = try vm.getInstanceVariable(context, name);
    if (value_arg.isNil()) return null;
    return (try coerceToStringValueExact(vm, value_arg)).toStringObject().str;
}

fn contextIntegerIvar(vm: *VM, context: Value, name: []const u8) VMError!?i64 {
    const value_arg = try vm.getInstanceVariable(context, name);
    if (value_arg.isNil()) return null;
    return try coerceToI64Exact(vm, value_arg, "bignum too big to convert into `long`");
}

fn contextBoolIvar(vm: *VM, context: Value, name: []const u8, default: bool) VMError!bool {
    const value_arg = try vm.getInstanceVariable(context, name);
    if (value_arg.isNil()) return default;
    return value_arg.isTruthy();
}

fn loadVerifyLocations(vm: *VM, ssl_ctx: *c.SSL_CTX, file: ?[]const u8, path: ?[]const u8) VMError!void {
    const file_z = if (file) |f| try vm.allocCStringZ(f) else null;
    defer if (file_z) |buf| vm.allocator.free(buf);
    const path_z = if (path) |p| try vm.allocCStringZ(p) else null;
    defer if (path_z) |buf| vm.allocator.free(buf);

    if (c.SSL_CTX_load_verify_locations(
        ssl_ctx,
        if (file_z) |buf| buf.ptr else null,
        if (path_z) |buf| buf.ptr else null,
    ) != 1) {
        return raiseCurrentSslError(vm, "SSL_CTX_load_verify_locations failed");
    }
}

fn configureSslCertStore(vm: *VM, ssl_ctx: *c.SSL_CTX, context: Value, verify_mode: i64) VMError!void {
    if (verify_mode == 0) return;

    var loaded_paths = false;
    if (try contextStringIvar(vm, context, "@ca_file")) |ca_file| {
        try loadVerifyLocations(vm, ssl_ctx, ca_file, null);
        loaded_paths = true;
    }
    if (try contextStringIvar(vm, context, "@ca_path")) |ca_path| {
        try loadVerifyLocations(vm, ssl_ctx, null, ca_path);
        loaded_paths = true;
    }

    const cert_store = try vm.getInstanceVariable(context, "@cert_store");
    if (!cert_store.isNil()) {
        if ((try vm.getInstanceVariable(cert_store, "@set_default_paths")).isTruthy()) {
            if (c.SSL_CTX_set_default_verify_paths(ssl_ctx) != 1) {
                return raiseCurrentSslError(vm, "SSL_CTX_set_default_verify_paths failed");
            }
            loaded_paths = true;
        }

        const files = try vm.getInstanceVariable(cert_store, "@files");
        if (files.isArray()) {
            for (files.toArrayObject().elements.items) |entry| {
                const file = (try coerceToStringValueExact(vm, entry)).toStringObject().str;
                try loadVerifyLocations(vm, ssl_ctx, file, null);
                loaded_paths = true;
            }
        }

        const paths = try vm.getInstanceVariable(cert_store, "@paths");
        if (paths.isArray()) {
            for (paths.toArrayObject().elements.items) |entry| {
                const path = (try coerceToStringValueExact(vm, entry)).toStringObject().str;
                try loadVerifyLocations(vm, ssl_ctx, null, path);
                loaded_paths = true;
            }
        }
    }

    if (!loaded_paths) {
        if (c.SSL_CTX_set_default_verify_paths(ssl_ctx) != 1) {
            return raiseCurrentSslError(vm, "SSL_CTX_set_default_verify_paths failed");
        }
    }
}

fn createSslState(vm: *VM, receiver: Value) VMError!*NativeSslSocket {
    const io = try sslReceiverIo(vm, receiver);
    if (io.closed) return vm.raiseExceptionFmt(vm.io_error_class, "closed stream", .{});

    const context = try sslReceiverContext(vm, receiver);
    const ssl_ctx = c.SSL_CTX_new(c.TLS_client_method()) orelse return raiseCurrentSslError(vm, "SSL_CTX_new failed");
    errdefer c.SSL_CTX_free(ssl_ctx);

    const verify_mode = (try contextIntegerIvar(vm, context, "@verify_mode")) orelse 0;
    c.SSL_CTX_set_verify(ssl_ctx, @intCast(verify_mode), null);
    try configureSslCertStore(vm, ssl_ctx, context, verify_mode);

    if (try contextStringIvar(vm, context, "@ciphers")) |ciphers| {
        const ciphers_z = try vm.allocCStringZ(ciphers);
        defer vm.allocator.free(ciphers_z);
        if (c.SSL_CTX_set_cipher_list(ssl_ctx, ciphers_z.ptr) != 1) {
            return raiseCurrentSslError(vm, "SSL_CTX_set_cipher_list failed");
        }
    }

    const ssl = c.SSL_new(ssl_ctx) orelse return raiseCurrentSslError(vm, "SSL_new failed");
    errdefer c.SSL_free(ssl);

    if (c.SSL_set_fd(ssl, io.fd) != 1) {
        return raiseCurrentSslError(vm, "SSL_set_fd failed");
    }

    const hostname_value = try vm.getInstanceVariable(receiver, "@hostname");
    if (!hostname_value.isNil()) {
        const hostname = (try coerceToStringValueExact(vm, hostname_value)).toStringObject().str;
        const hostname_z = try vm.allocCStringZ(hostname);
        defer vm.allocator.free(hostname_z);

        if (c.SSL_set_tlsext_host_name(ssl, hostname_z.ptr) != 1) {
            return raiseCurrentSslError(vm, "SSL_set_tlsext_host_name failed");
        }

        if (try contextBoolIvar(vm, context, "@verify_hostname", false) and verify_mode != 0) {
            const params = c.SSL_get0_param(ssl) orelse return raiseSslError(vm, "SSL_get0_param failed");
            if (c.X509_VERIFY_PARAM_set1_host(params, hostname_z.ptr, 0) != 1) {
                return raiseCurrentSslError(vm, "X509_VERIFY_PARAM_set1_host failed");
            }
        }
    }

    const state = std.heap.c_allocator.create(NativeSslSocket) catch return error.Fatal;
    state.* = .{ .ssl_ctx = ssl_ctx, .ssl = ssl };
    return state;
}

fn destroySslState(state: *NativeSslSocket) void {
    _ = c.SSL_shutdown(state.ssl);
    c.SSL_free(state.ssl);
    c.SSL_CTX_free(state.ssl_ctx);
    std.heap.c_allocator.destroy(state);
}

fn waitSymbol(vm: *VM, name: []const u8) VMError!Value {
    const sym = try vm.intern(name);
    return Value.fromObject(&sym.object);
}

fn sslConnectImpl(vm: *VM, receiver: Value, exception: bool) VMError!Value {
    if (try sslStateFromReceiver(vm, receiver)) |_| return receiver;

    const state = try createSslState(vm, receiver);
    errdefer destroySslState(state);

    const rc = c.SSL_connect(state.ssl);
    if (rc != 1) {
        const err_code = c.SSL_get_error(state.ssl, rc);
        if (!exception) {
            if (err_code == c.SSL_ERROR_WANT_READ) return waitSymbol(vm, "wait_readable");
            if (err_code == c.SSL_ERROR_WANT_WRITE) return waitSymbol(vm, "wait_writable");
        }
        return raiseCurrentSslError(vm, "SSL_connect failed");
    }

    try setSslStateOnReceiver(vm, receiver, state);
    return receiver;
}

fn requireSslState(vm: *VM, receiver: Value) VMError!*NativeSslSocket {
    return (try sslStateFromReceiver(vm, receiver)) orelse raiseSslError(vm, "SSL socket is not connected");
}

fn isKindOfClass(vm: *VM, value_arg: Value, expected: *ClassObject) bool {
    var current: ?*ClassObject = vm.getClass(value_arg);
    while (current) |klass| {
        if (klass == expected) return true;
        current = klass.superclass;
    }
    return false;
}

fn binaryString(vm: *VM, bytes: []const u8) VMError!Value {
    return vm.newStringWithEncoding(bytes, false, binary_encoding);
}

fn coerceToStringValueExact(vm: *VM, arg: Value) VMError!Value {
    return switch (try vm.probeToStringValue(arg)) {
        .string => |str| str,
        .missing, .nil_result => vm.raiseExceptionFmt(
            vm.type_error_class,
            "no implicit conversion of {s} into String",
            .{vm.className(arg)},
        ),
    };
}

fn coerceToI64Exact(vm: *VM, arg: Value, range_error_message: []const u8) VMError!i64 {
    const class_name = vm.className(arg);
    const missing_message = std.fmt.allocPrint(vm.allocator, "no implicit conversion of {s} into Integer", .{class_name}) catch return error.Fatal;
    defer vm.allocator.free(missing_message);
    const non_integer_message = std.fmt.allocPrint(vm.allocator, "can't convert {s} to Integer ({s}#to_int gives non-Integer)", .{ class_name, class_name }) catch return error.Fatal;
    defer vm.allocator.free(non_integer_message);
    return arg.coerceToI64ViaToInt(vm, missing_message, non_integer_message, range_error_message);
}

fn timingSafeEqualSlices(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var acc: u8 = 0;
    for (a, 0..) |byte, idx| {
        acc |= byte ^ b[idx];
    }
    return acc == 0;
}

fn canonicalDigestName(alg: DigestAlgorithm) []const u8 {
    return switch (alg) {
        .md5 => "MD5",
        .sha1 => "SHA1",
        .sha256 => "SHA256",
        .sha384 => "SHA384",
        .sha512 => "SHA512",
    };
}

fn digestLength(alg: DigestAlgorithm) usize {
    return switch (alg) {
        .md5 => 16,
        .sha1 => 20,
        .sha256 => 32,
        .sha384 => 48,
        .sha512 => 64,
    };
}

fn digestBlockLength(alg: DigestAlgorithm) usize {
    return switch (alg) {
        .md5, .sha1, .sha256 => 64,
        .sha384, .sha512 => 128,
    };
}

fn normalizedDigestName(name: []const u8, buffer: *[16]u8) ?[]const u8 {
    var len: usize = 0;
    for (name) |byte| {
        if (byte == '-' or byte == '_') continue;
        if (len >= buffer.len) return null;
        buffer[len] = std.ascii.toUpper(byte);
        len += 1;
    }
    return buffer[0..len];
}

fn resolveDigestAlgorithmByName(name: []const u8) ?DigestAlgorithm {
    var buffer: [16]u8 = undefined;
    const normalized = normalizedDigestName(name, &buffer) orelse return null;
    if (std.mem.eql(u8, normalized, "MD5")) return .md5;
    if (std.mem.eql(u8, normalized, "SHA1")) return .sha1;
    if (std.mem.eql(u8, normalized, "SHA256")) return .sha256;
    if (std.mem.eql(u8, normalized, "SHA384")) return .sha384;
    if (std.mem.eql(u8, normalized, "SHA512")) return .sha512;
    return null;
}

fn raiseDigestError(vm: *VM, name: []const u8) VMError {
    return vm.raiseExceptionFmt(try digestErrorClass(vm), "unsupported digest algorithm: {s}", .{name});
}

fn resolveDigestAlgorithmFromValue(vm: *VM, arg: Value) VMError!DigestAlgorithm {
    const digest_klass = try digestClass(vm);
    if (isKindOfClass(vm, arg, digest_klass)) {
        const name_value = try vm.getInstanceVariable(arg, "@algorithm_name");
        if (!name_value.isString()) return error.Fatal;
        return resolveDigestAlgorithmByName(name_value.toStringObject().str) orelse return error.Fatal;
    }

    const name_value = try coerceToStringValueExact(vm, arg);
    const name = name_value.toStringObject().str;
    return resolveDigestAlgorithmByName(name) orelse return raiseDigestError(vm, name);
}

fn computeDigest(alg: DigestAlgorithm, input: []const u8, out: *[64]u8) usize {
    return switch (alg) {
        .md5 => blk: {
            var digest: [16]u8 = undefined;
            std.crypto.hash.Md5.hash(input, &digest, .{});
            @memcpy(out[0..digest.len], &digest);
            break :blk digest.len;
        },
        .sha1 => blk: {
            var digest: [20]u8 = undefined;
            std.crypto.hash.Sha1.hash(input, &digest, .{});
            @memcpy(out[0..digest.len], &digest);
            break :blk digest.len;
        },
        .sha256 => blk: {
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});
            @memcpy(out[0..digest.len], &digest);
            break :blk digest.len;
        },
        .sha384 => blk: {
            var digest: [48]u8 = undefined;
            std.crypto.hash.sha2.Sha384.hash(input, &digest, .{});
            @memcpy(out[0..digest.len], &digest);
            break :blk digest.len;
        },
        .sha512 => blk: {
            var digest: [64]u8 = undefined;
            std.crypto.hash.sha2.Sha512.hash(input, &digest, .{});
            @memcpy(out[0..digest.len], &digest);
            break :blk digest.len;
        },
    };
}

fn computeHmac(alg: DigestAlgorithm, key: []const u8, input: []const u8, out: *[64]u8) usize {
    return switch (alg) {
        .md5 => blk: {
            var digest: [16]u8 = undefined;
            std.crypto.auth.hmac.HmacMd5.create(&digest, input, key);
            @memcpy(out[0..digest.len], &digest);
            break :blk digest.len;
        },
        .sha1 => blk: {
            var digest: [20]u8 = undefined;
            std.crypto.auth.hmac.HmacSha1.create(&digest, input, key);
            @memcpy(out[0..digest.len], &digest);
            break :blk digest.len;
        },
        .sha256 => blk: {
            var digest: [32]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha256.create(&digest, input, key);
            @memcpy(out[0..digest.len], &digest);
            break :blk digest.len;
        },
        .sha384 => blk: {
            var digest: [48]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha384.create(&digest, input, key);
            @memcpy(out[0..digest.len], &digest);
            break :blk digest.len;
        },
        .sha512 => blk: {
            var digest: [64]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha512.create(&digest, input, key);
            @memcpy(out[0..digest.len], &digest);
            break :blk digest.len;
        },
    };
}

fn digestHex(vm: *VM, bytes: []const u8) VMError!Value {
    const hex_chars = "0123456789abcdef";
    const encoded = vm.allocator.alloc(u8, bytes.len * 2) catch return error.Fatal;
    defer vm.allocator.free(encoded);
    for (bytes, 0..) |byte, idx| {
        encoded[idx * 2] = hex_chars[byte >> 4];
        encoded[idx * 2 + 1] = hex_chars[byte & 0x0f];
    }
    return vm.newString(encoded, false);
}

fn digestBase64(vm: *VM, bytes: []const u8) VMError!Value {
    const size = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = vm.allocator.alloc(u8, size) catch return error.Fatal;
    defer vm.allocator.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    return vm.newString(encoded, false);
}

fn digestDataBytes(vm: *VM, receiver: Value) VMError![]const u8 {
    const data_value = try vm.getInstanceVariable(receiver, "@data");
    if (!data_value.isString()) return "";
    return data_value.toStringObject().str;
}

fn digestAlgorithmForReceiver(vm: *VM, receiver: Value) VMError!DigestAlgorithm {
    const name_value = try vm.getInstanceVariable(receiver, "@algorithm_name");
    if (!name_value.isString()) return error.Fatal;
    return resolveDigestAlgorithmByName(name_value.toStringObject().str) orelse return error.Fatal;
}

fn setDigestState(vm: *VM, receiver: Value, alg: DigestAlgorithm, data: []const u8) VMError!void {
    try vm.setInstanceVariable(receiver, "@algorithm_name", try vm.newString(canonicalDigestName(alg), false));
    try vm.setInstanceVariable(receiver, "@data", try binaryString(vm, data));
}

fn appendDigestData(vm: *VM, receiver: Value, chunk: []const u8) VMError!void {
    const existing = try digestDataBytes(vm, receiver);
    const combined = vm.allocator.alloc(u8, existing.len + chunk.len) catch return error.Fatal;
    defer vm.allocator.free(combined);
    @memcpy(combined[0..existing.len], existing);
    @memcpy(combined[existing.len..], chunk);
    try vm.setInstanceVariable(receiver, "@data", try binaryString(vm, combined));
}

fn requiredKeywordMessage(vm: *VM, missing: []const []const u8) VMError {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.allocator);

    if (missing.len == 1) {
        out.appendSlice(vm.allocator, "missing keyword: :") catch return error.Fatal;
        out.appendSlice(vm.allocator, missing[0]) catch return error.Fatal;
    } else {
        out.appendSlice(vm.allocator, "missing keywords: ") catch return error.Fatal;
        for (missing, 0..) |name, idx| {
            if (idx != 0) out.appendSlice(vm.allocator, ", ") catch return error.Fatal;
            out.append(vm.allocator, ':') catch return error.Fatal;
            out.appendSlice(vm.allocator, name) catch return error.Fatal;
        }
    }

    return vm.raiseExceptionFmt(vm.argument_error_class, "{s}", .{out.items});
}

pub fn builtinOpenSSLFixedLengthSecureCompare(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const lhs = (try coerceToStringValueExact(vm, args[0])).toStringObject().str;
    const rhs = (try coerceToStringValueExact(vm, args[1])).toStringObject().str;
    if (lhs.len != rhs.len) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "inputs must be of equal length", .{});
    }
    return Value.boolean(timingSafeEqualSlices(lhs, rhs));
}

pub fn builtinOpenSSLDigestInitialize(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCountRange(args, 1, 2);
    const alg = try resolveDigestAlgorithmFromValue(vm, args[0]);
    const initial_data = if (args.len == 2)
        (try coerceToStringValueExact(vm, args[1])).toStringObject().str
    else
        "";
    try setDigestState(vm, receiver, alg, initial_data);
    return receiver;
}

pub fn builtinOpenSSLDigestUpdate(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const chunk = (try coerceToStringValueExact(vm, args[0])).toStringObject().str;
    try appendDigestData(vm, receiver, chunk);
    return receiver;
}

pub fn builtinOpenSSLDigestReset(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const alg = try digestAlgorithmForReceiver(vm, receiver);
    try setDigestState(vm, receiver, alg, "");
    return receiver;
}

pub fn builtinOpenSSLDigestName(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const alg = try digestAlgorithmForReceiver(vm, receiver);
    return vm.newString(canonicalDigestName(alg), false);
}

pub fn builtinOpenSSLDigestLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const alg = try digestAlgorithmForReceiver(vm, receiver);
    return Value.integer(@intCast(digestLength(alg)));
}

pub fn builtinOpenSSLDigestBlockLength(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const alg = try digestAlgorithmForReceiver(vm, receiver);
    return Value.integer(@intCast(digestBlockLength(alg)));
}

pub fn builtinOpenSSLDigestDigest(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const alg = try digestAlgorithmForReceiver(vm, receiver);
    const data = try digestDataBytes(vm, receiver);
    var digest_buf: [64]u8 = undefined;
    const len = computeDigest(alg, data, &digest_buf);
    return binaryString(vm, digest_buf[0..len]);
}

pub fn builtinOpenSSLDigestHexdigest(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const alg = try digestAlgorithmForReceiver(vm, receiver);
    const data = try digestDataBytes(vm, receiver);
    var digest_buf: [64]u8 = undefined;
    const len = computeDigest(alg, data, &digest_buf);
    return digestHex(vm, digest_buf[0..len]);
}

pub fn builtinOpenSSLDigestHexdigestBang(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const alg = try digestAlgorithmForReceiver(vm, receiver);
    const data = try digestDataBytes(vm, receiver);
    var digest_buf: [64]u8 = undefined;
    const len = computeDigest(alg, data, &digest_buf);
    try setDigestState(vm, receiver, alg, "");
    return digestHex(vm, digest_buf[0..len]);
}

pub fn builtinOpenSSLDigestBase64digest(vm: *VM, receiver: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 0);
    const alg = try digestAlgorithmForReceiver(vm, receiver);
    const data = try digestDataBytes(vm, receiver);
    var digest_buf: [64]u8 = undefined;
    const len = computeDigest(alg, data, &digest_buf);
    return digestBase64(vm, digest_buf[0..len]);
}

pub fn builtinOpenSSLDigestSingletonDigest(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const alg = try resolveDigestAlgorithmFromValue(vm, args[0]);
    const data = (try coerceToStringValueExact(vm, args[1])).toStringObject().str;
    var digest_buf: [64]u8 = undefined;
    const len = computeDigest(alg, data, &digest_buf);
    return binaryString(vm, digest_buf[0..len]);
}

pub fn builtinOpenSSLDigestSingletonHexdigest(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const alg = try resolveDigestAlgorithmFromValue(vm, args[0]);
    const data = (try coerceToStringValueExact(vm, args[1])).toStringObject().str;
    var digest_buf: [64]u8 = undefined;
    const len = computeDigest(alg, data, &digest_buf);
    return digestHex(vm, digest_buf[0..len]);
}

pub fn builtinOpenSSLDigestSingletonBase64digest(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const alg = try resolveDigestAlgorithmFromValue(vm, args[0]);
    const data = (try coerceToStringValueExact(vm, args[1])).toStringObject().str;
    var digest_buf: [64]u8 = undefined;
    const len = computeDigest(alg, data, &digest_buf);
    return digestBase64(vm, digest_buf[0..len]);
}

pub fn builtinOpenSSLHMACDigest(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 3);
    const alg = try resolveDigestAlgorithmFromValue(vm, args[0]);
    const key = (try coerceToStringValueExact(vm, args[1])).toStringObject().str;
    const data = (try coerceToStringValueExact(vm, args[2])).toStringObject().str;
    var digest_buf: [64]u8 = undefined;
    const len = computeHmac(alg, key, data, &digest_buf);
    return binaryString(vm, digest_buf[0..len]);
}

pub fn builtinOpenSSLHMACHexdigest(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 3);
    const alg = try resolveDigestAlgorithmFromValue(vm, args[0]);
    const key = (try coerceToStringValueExact(vm, args[1])).toStringObject().str;
    const data = (try coerceToStringValueExact(vm, args[2])).toStringObject().str;
    var digest_buf: [64]u8 = undefined;
    const len = computeHmac(alg, key, data, &digest_buf);
    return digestHex(vm, digest_buf[0..len]);
}

pub fn builtinOpenSSLRandomBytes(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const length = try coerceToI64Exact(vm, args[0], "bignum too big to convert into `long`");
    if (length < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative string size (or size too big)", .{});
    }
    const len: usize = @intCast(length);
    const bytes = vm.allocator.alloc(u8, len) catch return error.Fatal;
    defer vm.allocator.free(bytes);
    var prng = std.Random.DefaultPrng.init(@intCast(std.Io.Clock.boot.now(vm.io).nanoseconds));
    prng.random().bytes(bytes);
    return binaryString(vm, bytes);
}

pub fn builtinOpenSSLKDFPbkdf2Hmac(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    var salt_value: ?Value = null;
    var iterations_value: ?Value = null;
    var length_value: ?Value = null;
    var hash_value: ?Value = null;
    try vm.consumeKeywordArgs(
        .{ "salt", "iterations", "length", "hash" },
        .{ &salt_value, &iterations_value, &length_value, &hash_value },
    );
    try vm.validateKeywordArgsConsumed();

    var missing: [4][]const u8 = undefined;
    var missing_len: usize = 0;
    if (salt_value == null) {
        missing[missing_len] = "salt";
        missing_len += 1;
    }
    if (iterations_value == null) {
        missing[missing_len] = "iterations";
        missing_len += 1;
    }
    if (length_value == null) {
        missing[missing_len] = "length";
        missing_len += 1;
    }
    if (hash_value == null) {
        missing[missing_len] = "hash";
        missing_len += 1;
    }
    if (missing_len != 0) return requiredKeywordMessage(vm, missing[0..missing_len]);

    const password = (try coerceToStringValueExact(vm, args[0])).toStringObject().str;
    const salt = (try coerceToStringValueExact(vm, salt_value.?)).toStringObject().str;
    const iterations = try coerceToI64Exact(vm, iterations_value.?, "bignum too big to convert into `long`");
    const length = try coerceToI64Exact(vm, length_value.?, "bignum too big to convert into `long`");
    const alg = try resolveDigestAlgorithmFromValue(vm, hash_value.?);

    if (length < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative string size (or size too big)", .{});
    }

    const len: usize = @intCast(length);
    if (len == 0) return binaryString(vm, "");

    const output = vm.allocator.alloc(u8, len) catch return error.Fatal;
    defer vm.allocator.free(output);

    const rounds: u32 = if (iterations < 0)
        0
    else
        std.math.cast(u32, iterations) orelse return vm.raiseExceptionFmt(try kdfErrorClass(vm), "PKCS5_PBKDF2_HMAC: invalid iteration count", .{});

    const result = switch (alg) {
        .md5 => std.crypto.pwhash.pbkdf2(output, password, salt, rounds, std.crypto.auth.hmac.HmacMd5),
        .sha1 => std.crypto.pwhash.pbkdf2(output, password, salt, rounds, std.crypto.auth.hmac.HmacSha1),
        .sha256 => std.crypto.pwhash.pbkdf2(output, password, salt, rounds, std.crypto.auth.hmac.sha2.HmacSha256),
        .sha384 => std.crypto.pwhash.pbkdf2(output, password, salt, rounds, std.crypto.auth.hmac.sha2.HmacSha384),
        .sha512 => std.crypto.pwhash.pbkdf2(output, password, salt, rounds, std.crypto.auth.hmac.sha2.HmacSha512),
    };
    result catch |err| switch (err) {
        error.WeakParameters => return vm.raiseExceptionFmt(try kdfErrorClass(vm), "PKCS5_PBKDF2_HMAC: invalid iteration count", .{}),
        error.OutputTooLong => return vm.raiseExceptionFmt(try kdfErrorClass(vm), "PKCS5_PBKDF2_HMAC", .{}),
    };

    return binaryString(vm, output);
}

fn scryptParam(vm: *VM, value_arg: Value) VMError!u64 {
    const n = try coerceToI64Exact(vm, value_arg, "bignum too big to convert into `long`");
    if (n < 0) {
        return vm.raiseExceptionFmt(try kdfErrorClass(vm), "EVP_PBE_scrypt", .{});
    }
    return @intCast(n);
}

pub fn builtinOpenSSLKDFScrypt(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);

    var salt_value: ?Value = null;
    var n_value: ?Value = null;
    var r_value: ?Value = null;
    var p_value: ?Value = null;
    var length_value: ?Value = null;
    try vm.consumeKeywordArgs(
        .{ "salt", "N", "r", "p", "length" },
        .{ &salt_value, &n_value, &r_value, &p_value, &length_value },
    );
    try vm.validateKeywordArgsConsumed();

    var missing: [5][]const u8 = undefined;
    var missing_len: usize = 0;
    if (salt_value == null) {
        missing[missing_len] = "salt";
        missing_len += 1;
    }
    if (n_value == null) {
        missing[missing_len] = "N";
        missing_len += 1;
    }
    if (r_value == null) {
        missing[missing_len] = "r";
        missing_len += 1;
    }
    if (p_value == null) {
        missing[missing_len] = "p";
        missing_len += 1;
    }
    if (length_value == null) {
        missing[missing_len] = "length";
        missing_len += 1;
    }
    if (missing_len != 0) return requiredKeywordMessage(vm, missing[0..missing_len]);

    const password = (try coerceToStringValueExact(vm, args[0])).toStringObject().str;
    const salt = (try coerceToStringValueExact(vm, salt_value.?)).toStringObject().str;
    const N = try scryptParam(vm, n_value.?);
    const r = try scryptParam(vm, r_value.?);
    const p = try scryptParam(vm, p_value.?);
    const length = try coerceToI64Exact(vm, length_value.?, "bignum too big to convert into `long`");

    if (length < 0) {
        return vm.raiseExceptionFmt(vm.argument_error_class, "negative string size (or size too big)", .{});
    }
    const len: usize = @intCast(length);
    if (len == 0) return binaryString(vm, "");

    if (N < 2 or (N & (N - 1)) != 0) {
        return vm.raiseExceptionFmt(try kdfErrorClass(vm), "EVP_PBE_scrypt", .{});
    }

    const output = vm.allocator.alloc(u8, len) catch return error.Fatal;
    defer vm.allocator.free(output);

    if (c.EVP_PBE_scrypt(
        password.ptr,
        password.len,
        salt.ptr,
        salt.len,
        N,
        r,
        p,
        0,
        output.ptr,
        output.len,
    ) != 1) {
        return vm.raiseExceptionFmt(try kdfErrorClass(vm), "EVP_PBE_scrypt", .{});
    }

    return binaryString(vm, output);
}

pub fn builtinOpenSSLSslSocketConnect(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 3);
    _ = args[1];
    return sslConnectImpl(vm, args[0], args[2].isTruthy());
}

pub fn builtinOpenSSLSslSocketReadNonblock(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 4);
    const state = try requireSslState(vm, args[0]);
    const length = try coerceToI64Exact(vm, args[1], "bignum too big to convert into `long`");
    if (length < 0) return vm.raiseExceptionFmt(vm.argument_error_class, "negative string size (or size too big)", .{});

    const len: usize = @intCast(length);
    if (len == 0) return binaryString(vm, "");

    const buffer = vm.allocator.alloc(u8, len) catch return error.Fatal;
    defer vm.allocator.free(buffer);

    var read_len: usize = 0;
    if (c.SSL_read_ex(state.ssl, buffer.ptr, len, &read_len) == 1) {
        return binaryString(vm, buffer[0..read_len]);
    }

    const exception = args[3].isTruthy();
    const err_code = c.SSL_get_error(state.ssl, 0);
    if (!exception) {
        if (err_code == c.SSL_ERROR_WANT_READ) return waitSymbol(vm, "wait_readable");
        if (err_code == c.SSL_ERROR_WANT_WRITE) return waitSymbol(vm, "wait_writable");
    }
    if (err_code == c.SSL_ERROR_ZERO_RETURN) return Value.nil();
    return raiseCurrentSslError(vm, "SSL_read failed");
}

pub fn builtinOpenSSLSslSocketWriteNonblock(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 3);
    const state = try requireSslState(vm, args[0]);
    const data = (try coerceToStringValueExact(vm, args[1])).toStringObject().str;

    var written_len: usize = 0;
    if (c.SSL_write_ex(state.ssl, data.ptr, data.len, &written_len) == 1) {
        return Value.integer(@intCast(written_len));
    }

    const exception = args[2].isTruthy();
    const err_code = c.SSL_get_error(state.ssl, 0);
    if (!exception) {
        if (err_code == c.SSL_ERROR_WANT_READ) return waitSymbol(vm, "wait_readable");
        if (err_code == c.SSL_ERROR_WANT_WRITE) return waitSymbol(vm, "wait_writable");
    }
    return raiseCurrentSslError(vm, "SSL_write failed");
}

pub fn builtinOpenSSLSslSocketClose(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    if (try sslStateFromReceiver(vm, args[0])) |state| {
        destroySslState(state);
        try setSslStateOnReceiver(vm, args[0], null);
    }
    return Value.nil();
}

pub fn builtinOpenSSLSslSocketEof(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const state = try requireSslState(vm, args[0]);
    if (c.SSL_pending(state.ssl) > 0) return Value.boolean(false);
    const io = try sslReceiverIo(vm, args[0]);
    return io_builtin.builtinIoEof(vm, Value.fromObject(&io.object), &.{}, null);
}

pub fn builtinOpenSSLSslSocketSslVersion(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const state = try requireSslState(vm, args[0]);
    const version_ptr = c.SSL_get_version(state.ssl);
    if (version_ptr == null) return Value.nil();
    return vm.newString(std.mem.sliceTo(version_ptr, 0), false);
}

pub fn builtinOpenSSLSslSocketCipher(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    const state = try requireSslState(vm, args[0]);
    const cipher = c.SSL_get_current_cipher(state.ssl) orelse return Value.nil();

    const name_ptr = c.SSL_CIPHER_get_name(cipher);
    const version_ptr = c.SSL_CIPHER_get_version(cipher);
    var alg_bits: c_int = 0;
    const bits = c.SSL_CIPHER_get_bits(cipher, &alg_bits);

    const result = try vm.createArray();
    result.elements.append(vm.gc_allocator, try vm.newString(std.mem.sliceTo(name_ptr, 0), false)) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, try vm.newString(std.mem.sliceTo(version_ptr, 0), false)) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, Value.integer(bits)) catch return error.Fatal;
    result.elements.append(vm.gc_allocator, Value.integer(alg_bits)) catch return error.Fatal;
    return Value.fromObject(&result.object);
}

pub fn builtinOpenSSLSslSocketPeerCertPem(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 1);
    _ = try requireSslState(vm, args[0]);
    return Value.nil();
}

pub fn builtinOpenSSLSslSocketPostConnectionCheck(vm: *VM, _: Value, args: []Value, _: ?Block) VMError!Value {
    try vm.requireArgCount(args, 2);
    const state = try requireSslState(vm, args[0]);
    _ = args[1];
    if (c.SSL_get_verify_result(state.ssl) != c.X509_V_OK) {
        return raiseCurrentSslError(vm, "SSL peer verification failed");
    }
    return args[0];
}
