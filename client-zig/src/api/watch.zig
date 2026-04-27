//! Kubernetes watch client implementation.
//! Provides both low-level WatchStream and high-level Watcher(T) APIs.

const std = @import("std");
const tls = @import("tls");
const Client = @import("../client/Client.zig").Client;
const ResourceInfo = @import("typed.zig").ResourceInfo;
const proto = @import("../proto/mod.zig");

// ============================================================================
// Constants
// ============================================================================

const WatchQueryPart = "watch=true";
const AllowWatchBookmarksQueryPart = "allowWatchBookmarks=true";

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

        const RawEvent = struct {
            type: []const u8,
            object: T,
        };

        event_type: EventType,
        _parsed: std.json.Parsed(RawEvent),

        /// Parsed resource object.
        /// For BOOKMARK events, only metadata.resourceVersion is populated.
        pub fn object(self: Self) T {
            return self._parsed.value.object;
        }

        /// Free the parsed object memory.
        pub fn deinit(self: *Self) void {
            self._parsed.deinit();
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
        defer client.allocator.free(path);

        // 2. Establish TCP connection
        const hostname = std.Io.net.HostName.init(client.host) catch
            return error.ConnectionFailed;

        const tcp_stream = hostname.connect(client.io, client.port, .{ .mode = .stream }) catch
            return error.ConnectionFailed;
        errdefer tcp_stream.close(client.io);

        // 3. Upgrade to TLS
        const rng_impl: std.Random.IoSource = .{ .io = client.io };
        const rng = rng_impl.interface();
        const now = std.Io.Clock.real.now(client.io);

        var tls_conn = tls.clientFromStream(client.io, tcp_stream, .{
            .rng = rng,
            .now = now,
            .host = client.host,
            .root_ca = client.ca_bundle,
        }) catch return error.TlsError;
        errdefer tls_conn.close() catch {};

        // 4. Send HTTP GET request
        try sendWatchRequest(&tls_conn, client, path);

        return Self{
            .allocator = client.allocator,
            .io = client.io,
            .tls_conn = tls_conn,
            .tcp_stream = tcp_stream,
            .headers_parsed = false,
            .is_chunked = false,
            .chunk_remaining = 0,
            .line_buffer = .empty,
            .read_buffer = undefined,
            .read_buffer_pos = 0,
            .read_buffer_len = 0,
            .closed = false,
        };
    }

    /// Clean up resources and close connection.
    pub fn deinit(self: *Self) void {
        self.line_buffer.deinit(self.allocator);
        self.tls_conn.close();
        self.tcp_stream.close(self.io);
        self.closed = true;
    }

    /// Check if the stream has been closed.
    pub fn isClosed(self: *Self) bool {
        return self.closed;
    }

    /// close the watch stream.
    pub fn close(self: *Self) void {
        if (!self.closed) {
            self.tls_conn.close() catch {};
            self.tcp_stream.close(self.io);
            self.closed = true;
        }
    }

    /// Read Raw bytes from the TLS connection.
    /// This bypasses chunked encoding - use readLine() for normal usage.
    pub fn read(self: *Self, buffer: []u8) !usize {
        // return if the connection is already closed
        if (self.closed) return 0;

        const n = self.tls_conn.read(buffer) catch |err| {
            if (err == error.EndOfStream) {
                self.closed = true;
                return 0;
            }
            return err;
        };

        if (n == 0) self.closed = true;
        return n;
    }

    /// Read the next complete JSON line from the stream.
    /// Headless HTTP chunked encoding and partial line buffering.
    /// Returns null when stream ends.
    /// Caller owns returned slice and must deallocate with self.allocator.
    pub fn readLine(self: *Self) !?[]u8 {
        if (self.closed) return null;

        // Parse HTTP headers on first call
        if (!self.header_parsed) {
            try self.parseHTTPHeaders();
        }

        // Read until we have a complete line
        while (true) {
            // Check if we have a complete line in buffer
            if (try self.findLineInBuffer()) |line| {
                return line;
            }

            // We need more data - read from connection
            const bytes_read = try self.readMoreData();
            if (bytes_read == 0) {
                // bytes_read = 0 -> EOF
                // Connection closed
                self.closed = true;

                // Return any remaining buffered data as final line
                if (self.line_buffer.items.len > 0) {
                    const final_line = try self.allocator.dupe(u8, self.line_buffer.items);
                    self.line_buffer.clearRetainingCapacity();
                    return final_line;
                }
                return null;
            }
        }
    }

    // ========================================================================
    // Private Methods
    // ========================================================================

    /// Parse HTTP response headers, extract status and chunked flag.
    fn parseHTTPHeaders(self: *Self) !void {
        // Read until we find "\r\n\r\n" (end of headers)
        while (true) {
            // Try to find headers end in current buffer
            const headers_end = std.mem.indexOf(u8, self.line_buffer.items, "\r\n\r\n");
            if (headers_end) |end_idx| {
                const headers = self.line_buffer.items[0..end_idx];

                // Parse status line: "HTTP/1.1 200 OK"
                const status_line_end = std.mem.indexOf(u8, headers, "\r\n") orelse
                    return error.InvalidResponse;
                const status_line = headers[0..status_line_end];

                var parts = std.mem.tokenizeScalar(u8, status_line, ' ');
                _ = parts.next() orelse return error.InvalidResponse;
                const status_str = parts.next() orelse return error.InvalidResponse;
                const status_code = std.fmt.parseInt(u16, status_str, 10) catch
                    return error.InvalidResponse;

                if (status_code != 200) {
                    std.debug.print("Watch request failed with status: {d}\n", .{status_code});
                    return error.WatchFailed;
                }

                // Check for chunked encoding (case-insensitive search)
                // Look for "Transfer-Encoding" header containing "chunked"
                self.is_chunked = std.mem.indexOf(u8, headers, "chunked") != null;

                // Remove headers from buffer, keep body data
                const body_start = end_idx + 4;
                const remaining = self.line_buffer.items[body_start..];
                @memmove(self.line_buffer.items[0..remaining.len], remaining);
                self.line_buffer.items.len = remaining.len;

                self.header_parsed = true;
                return;
            }

            // Need more data - read from TLS
            const n = self.tls_conn.read(&self.read_buffer) catch |err| {
                if (err == error.EndOfStream) return error.UnexpectedEndOfStream;
                return err;
            };
            if (n == 0) return error.UnexpectedEndOfStream;

            try self.line_buffer.appendSlice(self.allocator, self.read_buffer[0..n]);
        }
    }

    /// Find a complete line in the buffer, extract and return it.
    fn findLineInBuffer(self: *Self) !?[]const u8 {
        const newline_idx = std.mem.indexOfScalar(u8, self.line_buffer.items, '\n') orelse
            return null;

        // Extract line (trim trailing \r if present)
        var line_end = newline_idx;
        if (line_end > 0 and self.line_buffer.items[line_end - 1] == '\r') {
            line_end -= 1;
        }

        const line = try self.allocator.dupe(u8, self.line_buffer.items[0..line_end]);

        // Remove line from buffer (including \n)
        const remaining_start = newline_idx + 1;
        const remaining = self.line_buffer.items[remaining_start..];
        @memmove(self.line_buffer.items[0..remaining.len], remaining);
        self.line_buffer.items.len = remaining.len;

        return line;
    }

    /// Read more data from connection into line buffer.
    /// Headless chunked encoding if enabled.
    fn readMoreData(self: *Self) !usize {
        if (self.is_chunked) {
            return self.readChunkedData();
        } else {
            return self.readRawData();
        }
    }

    /// Read raw (non-chunked) data.
    fn readRawData(self: *Self) !usize {
        const n = self.tls_conn.read(&self.read_buffer) catch |err| {
            if (err == error.EndOfStream) return 0;
            return err;
        };
        if (n == 0) return 0;

        try self.line_buffer.appendSlice(self.allocator, self.read_buffer[0..n]);
        return n;
    }

    /// Read chunked-encoded data.
    ///
    /// Format:
    /// ```
    /// <size-in-hex>\r\n
    /// <data>\r\n
    /// <size-in-hex>\r\n
    /// <data>\r\n
    /// 0\r\n
    /// \r\n
    /// ```
    fn readChunkedData(self: *Self) !usize {
        // If no bytes remaining in current chunk, read next chunk size
        if (self.chunk_remaining == 0) {
            try self.readChunkSize();

            // Zero-size chunk means end of stream
            if (self.chunk_remaining == 0) {
                return 0;
            }
        }

        // Read from current chunk (don't read more than chunk_remaining)
        const to_read = @min(self.chunk_remaining, self.read_buffer.len);
        const n = self.tls_conn.read(self.read_buffer[0..to_read]) catch |err| {
            if (err == error.EndOfStream) return 0;
            return err;
        };
        if (n == 0) return 0;

        try self.line_buffer.appendSlice(self.allocator, self.read_buffer[0..n]);
        self.chunk_remaining -= n;

        // If chunk finished, consume trailing CRLF
        if (self.chunk_remaining == 0) {
            try self.consumeCRLF();
        }

        return n;
    }

    /// Read and parse chunk size line (e.g., "4a\r\n" -> 74).
    fn readChunkSize(self: *Self) !void {
        // Accumulate bytes until we find CRLF
        var size_buf: [32]u8 = undefined;
        var size_len: usize = 0;

        while (size_len < size_buf.len) {
            var byte: [1]u8 = undefined;
            const n = self.tls_conn.read(&byte) catch |err| {
                if (err == error.EndOfStream) return error.UnexpectedEndOfStream;
                return err;
            };
            if (n == 0) return error.UnexpectedEndOfStream;

            if (byte[0] == '\r') {
                // Next byte should be \n
                const n2 = self.tls_conn.read(&byte) catch |err| {
                    if (err == error.EndOfStream) return error.UnexpectedEndOfStream;
                    return err;
                };
                if (n2 == 0 or byte[0] != '\n') {
                    return error.InvalidChunkedEncoding;
                }
                break;
            }

            size_buf[size_len] = byte[0];
            size_len += 1;
        }

        // parse hex chunk size
        self.chunk_remaining = std.fmt.parseInt(usize, size_buf[0..size_len], 16) catch
            return error.InvalidChunkedEncoding;
    }

    /// Consume the trailing CRCL after chunk data.
    fn consumeCRLF(self: *Self) !void {
        var crlf: [2]u8 = undefined;
        var read_total: usize = 0;

        while (read_total < 2) {
            const n = self.tls_conn.read(crlf[read_total..]) catch |err| {
                if (err == error.EndOfStream) return error.InvalidChunkedEncoding;
                return err;
            };
            if (n == 0) return error.InvalidChunkedEncoding;
            read_total += n;
        }

        if (crlf[0] != '\r' or crlf[1] != '\n') {
            return error.InvalidChunkedEncoding;
        }
    }
};

