//! Kubernetes watch client implementation.
//! Provides both low-level WatchStream and high-level Watcher(T) APIs.

const std = @import("std");
const tls = @import("tls");
const protobuf = @import("protobuf");
const client_mod = @import("../client/Client.zig");
const Client = client_mod.Client;
const ContentType = client_mod.ContentType;
const ResourceInfo = @import("typed.zig").ResourceInfo;
const proto = @import("../proto/mod.zig");
const runtime = @import("../proto/k8s/io/apimachinery/pkg/runtime.pb.zig");
const metav1 = @import("../proto/k8s/io/apimachinery/pkg/apis/meta/v1.pb.zig");

/// Kubernetes protobuf magic bytes
const K8S_PROTOBUF_MAGIC = "k8s\x00";

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

    /// Content type for the response (json or protobuf).
    /// Protobuf is more efficient and avoids JSON map field issues.
    contentType: ContentType = .protobuf,
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
        return error.UnknownEventType;
    }
};

/// Typed watch event containing the parsed resource object.
pub fn WatchEvent(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Raw event structure matching Kubernetes watch API response (JSON mode).
        pub const RawEvent = struct {
            type: []const u8,
            object: T,
        };

        event_type: EventType,
        // For JSON mode
        _json_parsed: ?std.json.Parsed(RawEvent) = null,
        // For protobuf mode
        _protobuf_value: ?T = null,
        _allocator: ?std.mem.Allocator = null,
        _is_protobuf: bool = false,

        /// Parsed resource object.
        /// For BOOKMARK events, only metadata.resourceVersion is populated.
        pub fn object(self: Self) T {
            if (self._is_protobuf) {
                return self._protobuf_value.?;
            } else {
                return self._json_parsed.?.value.object;
            }
        }

        /// Free the parsed object memory.
        pub fn deinit(self: *Self) void {
            if (self._is_protobuf) {
                if (self._protobuf_value) |*val| {
                    protobuf.deinit(self._allocator.?, val);
                }
            } else {
                if (self._json_parsed) |*parsed| {
                    parsed.deinit();
                }
            }
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

    // Connection state (pointer to avoid move issues)
    tls_conn: *tls.Connection,
    tcp_stream: std.Io.net.Stream,
    // TLS state - heap allocated to keep buffers alive
    tls_state: *TlsState,

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

    // Content type (json or protobuf)
    content_type: ContentType,

    /// TLS state that must stay at a fixed address for the connection lifetime.
    /// This fixes the use-after-free bug in tls.clientFromStream() which
    /// allocates buffers on the stack that go out of scope.
    const TlsState = struct {
        input_buf: [tls.input_buffer_len]u8,
        output_buf: [tls.output_buffer_len]u8,
        reader: std.Io.net.Stream.Reader,
        writer: std.Io.net.Stream.Writer,
    };

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

        // 3. Allocate TLS state on heap - this fixes the use-after-free bug in
        // tls.clientFromStream() which allocates buffers on the stack
        const tls_state = try client.allocator.create(TlsState);
        errdefer client.allocator.destroy(tls_state);

        // Initialize reader and writer with heap-allocated buffers
        tls_state.reader = tcp_stream.reader(client.io, &tls_state.input_buf);
        tls_state.writer = tcp_stream.writer(client.io, &tls_state.output_buf);

        // 4. Allocate TLS connection on heap to avoid move issues
        const tls_conn = try client.allocator.create(tls.Connection);
        errdefer client.allocator.destroy(tls_conn);

        // 5. Upgrade to TLS using tls.client() with heap-allocated reader/writer
        const rng_impl: std.Random.IoSource = .{ .io = client.io };
        const rng = rng_impl.interface();
        const now = std.Io.Clock.real.now(client.io);

        tls_conn.* = tls.client(&tls_state.reader.interface, &tls_state.writer.interface, .{
            .rng = rng,
            .now = now,
            .host = client.host,
            .root_ca = client.ca_bundle,
        }) catch {
            return error.TlsError;
        };
        errdefer tls_conn.close() catch {};

        // 6. Send HTTP GET request
        try sendWatchRequest(tls_conn, client, path, options.contentType);

        return Self{
            .allocator = client.allocator,
            .io = client.io,
            .tls_conn = tls_conn,
            .tcp_stream = tcp_stream,
            .tls_state = tls_state,
            .header_parsed = false,
            .is_chunked = false,
            .chunk_remaining = 0,
            .line_buffer = .empty,
            .read_buffer = undefined,
            .read_buffer_pos = 0,
            .read_buffer_len = 0,
            .closed = false,
            .content_type = options.contentType,
        };
    }

    /// Clean up resources and close connection.
    pub fn deinit(self: *Self) void {
        self.line_buffer.deinit(self.allocator);
        if (!self.closed) {
            self.tls_conn.close() catch {};
            self.tcp_stream.close(self.io);
            self.closed = true;
        }
        self.allocator.destroy(self.tls_conn);
        self.allocator.destroy(self.tls_state);
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
        // Note: tls_conn memory is freed in deinit()
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

    /// Read the next protobuf event from the stream.
    /// For protobuf mode: reads length-prefixed k8s protobuf envelope.
    /// Returns null when stream ends.
    /// Caller owns returned slice and must deallocate with self.allocator.
    pub fn readProtobufEvent(self: *Self) !?[]u8 {
        if (self.closed) return null;

        // Parse HTTP headers on first call
        if (!self.header_parsed) {
            try self.parseHTTPHeaders();
        }

        // Read the 4-byte length prefix
        // First, use any data already in line_buffer before reading more
        var len_buf: [4]u8 = undefined;
        var len_read: usize = 0;
        while (len_read < 4) {
            // Check if line_buffer has data we can use
            if (self.line_buffer.items.len > 0) {
                const available = self.line_buffer.items.len;
                const needed = 4 - len_read;
                const to_copy = @min(available, needed);
                @memcpy(len_buf[len_read..][0..to_copy], self.line_buffer.items[0..to_copy]);
                len_read += to_copy;
                // Remove copied bytes from line_buffer
                const remaining = self.line_buffer.items[to_copy..];
                @memmove(self.line_buffer.items[0..remaining.len], remaining);
                self.line_buffer.items.len = remaining.len;
                continue;
            }
            // Need more data from connection
            const bytes_read = try self.readMoreData();
            if (bytes_read == 0) {
                if (len_read == 0) return null; // Clean EOF
                return error.UnexpectedEndOfStream;
            }
        }

        // Parse length as big-endian u32
        const event_len: usize = @as(usize, std.mem.readInt(u32, &len_buf, .big));
        if (event_len == 0) return null;
        if (event_len > 10 * 1024 * 1024) return error.EventTooLarge; // 10MB limit

        // Read the event data
        while (self.line_buffer.items.len < event_len) {
            const bytes_read = try self.readMoreData();
            if (bytes_read == 0) return error.UnexpectedEndOfStream;
        }

        // Extract the event data
        const event_data = try self.allocator.dupe(u8, self.line_buffer.items[0..event_len]);
        errdefer self.allocator.free(event_data);

        // Remove event from buffer
        const remaining = self.line_buffer.items[event_len..];
        @memmove(self.line_buffer.items[0..remaining.len], remaining);
        self.line_buffer.items.len = remaining.len;

        return event_data;
    }

    /// Read the next complete JSON line from the stream.
    /// Handles HTTP chunked encoding and partial line buffering.
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

                // Get remaining body data after headers
                const body_start = end_idx + 4;
                const remaining = self.line_buffer.items[body_start..];

                // For chunked encoding, move body data to read_buffer (it starts with framing)
                // For non-chunked, keep it in line_buffer (it's application data)
                if (self.is_chunked and remaining.len > 0) {
                    // Move to read_buffer for chunked decoding
                    @memcpy(self.read_buffer[0..remaining.len], remaining);
                    self.read_buffer_pos = 0;
                    self.read_buffer_len = remaining.len;
                    self.line_buffer.items.len = 0;
                } else {
                    // Keep in line_buffer for raw mode
                    @memmove(self.line_buffer.items[0..remaining.len], remaining);
                    self.line_buffer.items.len = remaining.len;
                }

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
    fn findLineInBuffer(self: *Self) !?[]u8 {
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

    // ========================================================================
    // Buffered Reader Helpers
    // These use read_buffer as a buffer for TLS reads, avoiding byte-by-byte
    // TLS operations which can cause parsing issues.
    // ========================================================================

    /// Get available bytes in read_buffer (not yet consumed).
    fn bufferedAvailable(self: *Self) []u8 {
        return self.read_buffer[self.read_buffer_pos..self.read_buffer_len];
    }

    /// Consume n bytes from the buffered reader.
    fn bufferedConsume(self: *Self, n: usize) void {
        self.read_buffer_pos += n;
        // Reset position when buffer is empty to maximize space for next read
        if (self.read_buffer_pos >= self.read_buffer_len) {
            self.read_buffer_pos = 0;
            self.read_buffer_len = 0;
        }
    }

    /// Ensure at least `min_bytes` are available in the buffer.
    /// Reads from TLS if necessary.
    fn bufferedEnsure(self: *Self, min_bytes: usize) !bool {
        while (self.read_buffer_len - self.read_buffer_pos < min_bytes) {
            // Compact buffer if needed to make room
            if (self.read_buffer_pos > 0) {
                const available = self.bufferedAvailable();
                @memmove(self.read_buffer[0..available.len], available);
                self.read_buffer_len = available.len;
                self.read_buffer_pos = 0;
            }

            // Read more from TLS
            const space = self.read_buffer[self.read_buffer_len..];
            if (space.len == 0) return error.BufferFull;

            const n = self.tls_conn.read(space) catch |err| {
                if (err == error.EndOfStream) return false;
                // TlsBadVersion during watch can occur when TLS record boundaries
                // don't align with HTTP chunk boundaries. This is an intermittent issue
                // that depends on how the server chunks data vs TLS record sizes.
                // Treat it as connection closure to allow reconnection.
                if (err == error.TlsBadVersion) {
                    self.closed = true;
                    return error.ConnectionLost;
                }
                return err;
            };
            if (n == 0) return false; // EOF

            self.read_buffer_len += n;
        }
        return true;
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

        // Ensure we have data in the buffer
        if (self.bufferedAvailable().len == 0) {
            const has_data = try self.bufferedEnsure(1);
            if (!has_data) return 0;
        }

        // Copy available data (up to chunk_remaining) to line_buffer
        const available = self.bufferedAvailable();
        const n = @min(available.len, self.chunk_remaining);
        if (n == 0) return 0;

        try self.line_buffer.appendSlice(self.allocator, available[0..n]);
        self.bufferedConsume(n);
        self.chunk_remaining -= n;

        // If chunk finished, consume trailing CRLF
        if (self.chunk_remaining == 0) {
            try self.consumeCRLF();
        }

        return n;
    }

    /// Read and parse chunk size line (e.g., "4a\r\n" -> 74).
    /// Uses the buffered reader to avoid byte-by-byte TLS reads.
    /// Framing data stays in read_buffer, never goes to line_buffer.
    fn readChunkSize(self: *Self) !void {
        // Keep reading until we find \r\n in the buffered reader
        while (true) {
            const available = self.bufferedAvailable();

            // Look for \r\n in buffered data
            if (std.mem.indexOf(u8, available, "\r\n")) |crlf_pos| {
                // Found it - parse the chunk size
                const size_str = available[0..crlf_pos];

                if (size_str.len == 0 or size_str.len > 16) {
                    return error.InvalidChunkedEncodingSize;
                }

                self.chunk_remaining = std.fmt.parseInt(usize, size_str, 16) catch {
                    return error.InvalidChunkedEncodingSize;
                };

                // Consume the chunk size line (including \r\n) from buffered reader
                self.bufferedConsume(crlf_pos + 2);
                return;
            }

            // No \r\n found yet - read more data into buffer
            const has_data = try self.bufferedEnsure(available.len + 1);
            if (!has_data) return error.UnexpectedEndOfStream;
        }
    }

    /// Consume the trailing CRLF after chunk data.
    /// Uses the buffered reader to avoid byte-by-byte TLS reads.
    fn consumeCRLF(self: *Self) !void {
        // Ensure we have at least 2 bytes in buffer
        const has_data = try self.bufferedEnsure(2);
        if (!has_data) return error.InvalidChunkedEncoding;

        const available = self.bufferedAvailable();

        // Verify and consume \r\n
        if (available[0] != '\r' or available[1] != '\n') {
            return error.InvalidChunkedEncoding;
        }

        self.bufferedConsume(2);
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
        /// Last seen resourceVersion for reconnection.
        /// Updated from BOOKMARK events and successful event processing.
        last_resource_version: ?[]const u8 = null,

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

        /// Get the last seen resourceVersion for reconnection.
        /// Returns null if no events have been processed yet.
        pub fn getLastResourceVersion(self: *Self) ?[]const u8 {
            return self.last_resource_version;
        }

        /// Get the next watch event.
        /// Returns null when the stream ends.
        /// Caller must call event.deinit() when done.
        pub fn next(self: *Self) !?WatchEvent(T) {
            return switch (self.stream.content_type) {
                .protobuf => self.nextProtobuf(),
                .json => self.nextJson(),
            };
        }

        /// Parse next event from protobuf stream.
        /// Streaming format: 4-byte big-endian length + WatchEvent protobuf (no k8s envelope)
        fn nextProtobuf(self: *Self) !?WatchEvent(T) {
            // Read the next protobuf event (length-prefixed, no k8s envelope for streaming)
            const event_data = try self.stream.readProtobufEvent() orelse return null;
            defer self.allocator.free(event_data);

            // Decode WatchEvent directly (streaming format doesn't use k8s envelope)
            var reader: std.Io.Reader = .fixed(event_data);
            const watch_event = metav1.WatchEvent.decode(&reader, self.allocator) catch {
                return error.ProtobufDecodeError;
            };
            defer {
                var we = watch_event;
                we.deinit(self.allocator);
            }

            // Get event type
            const event_type = EventType.fromString(watch_event.type orelse "ADDED") catch {
                return error.UnknownEventType;
            };

            // The object field contains RawExtension with the serialized resource
            // For streaming watch, the object is wrapped in k8s envelope
            const object_ext = watch_event.object orelse {
                return error.InvalidResponse;
            };

            const object_raw = object_ext.raw orelse {
                return error.InvalidResponse;
            };

            // The raw data is k8s envelope format (k8s\x00 + Unknown wrapper)
            if (object_raw.len < 4 or !std.mem.eql(u8, object_raw[0..4], K8S_PROTOBUF_MAGIC)) {
                return error.InvalidResponse;
            }

            // Decode Unknown wrapper from object
            var unknown_reader: std.Io.Reader = .fixed(object_raw[4..]);
            const unknown = runtime.Unknown.decode(&unknown_reader, self.allocator) catch {
                return error.ProtobufDecodeError;
            };
            defer {
                var u = unknown;
                u.deinit(self.allocator);
            }

            // Decode the actual resource from Unknown.raw
            const resource_raw = unknown.raw orelse {
                return error.InvalidResponse;
            };

            var obj_reader: std.Io.Reader = .fixed(resource_raw);
            const resource = T.decode(&obj_reader, self.allocator) catch {
                return error.ProtobufDecodeError;
            };

            return WatchEvent(T){
                .event_type = event_type,
                ._protobuf_value = resource,
                ._allocator = self.allocator,
                ._is_protobuf = true,
            };
        }

        /// Parse next event from JSON stream.
        fn nextJson(self: *Self) !?WatchEvent(T) {
            // Read the next JSON line.
            const line = try self.stream.readLine() orelse return null;
            defer self.allocator.free(line);

            // Parse watch event directly using the RawEvent struct
            // T's jsonParse method will be called automatically for the object field
            @setEvalBranchQuota(1000000);
            const parsed = std.json.parseFromSlice(
                WatchEvent(T).RawEvent,
                self.allocator,
                line,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_if_needed },
            ) catch {
                return error.JsonParseError;
            };

            // Convert type string to enum
            const event_type = EventType.fromString(parsed.value.type) catch {
                parsed.deinit();
                return error.UnknownEventType;
            };

            return WatchEvent(T){
                .event_type = event_type,
                ._json_parsed = parsed,
                ._is_protobuf = false,
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
        const param = try std.fmt.allocPrint(allocator, "timeoutSeconds={d}", .{timeout});
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
    content_type: ContentType,
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
            "Accept: {s}\r\n" ++
            "Connection: keep-alive\r\n" ++
            "\r\n",
        .{ path, client.host, auth_header, content_type.acceptHeader() },
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
