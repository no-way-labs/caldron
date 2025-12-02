const std = @import("std");

// Simple XChaCha20-Poly1305 encryption for file transfers
// Using a password-derived key

pub const EncryptedData = struct {
    nonce: [24]u8,
    ciphertext: []u8,
    tag: [16]u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *EncryptedData) void {
        self.allocator.free(self.ciphertext);
    }
};

pub fn deriveKey(password: []const u8) [32]u8 {
    var key: [32]u8 = undefined;

    // Use Argon2id for secure password-based key derivation
    // Salt is derived from a fixed context string - in a multi-user system,
    // this should be random per-user and stored. For peer-to-peer transfers
    // where both parties need the same key from the same password, we use
    // a deterministic salt.
    const salt = "mitt-v1-salt-24!"; // Exactly 16 bytes
    var salt_bytes: [16]u8 = undefined;
    @memcpy(&salt_bytes, salt);

    // Argon2id parameters (balanced security/performance)
    // - 3 iterations (recommended minimum)
    // - 64 MiB memory (good balance for client devices)
    // - 4 parallel threads
    std.crypto.pwhash.argon2.kdf(
        std.heap.page_allocator,
        &key,
        password,
        &salt_bytes,
        .{
            .t = 3,  // time cost (iterations)
            .m = 65536,  // memory cost in KiB (64 MiB)
            .p = 4,  // parallelism
        },
        .argon2id,
    ) catch |err| {
        // Fallback to deterministic key on error (should never happen)
        std.debug.print("Warning: Argon2 KDF failed: {}, using SHA-256 fallback\n", .{err});
        std.crypto.hash.sha2.Sha256.hash(password, &key, .{});
    };

    return key;
}

pub fn generatePassword(allocator: std.mem.Allocator) ![]const u8 {
    const id_module = @import("id.zig");
    return try id_module.generate(allocator);
}

pub fn encrypt(allocator: std.mem.Allocator, plaintext: []const u8, key: [32]u8) !EncryptedData {
    var nonce: [24]u8 = undefined;
    std.crypto.random.bytes(&nonce);

    const ciphertext = try allocator.alloc(u8, plaintext.len);
    errdefer allocator.free(ciphertext);

    var tag: [16]u8 = undefined;

    std.crypto.aead.chacha_poly.XChaCha20Poly1305.encrypt(
        ciphertext,
        &tag,
        plaintext,
        "",
        nonce,
        key,
    );

    return EncryptedData{
        .nonce = nonce,
        .ciphertext = ciphertext,
        .tag = tag,
        .allocator = allocator,
    };
}

pub fn decrypt(allocator: std.mem.Allocator, encrypted: EncryptedData, key: [32]u8) ![]u8 {
    const plaintext = try allocator.alloc(u8, encrypted.ciphertext.len);
    errdefer allocator.free(plaintext);

    std.crypto.aead.chacha_poly.XChaCha20Poly1305.decrypt(
        plaintext,
        encrypted.ciphertext,
        encrypted.tag,
        "",
        encrypted.nonce,
        key,
    ) catch {
        return error.DecryptionFailed;
    };

    return plaintext;
}

test "encrypt and decrypt" {
    const allocator = std.testing.allocator;

    const password = "test-password-123";
    const key = deriveKey(password);

    const plaintext = "Hello, World!";

    var encrypted = try encrypt(allocator, plaintext, key);
    defer encrypted.deinit();

    const decrypted = try decrypt(allocator, encrypted, key);
    defer allocator.free(decrypted);

    try std.testing.expectEqualStrings(plaintext, decrypted);
}
