//! Kubeconfig file parsing and authentication.
//! Supports loading configuration from ~/.kube/config.json or $KUBECONFIG.
//!
//! This module uses JSON parsing for kubeconfig files.
//! Convert your YAML kubeconfig to JSON using: yq -o=json ~/.kube/config > ~/.kube/config.json
const std = @import("std");

/// Resolved configuration ready for use by the HTTP client.
pub const Config = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    token: ?[]const u8,
    ca_cert: ?[]const u8,
    skip_tls_verify: bool,
    namespace: ?[]const u8,

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.host);
        if (self.token) |t| self.allocator.free(t);
        if (self.ca_cert) |c| self.allocator.free(c);
        if (self.namespace) |n| self.allocator.free(n);
    }
};

pub const Error = error{
    KubeconfigNotFound,
    InvalidKubeconfig,
    NoCurrentContext,
    ContextNotFound,
    ClusterNotFound,
    UserNotFound,
    NoHomeDirectory,
    InvalidBase64,
    UnsupportedAuthMethod,
    UnexpectedEndOfFile,
    FileNotFound,
    AccessDenied,
    FileTooBig,
    InputOutput,
    IsDir,
    NoSpaceLeft,
    OutOfMemory,
    JsonParseError,
};

/// JSON structure for kubeconfig file
const KubeconfigJson = struct {
    @"current-context": ?[]const u8 = null,
    contexts: ?[]const ContextEntry = null,
    clusters: ?[]const ClusterEntry = null,
    users: ?[]const UserEntry = null,

    const ContextEntry = struct {
        name: ?[]const u8 = null,
        context: ?ContextData = null,

        const ContextData = struct {
            cluster: ?[]const u8 = null,
            user: ?[]const u8 = null,
            namespace: ?[]const u8 = null,
        };
    };

    const ClusterEntry = struct {
        name: ?[]const u8 = null,
        cluster: ?ClusterData = null,

        const ClusterData = struct {
            server: ?[]const u8 = null,
            @"certificate-authority-data": ?[]const u8 = null,
            @"certificate-authority": ?[]const u8 = null,
            @"insecure-skip-tls-verify": ?bool = null,
        };
    };

    const UserEntry = struct {
        name: ?[]const u8 = null,
        user: ?UserData = null,

        const UserData = struct {
            token: ?[]const u8 = null,
            @"client-certificate-data": ?[]const u8 = null,
            @"client-key-data": ?[]const u8 = null,
        };
    };
};

/// Load kubeconfig from the given path or default location.
/// If path is null, tries $KUBECONFIG, then ~/.kube/config.json.
pub fn load(io: std.Io, environ_map: *std.process.Environ.Map, allocator: std.mem.Allocator, path: ?[]const u8) !Config {
    const config_path = if (path) |p| p else try getDefaultPath(environ_map, allocator);
    const should_free_path = path == null;
    defer if (should_free_path) allocator.free(config_path);

    // Read kubeconfig file
    const content = readFile(io, allocator, config_path) catch |err| {
        return switch (err) {
            error.FileNotFound => error.KubeconfigNotFound,
            else => err,
        };
    };
    defer allocator.free(content);

    // Parse the kubeconfig JSON
    return parseKubeconfig(io, allocator, content);
}

