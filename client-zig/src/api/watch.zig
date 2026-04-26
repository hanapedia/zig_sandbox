//! Kubernetes watch client implementation.
//! Provides both low-level WatchStream and high-level Watcher(T) APIs.

const std = @import("std");
const tls = @import("tls");
const Client = @import("../client/Client.zig").Client;
const ResourceInfo = @import("typed.zig").ResourceInfo;
const proto = @import("../proto/mod.zig");

// ============================================================================
// Public Types
// ============================================================================

/// Options for Watch operations.
pub const WatchOptions = struct {
    /// Start watching from this resource vsersion.
    /// If null, watches from current version.
    resourceVersion: ?[]const u8 = null,

    /// Server-side timeout in seconds.
    /// After this, server closes connection and you need to reconnect.
    timeoutSeconds: ?i64 = null,

    /// Lable selector to filger resources (e.g., "app=nginx").
    labelSelector: ?[]const u8 = null,

    /// Field selector to filger resources (e.g., "metadata.name=my-pod").
    fieldSelector: ?[]const u8 = null,

    /// Request bookmark events for efficient reconnection.
    allowWatchBookmarks: bool = true,
};

/// Event types from Kubernetes watch API.
pub const EventType = enum {
    ADDED,
    MODIFIED,
    DELETED,
    BOOKMARK,
    ERROR,

    /// Parse event type from string.
    pub fn fromString(s: []const u8) !EventType {
        if (std.mem.eql(u8, s, "ADDED")) return .ADDED;
        if (std.mem.eql(u8, s, "MODIFIED")) return .MODIFIED;
        if (std.mem.eql(u8, s, "DELETED")) return .DELETED;
        if (std.mem.eql(u8, s, "BOOKMARK")) return .BOOKMARK;
        if (std.mem.eql(u8, s, "ERROR")) return .ERROR;
    }
};

/// Typed watch event containing the parsed resource object.
pub fn WatchEvent(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Event Type
        event_type: EventType,

        /// Parsed resource object.
        /// For BOOKMARK events, only metadata.resourceVersion is populated.
        object: std.json.Parsed(T),

        /// Free the parsed object memory.
        pub fn deinit(self: *Self) void {
            self.object.deinit();
        }
    };
}

// ============================================================================
// WatchStream - Low-level API
// ============================================================================

/// Low-level watch stream that handles HTTP chunked encoding and line buffering.
///
/// This struct owns the TLS connection and provides methods to:
/// - Read raw bytes (for custom I/O control)
/// - Read complete JSON lines (handles chunked encoding internally)
/// - Read parsed WatchEvent objects
///
/// ## Example: Low-level usage
/// var stream = try WatchStream.init(client, namespace, info, .{});
/// defer stream.deinit();
///
/// while (try stream.readLine()) |line| {
///     defer stream.allocator.free(line);
///     std.debug.print("Event: {s}\n", .{line});
/// }
pub const WatchStream = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    io: std.Io,

    // Connection state
    tls_conn: tls.Connection,
    tcp_stream: std.Io.net.Stream,

    // HTTP parsing state
    header_parsed: bool,
    is_chunked: bool,

    // Chunked encoding state
    chunk_remaining: usize, // Bytes remaining in current chunk

    // Line buffering state
    line_buffer: std.ArrayList(u8),
    read_buffer: [4096]u8,
    read_buffer_pos: usize, // Current position in read_buffer
    read_buffer_len: usize, // Valid bytes in read_buffer

    // Stream state
    closed: bool,

    // ========================================================================
    // Public Methods
    // ========================================================================

    /// Initialize a watch stream by connecting to the API server.
    pub fn init(
        client: *Client,
        namespace: ?[]const u8,
        info: ResourceInfo,
        options: WatchOptions,
    ) !Self {
        // 1. Build the watch URL path
        const path = try buildWatchPath(client.allocator, namespace, info, options);
    }
};

fn buildWatchPath(
    allocator: std.mem.Allocator,
    namespace: ?[]const u8,
    info: ResourceInfo,
    options: WatchOptions,
) ![]const u8 {
    // Build base path (same as list path)
    var base_path: []const u8 = undefined;
    // namespaced resources
    if (info.namespaced) {
        if (namespace) |ns| {
            // core api group
            if (info.api_group.len == 0) {
                base_path = try std.fmt.allocPrint(allocator, "/api/{s}/namespaces/{s}/{s}", .{
                    info.api_version, ns, info.plural,
                });
            } else {
                base_path = try std.fmt.allocPrint(allocator, "/api/{s}/{s}/namespaces/{s}/{s}", .{
                    info.api_group, info.api_version, ns, info.plural,
                });
            }
        } else {
            // watch across namespaces
            if (info.api_group.len == 0) {
                base_path = try std.fmt.allocPrint(allocator, "/api/{s}/{s}", .{
                    info.api_version, info.plural,
                });
            } else {
                base_path = try std.fmt.allocPrint(allocator, "/api/{s}/{s}/{s}", .{
                    info.api_group, info.api_version, info.plural,
                });
            }
        }
    } else {
        // Cluster-scoped resource (no namespace)
        if (info.api_group.len == 0) {
            base_path = try std.fmt.allocPrint(allocator, "/api/{s}/{s}", .{
                info.api_version, info.plural,
            });
        } else {
            base_path = try std.fmt.allocPrint(allocator, "/apis/{s}/{s}/{s}", .{
                info.api_group, info.api_version, info.plural,
            });
        }
    }
    defer allocator.free(base_path);

    // Build query parameters
    var query_parts: std.ArrayList([]const u8) = .empty;
    defer {
        for (query_parts.items) |part| {
            if (!isStaticString(part)) {
                allocator.free(part);
            }
        }
        query_parts.deinit(allocator);
    }

    // Always add watch=true
    try query_parts.append(allocator, WatchQueryPart);

    if (options.allowWatchBookmarks) {
        try query_parts.append(allocator, AllowWatchBookmarksQueryPart);
    }

    if (options.resourceVersion) |rv| {
        const param = try std.fmt.allocPrint(allocator, "resourceVersion={s}", .{rv});
        try query_parts.append(allocator, param);
    }

    if (options.timeoutSeconds) |timeout| {
        const param = try std.fmt.allocPrint(allocator, "timeoutSeconds={s}", .{timeout});
        try query_parts.append(allocator, param);
    }

    if (options.labelSelector) |ls| {
        const param = try std.fmt.allocPrint(allocator, "labelSelector={s}", .{ls});
        try query_parts.append(allocator, param);
    }

    if (options.fieldSelector) |fs| {
        const param = try std.fmt.allocPrint(allocator, "fieldSelector={s}", .{fs});
        try query_parts.append(allocator, param);
    }

    // Join the query params
    const query = try std.mem.join(allocator, "&", query_parts.items);
    defer allocator.free(query);

    return std.fmt.allocPrint(allocator, "{s}?{s}", .{ base_path, query });
}

/// Check if a string is a static/comptime string (shouldn't be freed).
fn isStaticString(s: []const u8) bool {
    // Static strings we use
    return std.mem.eql(u8, s, WatchQueryPart) or
        std.mem.eql(u8, s, AllowWatchBookmarksQueryPart);
}

const WatchQueryPart = "watch=true";
const AllowWatchBookmarksQueryPart = "allowWatchBookmarks=true";
