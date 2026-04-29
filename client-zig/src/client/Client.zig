//! HTTP client wrapper for Kubernetes API requests.
//! Uses tls.zig for TLS connections to work around std.http.Client TLS issues.
const std = @import("std");
const tls = @import("tls");
const protobuf = @import("protobuf");
const runtime = @import("../proto/k8s/io/apimachinery/pkg/runtime.pb.zig");

/// Kubernetes protobuf magic bytes
const K8S_PROTOBUF_MAGIC = "k8s\x00";

/// Content types
pub const ContentType = enum {
    json,
    protobuf,

    pub fn acceptHeader(self: ContentType) []const u8 {
        return switch (self) {
            .json => "application/json",
            .protobuf => "application/vnd.kubernetes.protobuf",
        };
    }
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    host: []const u8,
    port: u16,
    token: ?[]const u8,
    ca_bundle: tls.config.cert.Bundle,
    has_custom_ca: bool,

    pub const Error = error{
        ConnectionFailed,
        RequestFailed,
        InvalidResponse,
        Unauthorized,
        Forbidden,
        NotFound,
        Conflict,
        ServerError,
        JsonParseError,
        ProtobufDecodeError,
        CertificateError,
        InvalidUri,
        TlsError,
    };

    pub const Options = struct {
        host: []const u8,
        token: ?[]const u8 = null,
        ca_cert: ?[]const u8 = null, // DER-encoded certificate
        skip_tls_verify: bool = false,
    };

    /// Initialize a new Kubernetes API client.
    pub fn init(io: std.Io, allocator: std.mem.Allocator, options: Options) !Client {
        // Parse host to extract hostname and port
        const uri = std.Uri.parse(options.host) catch return error.InvalidUri;
        const hostname = if (uri.host) |h| h.percent_encoded else return error.InvalidUri;
        const port: u16 = uri.port orelse 443;

        var ca_bundle: tls.config.cert.Bundle = .empty;
        var has_custom_ca = false;

        if (options.ca_cert) |ca_cert| {
            has_custom_ca = true;
            // Add the DER-encoded certificate to the bundle
            const now = std.Io.Clock.real.now(io);
            const decoded_start: u32 = @intCast(ca_bundle.bytes.items.len);
            try ca_bundle.bytes.appendSlice(allocator, ca_cert);
            ca_bundle.parseCert(allocator, decoded_start, now.toSeconds()) catch |err| {
                ca_bundle.bytes.items.len = decoded_start;
                std.debug.print("Failed to parse CA cert: {}\n", .{err});
                return error.CertificateError;
            };
            std.debug.print("CA cert loaded, bundle has {} certs\n", .{ca_bundle.map.count()});
        } else if (!options.skip_tls_verify) {
            // Load system CA bundle
            ca_bundle.rescan(allocator, io, std.Io.Clock.real.now(io)) catch |err| {
                std.debug.print("Failed to load system CA bundle: {}\n", .{err});
                // Continue without system certs - might work with skip_tls_verify
            };
        }

        return .{
            .allocator = allocator,
            .io = io,
            .host = try allocator.dupe(u8, hostname),
            .port = port,
            .token = if (options.token) |t| try allocator.dupe(u8, t) else null,
            .ca_bundle = ca_bundle,
            .has_custom_ca = has_custom_ca,
        };
    }

    pub fn deinit(self: *Client) void {
        self.ca_bundle.deinit(self.allocator);
        self.allocator.free(self.host);
        if (self.token) |t| self.allocator.free(t);
    }

    /// Perform a GET request and parse the response as protobuf into type T.
    pub fn get(self: *Client, comptime T: type, path: []const u8) !ProtoResult(T) {
        const response = try self.requestWithContentType(.GET, path, null, .protobuf);
        errdefer self.allocator.free(response.body);

        // Check status code
        switch (response.status) {
            .ok => {},
            .unauthorized => return error.Unauthorized,
            .forbidden => return error.Forbidden,
            .not_found => return error.NotFound,
            .conflict => return error.Conflict,
            else => {
                if (@intFromEnum(response.status) >= 500) {
                    return error.ServerError;
                }
                return error.InvalidResponse;
            },
        }

        // Parse protobuf response
        return self.decodeK8sProtobuf(T, response.body);
    }

    /// Result type for protobuf decoding - owns the response body memory
    pub fn ProtoResult(comptime T: type) type {
        return struct {
            value: T,
            _response_body: []const u8,
            _allocator: std.mem.Allocator,

            pub fn deinit(self: *@This()) void {
                protobuf.deinit(self._allocator, &self.value);
                self._allocator.free(self._response_body);
            }
        };
    }

    /// Decode Kubernetes protobuf envelope format.
    /// Format: k8s\x00 + protobuf(Unknown{typeMeta, raw})
    /// The raw field contains the actual protobuf-encoded message.
    fn decodeK8sProtobuf(self: *Client, comptime T: type, body: []const u8) !ProtoResult(T) {
        // Check magic bytes
        if (body.len < 4 or !std.mem.eql(u8, body[0..4], K8S_PROTOBUF_MAGIC)) {
            std.debug.print("Invalid K8s protobuf magic, got: {x}\n", .{body[0..@min(4, body.len)]});
            return error.InvalidResponse;
        }

        // Skip magic bytes and decode Unknown wrapper
        var reader: std.Io.Reader = .fixed(body[4..]);

        const unknown = runtime.Unknown.decode(&reader, self.allocator) catch |err| {
            std.debug.print("Failed to decode Unknown wrapper: {}\n", .{err});
            return error.ProtobufDecodeError;
        };
        defer {
            var u = unknown;
            u.deinit(self.allocator);
        }

        // The raw field contains the actual message
        const raw_data = unknown.raw orelse {
            std.debug.print("Unknown wrapper has no raw data\n", .{});
            return error.InvalidResponse;
        };

        // Decode the actual type from raw bytes
        var raw_reader: std.Io.Reader = .fixed(raw_data);

        const value = T.decode(&raw_reader, self.allocator) catch |err| {
            std.debug.print("Failed to decode {s}: {}\n", .{ @typeName(T), err });
            return error.ProtobufDecodeError;
        };

        return .{
            .value = value,
            ._response_body = body,
            ._allocator = self.allocator,
        };
    }

    /// Perform a GET request and parse the response as JSON into type T.
    /// Deprecated: Use get() for protobuf encoding instead.
    pub fn getJson(self: *Client, comptime T: type, path: []const u8) !std.json.Parsed(T) {
        const response = try self.requestWithContentType(.GET, path, null, .json);
        defer self.allocator.free(response.body);

        // Check status code
        switch (response.status) {
            .ok => {},
            .unauthorized => return error.Unauthorized,
            .forbidden => return error.Forbidden,
            .not_found => return error.NotFound,
            .conflict => return error.Conflict,
            else => {
                if (@intFromEnum(response.status) >= 500) {
                    return error.ServerError;
                }
                return error.InvalidResponse;
            },
        }

        // Parse JSON response
        @setEvalBranchQuota(1000000);

        return T.jsonDecode(response.body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_if_needed,
        }, self.allocator) catch |err| {
            std.debug.print("Proto JSON parse error: {}\n", .{err});
            std.debug.print("Response body (first 500 chars): {s}\n", .{response.body[0..@min(500, response.body.len)]});
            return error.JsonParseError;
        };
    }

    /// Perform a raw HTTP request using tls.zig with JSON content type.
    pub fn request(
        self: *Client,
        method: std.http.Method,
        path: []const u8,
        body: ?[]const u8,
    ) !Response {
        return self.requestWithContentType(method, path, body, .json);
    }

    /// Perform a raw HTTP request using tls.zig with specified content type.
    pub fn requestWithContentType(
        self: *Client,
        method: std.http.Method,
        path: []const u8,
        body: ?[]const u8,
        content_type: ContentType,
    ) !Response {
        // Create HostName for connection
        const hostname = std.Io.net.HostName.init(self.host) catch |err| {
            std.debug.print("Invalid hostname: {}\n", .{err});
            return error.ConnectionFailed;
        };

        // Connect to server via TCP
        const tcp_stream = hostname.connect(self.io, self.port, .{ .mode = .stream }) catch |err| {
            std.debug.print("TCP connect failed: {}\n", .{err});
            return error.ConnectionFailed;
        };
        defer tcp_stream.close(self.io);

        // Get random number generator
        const rng_impl: std.Random.IoSource = .{ .io = self.io };
        const rng = rng_impl.interface();

        // Get current time
        const now = std.Io.Clock.real.now(self.io);

        // Upgrade to TLS using tls.zig
        var tls_conn = tls.clientFromStream(self.io, tcp_stream, .{
            .rng = rng,
            .now = now,
            .host = self.host,
            .root_ca = self.ca_bundle,
        }) catch |err| {
            std.debug.print("TLS handshake failed: {}\n", .{err});
            return error.TlsError;
        };
        defer tls_conn.close() catch {};

        // Build HTTP request
        const path_to_use = if (path.len > 0) path else "/";
        const auth_header = if (self.token) |token|
            try std.fmt.allocPrint(self.allocator, "Authorization: Bearer {s}\r\n", .{token})
        else
            try self.allocator.dupe(u8, "");
        defer self.allocator.free(auth_header);

        const content_length_header = if (body) |b|
            try std.fmt.allocPrint(self.allocator, "Content-Length: {d}\r\n", .{b.len})
        else
            try self.allocator.dupe(u8, "");
        defer self.allocator.free(content_length_header);

        const body_content = body orelse "";
        const accept_header = content_type.acceptHeader();

        const request_str = try std.fmt.allocPrint(self.allocator, "{s} {s} HTTP/1.1\r\nHost: {s}\r\n{s}Accept: {s}\r\nContent-Type: application/json\r\n{s}Connection: close\r\n\r\n{s}", .{
            @tagName(method),
            path_to_use,
            self.host,
            auth_header,
            accept_header,
            content_length_header,
            body_content,
        });
        defer self.allocator.free(request_str);

        // Send request
        _ = tls_conn.write(request_str) catch |err| {
            std.debug.print("TLS write failed: {}\n", .{err});
            return error.RequestFailed;
        };

        // Read response
        var response_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer response_buf.deinit(self.allocator);

        var read_buf: [4096]u8 = undefined;
        while (true) {
            const n = tls_conn.read(&read_buf) catch |err| {
                if (err == error.EndOfStream) break;
                std.debug.print("TLS read failed: {}\n", .{err});
                return error.RequestFailed;
            };
            if (n == 0) break;
            try response_buf.appendSlice(self.allocator, read_buf[0..n]);
        }

        return try self.parseResponse(response_buf.items);
    }

    fn parseResponse(self: *Client, response_data: []const u8) !Response {
        // Find end of status line
        const status_line_end = std.mem.indexOf(u8, response_data, "\r\n") orelse return error.InvalidResponse;
        const status_line = response_data[0..status_line_end];

        // Parse status code - Format: "HTTP/1.1 200 OK"
        var status_parts = std.mem.tokenizeScalar(u8, status_line, ' ');
        _ = status_parts.next() orelse return error.InvalidResponse; // Skip HTTP version
        const status_code_str = status_parts.next() orelse return error.InvalidResponse;
        const status_code = std.fmt.parseInt(u16, status_code_str, 10) catch return error.InvalidResponse;

        // Find end of headers
        const headers_end = std.mem.indexOf(u8, response_data, "\r\n\r\n") orelse return error.InvalidResponse;
        const headers_section = response_data[status_line_end + 2 .. headers_end];

        // Check if response is chunked
        var is_chunked = false;
        var headers_iter = std.mem.tokenizeSequence(u8, headers_section, "\r\n");
        while (headers_iter.next()) |header_line| {
            const colon_idx = std.mem.indexOf(u8, header_line, ":") orelse continue;
            const name = header_line[0..colon_idx];
            const value = std.mem.trim(u8, header_line[colon_idx + 1 ..], " ");
            if (std.ascii.eqlIgnoreCase(name, "Transfer-Encoding") and std.mem.eql(u8, value, "chunked")) {
                is_chunked = true;
                break;
            }
        }

        // Body starts after headers
        const body_start = headers_end + 4;
        const raw_body = response_data[body_start..];

        const response_body = if (is_chunked)
            try self.decodeChunkedBody(raw_body)
        else
            try self.allocator.dupe(u8, raw_body);

        return .{
            .status = @enumFromInt(status_code),
            .body = response_body,
        };
    }

    /// Decode HTTP chunked transfer encoding
    fn decodeChunkedBody(self: *Client, chunked_data: []const u8) ![]const u8 {
        var result: std.ArrayListUnmanaged(u8) = .empty;
        errdefer result.deinit(self.allocator);

        var pos: usize = 0;
        while (pos < chunked_data.len) {
            // Find end of chunk size line
            const size_line_end = std.mem.indexOfPos(u8, chunked_data, pos, "\r\n") orelse
                return error.InvalidResponse;
            const size_line = chunked_data[pos..size_line_end];

            // Parse chunk size (hexadecimal)
            const chunk_size = std.fmt.parseInt(usize, size_line, 16) catch
                return error.InvalidResponse;

            // Move past size line
            pos = size_line_end + 2;

            // If chunk size is 0, we're done
            if (chunk_size == 0) break;

            // Read chunk data
            if (pos + chunk_size > chunked_data.len) return error.InvalidResponse;
            try result.appendSlice(self.allocator, chunked_data[pos .. pos + chunk_size]);

            // Move past chunk data and trailing \r\n
            pos += chunk_size;
            if (pos + 2 > chunked_data.len) return error.InvalidResponse;
            if (chunked_data[pos] != '\r' or chunked_data[pos + 1] != '\n')
                return error.InvalidResponse;
            pos += 2;
        }

        return try result.toOwnedSlice(self.allocator);
    }

    pub const Response = struct {
        status: std.http.Status,
        body: []const u8,
    };
};

test "Client initialization" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var client = try Client.init(io, allocator, .{
        .host = "https://localhost:6443",
        .token = "test-token",
    });
    defer client.deinit();

    try std.testing.expectEqualStrings("localhost", client.host);
    try std.testing.expectEqual(@as(u16, 6443), client.port);
    try std.testing.expectEqualStrings("test-token", client.token.?);
}