fn parseKubeconfig(io: std.Io, allocator: std.mem.Allocator, content: []const u8) !Config {
    const parsed = std.json.parseFromSlice(KubeconfigJson, allocator, content, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch return error.JsonParseError;
    defer parsed.deinit();

    const kubeconfig = parsed.value;

    // Get current context
    const current_context = kubeconfig.@"current-context" orelse return error.NoCurrentContext;

    // Find the matching context
    var context_cluster: ?[]const u8 = null;
    var context_user: ?[]const u8 = null;
    var context_namespace: ?[]const u8 = null;

    if (kubeconfig.contexts) |contexts| {
        for (contexts) |ctx| {
            if (ctx.name) |name| {
                if (std.mem.eql(u8, name, current_context)) {
                    if (ctx.context) |context_data| {
                        context_cluster = context_data.cluster;
                        context_user = context_data.user;
                        context_namespace = context_data.namespace;
                    }
                    break;
                }
            }
        }
    }

    if (context_cluster == null) return error.ContextNotFound;

    // Find the matching cluster
    var server: ?[]const u8 = null;
    var ca_data: ?[]const u8 = null;
    var ca_file: ?[]const u8 = null;
    var skip_tls: bool = false;

    if (kubeconfig.clusters) |clusters| {
        for (clusters) |cluster_entry| {
            if (cluster_entry.name) |name| {
                if (std.mem.eql(u8, name, context_cluster.?)) {
                    if (cluster_entry.cluster) |cluster_data| {
                        server = cluster_data.server;
                        ca_data = cluster_data.@"certificate-authority-data";
                        ca_file = cluster_data.@"certificate-authority";
                        skip_tls = cluster_data.@"insecure-skip-tls-verify" orelse false;
                    }
                    break;
                }
            }
        }
    }

    if (server == null) return error.ClusterNotFound;

    // Find the matching user
    var token: ?[]const u8 = null;

    if (context_user) |user_name| {
        if (kubeconfig.users) |users| {
            for (users) |user_entry| {
                if (user_entry.name) |name| {
                    if (std.mem.eql(u8, name, user_name)) {
                        if (user_entry.user) |user_data| {
                            token = user_data.token;
                        }
                        break;
                    }
                }
            }
        }
    }

    // Decode CA certificate if provided as base64
    var ca_cert: ?[]const u8 = null;
    if (ca_data) |data| {
        ca_cert = decodeBase64(allocator, data) catch null;
    } else if (ca_file) |file_path| {
        ca_cert = readFile(io, allocator, file_path) catch null;
    }

    return .{
        .allocator = allocator,
        .host = try allocator.dupe(u8, server.?),
        .token = if (token) |t| try allocator.dupe(u8, t) else null,
        .ca_cert = ca_cert,
        .skip_tls_verify = skip_tls,
        .namespace = if (context_namespace) |n| try allocator.dupe(u8, n) else null,
    };
}

fn getDefaultPath(environ_map: *std.process.Environ.Map, allocator: std.mem.Allocator) ![]const u8 {
    // Check KUBECONFIG environment variable first
    if (environ_map.get("KUBECONFIG")) |kc| {
        return try allocator.dupe(u8, kc);
    }

    // Fall back to ~/.kube/config.json
    const home = environ_map.get("HOME") orelse return error.NoHomeDirectory;
    return try std.fmt.allocPrint(allocator, "{s}/.kube/config.json", .{home});
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

fn decodeBase64(allocator: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    const decoder = std.base64.standard.Decoder;
    const size = decoder.calcSizeForSlice(encoded) catch return error.InvalidBase64;
    const buffer = try allocator.alloc(u8, size);
    errdefer allocator.free(buffer);

    decoder.decode(buffer, encoded) catch return error.InvalidBase64;

    // Check if the decoded data is PEM-encoded (starts with "-----BEGIN")
    // If so, extract and decode the inner base64 content to get DER
    if (std.mem.startsWith(u8, buffer, "-----BEGIN")) {
        defer allocator.free(buffer);
        return decodePemToDer(allocator, buffer);
    }

    return buffer;
}

/// Decode a PEM certificate to DER format
fn decodePemToDer(allocator: std.mem.Allocator, pem: []const u8) ![]const u8 {
    const begin_marker = "-----BEGIN CERTIFICATE-----";
    const end_marker = "-----END CERTIFICATE-----";

    const begin_pos = std.mem.indexOf(u8, pem, begin_marker) orelse return error.InvalidBase64;
    const cert_start = begin_pos + begin_marker.len;
    const end_pos = std.mem.indexOfPos(u8, pem, cert_start, end_marker) orelse return error.InvalidBase64;

    // Extract the base64 content between markers, stripping whitespace
    const base64_content = std.mem.trim(u8, pem[cert_start..end_pos], " \t\r\n");

    // Count actual base64 characters (skip newlines)
    var base64_len: usize = 0;
    for (base64_content) |c| {
        if (c != '\n' and c != '\r' and c != ' ') {
            base64_len += 1;
        }
    }

    // Decode ignoring whitespace
    const decoder = std.base64.standard.Decoder;
    const der_size = try decoder.calcSizeUpperBound(base64_len);
    const der_buffer = try allocator.alloc(u8, der_size);
    errdefer allocator.free(der_buffer);

    // Manual decode skipping whitespace
    var clean_base64 = try allocator.alloc(u8, base64_len);
    defer allocator.free(clean_base64);

    var idx: usize = 0;
    for (base64_content) |c| {
        if (c != '\n' and c != '\r' and c != ' ') {
            clean_base64[idx] = c;
            idx += 1;
        }
    }

    const decoded_len = decoder.calcSizeForSlice(clean_base64) catch return error.InvalidBase64;
    const result = try allocator.realloc(der_buffer, decoded_len);
    decoder.decode(result, clean_base64) catch return error.InvalidBase64;

    return result;
}

test "parseKubeconfig basic" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const content =
        \\{
        \\  "current-context": "test-context",
        \\  "contexts": [
        \\    {
        \\      "name": "test-context",
        \\      "context": {
        \\        "cluster": "test-cluster",
        \\        "user": "test-user",
        \\        "namespace": "test-ns"
        \\      }
        \\    }
        \\  ],
        \\  "clusters": [
        \\    {
        \\      "name": "test-cluster",
        \\      "cluster": {
        \\        "server": "https://localhost:6443",
        \\        "insecure-skip-tls-verify": true
        \\      }
        \\    }
        \\  ],
        \\  "users": [
        \\    {
        \\      "name": "test-user",
        \\      "user": {
        \\        "token": "my-secret-token"
        \\      }
        \\    }
        \\  ]
        \\}
    ;

    var config = try parseKubeconfig(io, allocator, content);
    defer config.deinit();

    try std.testing.expectEqualStrings("https://localhost:6443", config.host);
    try std.testing.expectEqualStrings("my-secret-token", config.token.?);
    try std.testing.expectEqualStrings("test-ns", config.namespace.?);
    try std.testing.expect(config.skip_tls_verify);
}

test "parseKubeconfig no token" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const content =
        \\{
        \\  "current-context": "test-context",
        \\  "contexts": [
        \\    {
        \\      "name": "test-context",
        \\      "context": {
        \\        "cluster": "test-cluster",
        \\        "user": "test-user"
        \\      }
        \\    }
        \\  ],
        \\  "clusters": [
        \\    {
        \\      "name": "test-cluster",
        \\      "cluster": {
        \\        "server": "https://127.0.0.1:8443"
        \\      }
        \\    }
        \\  ],
        \\  "users": [
        \\    {
        \\      "name": "test-user",
        \\      "user": {}
        \\    }
        \\  ]
        \\}
    ;

    var config = try parseKubeconfig(io, allocator, content);
    defer config.deinit();

    try std.testing.expectEqualStrings("https://127.0.0.1:8443", config.host);
    try std.testing.expect(config.token == null);
    try std.testing.expect(config.namespace == null);
    try std.testing.expect(!config.skip_tls_verify);
}

test "getDefaultPath with HOME set" {
    const allocator = std.testing.allocator;

    // Create a mock environment map with HOME set
    var map = std.process.Environ.Map.init(allocator);
    defer map.deinit();
    try map.put("HOME", "/home/testuser");

    const path = try getDefaultPath(&map, allocator);
    defer allocator.free(path);

    try std.testing.expectEqualStrings("/home/testuser/.kube/config.json", path);
}

test "getDefaultPath with KUBECONFIG set" {
    const allocator = std.testing.allocator;

    var map = std.process.Environ.Map.init(allocator);
    defer map.deinit();
    try map.put("HOME", "/home/testuser");
    try map.put("KUBECONFIG", "/custom/path/kubeconfig.json");

    const path = try getDefaultPath(&map, allocator);
    defer allocator.free(path);

    try std.testing.expectEqualStrings("/custom/path/kubeconfig.json", path);
}