// ============================================================================
// Watcher(T) - High-level API
// ============================================================================

/// High-level typed watcher that yields WatchEvent(T) objects.
///
/// ## Example: High-level usage
/// var watcher = try Watcher(Pod).init(client, "default", info, .{});
/// defer watcher.deinit();
///
/// while (try watcher.next()) |*event| {
///     defer event.deinit();
///     std.debug.print("[{s}] {s}\n", .{
///         @tagName(event.event_type),
///         event.object.value.metadata.?.name orelse "?",
///     });
/// }
pub fn Watcher(comptime T: type) type {
    return struct {
        const Self = @This();

        stream: WatchStream,
        allocator: std.mem.Allocator,

        /// Initialize a watcher for the given resource type.
        pub fn init(
            client: *Client,
            namespace: ?[]const u8,
            info: ResourceInfo,
            options: WatchOptions,
        ) !Self {
            return Self{
                .stream = try WatchStream.init(client, namespace, info, options),
                .allocator = client.allocator,
            };
        }

        /// Get the next watch event.
        /// Returns null when the stream ends.
        /// Caller must call event.deinit() when done.
        pub fn next(self: *Self) !?WatchEvent(T) {
            // Read the next JSON line.
            const line = try self.stream.readLine() orelse return null;
            defer self.allocator.free(line);

            // Parse directly into a struct with the typed object field
            const parsed = std.json.parseFromSlice(
                WatchEvent(T).RawEvent,
                self.allocator,
                line,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            ) catch return error.JsonParseError;

            // Convert type string to enum
            const event_type = EventType.fromString(parsed.value.type) orelse {
                parsed.deinit();
                return error.UnknownEventType;
            };

            return WatchEvent(T){
                .event_type = event_type,
                ._parsed = parsed,
            };
        }

        /// Get access to the underlying WatchStream for low-level control.
        pub fn getStream(self: *Self) *WatchStream {
            return &self.stream;
        }

        /// Check if the watche is closed.
        pub fn isClosed(self: *Self) bool {
            return &self.stream.isClosed();
        }

        /// Close the watcher.
        pub fn close(self: *Self) void {
            return &self.stream.close();
        }

        /// Clean up resources.
        pub fn deinit(self: *Self) void {
            self.stream.deinit();
        }
    };
}

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

