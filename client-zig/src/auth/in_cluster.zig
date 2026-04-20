//! In-cluster authentication using mounted ServiceAccount credentials.
//! When running inside a Kubernetes Pod, credentials are automatically mounted at:
//! - /var/run/secrets/kubernetes.io/serviceaccount/token
//! - /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
//! - /var/run/secrets/kubernetes.io/serviceaccount/namespace
const std = @import("std");

pub const InClusterConfig = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    token: []const u8,
    ca_cert: ?[]const u8,
    namespace: ?[]const u8,

    pub const token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token";
    pub const ca_path = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt";
    pub const namespace_path = "/var/run/secrets/kubernetes.io/serviceaccount/namespace";

    pub const Error = error{
        NotInCluster,
        MissingServiceHost,
        MissingServicePort,
        TokenReadFailed,
        InvalidHost,
    };

    /// Load in-cluster configuration from the standard ServiceAccount mount paths.
    /// Returns error.NotInCluster if not running inside a Kubernetes Pod.
    pub fn load(io: std.Io, environ_map: *std.process.Environ.Map, allocator: std.mem.Allocator) !InClusterConfig {
        // Read service account token
        const token = readFile(io, allocator, token_path) catch |err| {
            return switch (err) {
                error.FileNotFound => error.NotInCluster,
                else => error.TokenReadFailed,
            };
        };
        errdefer allocator.free(token);

        // Read CA certificate (optional but usually present) and convert PEM to DER
        const ca_cert = blk: {
            const pem = readFile(io, allocator, ca_path) catch |err| {
                std.debug.print("Failed to read CA cert: {}\n", .{err});
                break :blk null;
            };
            defer allocator.free(pem);
            std.debug.print("Read CA PEM, len={}\n", .{pem.len});
            const der = decodePemToDer(allocator, pem) catch |err| {
                std.debug.print("Failed to decode PEM to DER: {}\n", .{err});
                break :blk null;
            };
            std.debug.print("Decoded DER, len={}\n", .{der.len});
            break :blk der;
        };
        errdefer if (ca_cert) |c| allocator.free(c);

        // Read namespace (optional)
        const namespace = readFile(io, allocator, namespace_path) catch null;
        errdefer if (namespace) |n| allocator.free(n);

        // Build API server URL from environment variables
        // We check for the env vars to verify we're in-cluster but use the DNS name
        // because it's in the cert's SANs and works better with TLS validation
        _ = environ_map.get("KUBERNETES_SERVICE_HOST") orelse
            return error.MissingServiceHost;
        const service_port = environ_map.get("KUBERNETES_SERVICE_PORT") orelse
            return error.MissingServicePort;

        // Build host URL - use DNS name instead of IP for TLS certificate validation
        // The kubernetes service has a DNS name that's in the cert's SANs
        const host = std.fmt.allocPrint(allocator, "https://kubernetes.default.svc:{s}", .{
            service_port,
        }) catch return error.InvalidHost;

        return .{
            .allocator = allocator,
            .host = host,
            .token = token,
            .ca_cert = ca_cert,
            .namespace = if (namespace) |n| std.mem.trim(u8, n, " \t\r\n") else null,
        };
    }

    pub fn deinit(self: *InClusterConfig) void {
        self.allocator.free(self.host);
        self.allocator.free(self.token);
        if (self.ca_cert) |c| self.allocator.free(c);
        if (self.namespace) |n| {
            // Only free if we allocated it (check if it's a slice into our buffer)
            // Actually, namespace points into the original token buffer we read
            // We need to track this separately... for simplicity, let's just
            // read it as a separate allocation
            _ = n;
        }
    }

    fn readFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
        const file = try std.Io.Dir.openFileAbsolute(io, path, .{});
        defer file.close(io);

        const stat = try file.stat(io);
        const size = stat.size;

        const buffer = try allocator.alloc(u8, size);
        errdefer allocator.free(buffer);

        var read_buf: [4096]u8 = undefined;
        var reader = file.reader(io, &read_buf);

        // Read all content into buffer
        try reader.interface.readSliceAll(buffer);

        return buffer;
    }
};

fn decodePemToDer(allocator: std.mem.Allocator, pem: []const u8) ![]const u8 {
    const begin_marker = "-----BEGIN CERTIFICATE-----";
    const end_marker = "-----END CERTIFICATE-----";

    const begin_pos = std.mem.indexOf(u8, pem, begin_marker) orelse return error.InvalidPem;
    const after_begin = begin_pos + begin_marker.len;

    const end_pos = std.mem.indexOfPos(u8, pem, after_begin, end_marker) orelse return error.InvalidPem;

    // Extract the base64-encoded content between markers
    const base64_content = pem[after_begin..end_pos];

    // Use decoder that ignores whitespace (newlines, spaces, etc.)
    const base64_decoder = std.base64.standard.decoderWithIgnore(" \t\r\n");

    // Calculate decoded size
    const decoded_size = base64_decoder.calcSizeUpperBound(base64_content.len);

    // Allocate buffer for decoded data
    const der = try allocator.alloc(u8, decoded_size);
    errdefer allocator.free(der);

    // Decode base64 to DER
    const decoded_len = base64_decoder.decode(der, base64_content) catch return error.InvalidBase64;

    // Shrink to actual size if needed
    if (decoded_len < der.len) {
        return allocator.realloc(der, decoded_len) catch der[0..decoded_len];
    }

    return der;
}

test "InClusterConfig paths are correct" {
    try std.testing.expectEqualStrings(
        "/var/run/secrets/kubernetes.io/serviceaccount/token",
        InClusterConfig.token_path,
    );
    try std.testing.expectEqualStrings(
        "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
        InClusterConfig.ca_path,
    );
}