/// Send the HTTP GET request for watching
fn sendWatchRequest(
    tls_conn: *tls.Connection,
    client: *Client,
    path: []const u8,
) !void {
    // Build Authorization header
    const auth_header = if (client.token) |token|
        try std.fmt.allocPrint(client.allocator, "Authorization: Bearer {s}\r\n", .{token})
    else
        try client.allocator.dupe(u8, "");
    defer client.allocator.free(auth_header);

    // Build full HTTP request
    const request = try std.fmt.allocPrint(
        client.allocator,
        "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "{s}" ++
            "Accept: application/json\r\n" ++
            "Connection: keep-alive\r\n" ++
            "\r\n",
        .{ path, client.host, auth_header },
    );
    defer client.allocator.free(request);

    // Send request
    _ = tls_conn.write(request) catch return Client.Error.RequestFailed;
}

// ============================================================================
// Tests
// ============================================================================

test "buildWatchPath basic" {
    const allocator = std.testing.allocator;

    const path = try buildWatchPath(allocator, "default", .{
        .api_version = "v1",
        .api_group = "",
        .plural = "pods",
        .namespaced = true,
    }, .{});
    defer allocator.free(path);

    try std.testing.expect(std.mem.indexOf(u8, path, "/api/v1/namespaces/default/pods") != null);
    try std.testing.expect(std.mem.indexOf(u8, path, "watch=true") != null);
}

test "buildWatchPath with options" {
    const allocator = std.testing.allocator;

    const path = try buildWatchPath(allocator, "kube-system", .{
        .api_version = "v1",
        .api_group = "apps",
        .plural = "deployments",
        .namespaced = true,
    }, .{
        .resourceVersion = "12345",
        .labelSelector = "app=nginx",
        .timeoutSeconds = 300,
    });
    defer allocator.free(path);

    try std.testing.expect(std.mem.indexOf(u8, path, "resourceVersion=12345") != null);
    try std.testing.expect(std.mem.indexOf(u8, path, "labelSelector=app=nginx") != null);
    try std.testing.expect(std.mem.indexOf(u8, path, "timeoutSeconds=300") != null);
}

test "buildWatchPath cluster-scoped" {
    const allocator = std.testing.allocator;

    const path = try buildWatchPath(allocator, null, .{
        .api_version = "v1",
        .api_group = "",
        .plural = "nodes",
        .namespaced = false,
    }, .{});
    defer allocator.free(path);

    try std.testing.expect(std.mem.indexOf(u8, path, "/api/v1/nodes") != null);
    try std.testing.expect(std.mem.indexOf(u8, path, "namespaces") == null);
}

test "EventType parsing" {
    try std.testing.expectEqual(EventType.ADDED, try EventType.fromString("ADDED"));
    try std.testing.expectEqual(EventType.MODIFIED, try EventType.fromString("MODIFIED"));
    try std.testing.expectEqual(EventType.DELETED, try EventType.fromString("DELETED"));
    try std.testing.expectEqual(EventType.BOOKMARK, try EventType.fromString("BOOKMARK"));
    try std.testing.expectEqual(EventType.ERROR, try EventType.fromString("ERROR"));
    try std.testing.expectError(error.InvalidEventType, EventType.fromString("INVALID"));
}
