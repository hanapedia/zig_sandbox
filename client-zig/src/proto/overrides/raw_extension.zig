//! Custom RawExtension type with Kubernetes-compatible JSON parsing.
//! This overrides the generated protobuf type to handle embedded JSON objects.

const std = @import("std");
const protobuf = @import("protobuf");
const fd = protobuf.fd;

/// RawExtension is used to hold extensions in external versions.
/// In Kubernetes JSON, the embedded object is inlined directly,
/// not wrapped in a "raw" field.
///
/// +k8s:deepcopy-gen=true
/// +protobuf=true
/// +k8s:openapi-gen=true
pub const RawExtension = struct {
    raw: ?[]const u8 = null,

    pub const _desc_table = .{
        .raw = fd(1, .{ .scalar = .bytes }),
    };

    /// Encodes the message to the writer
    pub fn encode(
        self: @This(),
        writer: *std.Io.Writer,
        allocator: std.mem.Allocator,
    ) (std.Io.Writer.Error || std.mem.Allocator.Error)!void {
        return protobuf.encode(writer, allocator, self);
    }

    /// Decodes the message from the bytes read from the reader.
    pub fn decode(
        reader: *std.Io.Reader,
        allocator: std.mem.Allocator,
    ) (protobuf.DecodingError || std.Io.Reader.Error || std.mem.Allocator.Error)!@This() {
        return protobuf.decode(@This(), reader, allocator);
    }

    /// Deinitializes and frees the memory associated with the message.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        return protobuf.deinit(allocator, self);
    }

    /// Duplicates the message.
    pub fn dupe(self: @This(), allocator: std.mem.Allocator) std.mem.Allocator.Error!@This() {
        return protobuf.dupe(@This(), self, allocator);
    }

    /// Decodes the message from the JSON string.
    pub fn jsonDecode(
        input: []const u8,
        options: std.json.ParseOptions,
        allocator: std.mem.Allocator,
    ) !std.json.Parsed(@This()) {
        return protobuf.json.decode(@This(), input, options, allocator);
    }

    /// Encodes the message to a JSON string.
    pub fn jsonEncode(
        self: @This(),
        options: std.json.Stringify.Options,
        pb_options: protobuf.json.Options,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        return protobuf.json.encode(self, options, pb_options, allocator);
    }

    /// Custom JSON parser that handles Kubernetes RawExtension.
    /// In Kubernetes JSON, RawExtension contains the embedded object directly.
    /// We need to capture the raw JSON bytes of whatever value is present.
    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !@This() {
        _ = options;

        // Peek at the next token to determine what we're dealing with
        const token = try source.peekNextTokenType();

        switch (token) {
            .object_begin, .array_begin => {
                // For objects/arrays, we need to capture the entire JSON structure
                // Skip the value and capture the bytes (this is a limitation -
                // we'd need access to the underlying buffer to capture raw bytes)
                // For now, parse as Value and re-serialize
                const value = try std.json.innerParse(std.json.Value, allocator, source, .{
                    .allocate = .alloc_if_needed,
                    .ignore_unknown_fields = true,
                });

                // Serialize back to JSON string
                const json_str = std.json.Stringify.valueAlloc(allocator, value, .{}) catch return error.OutOfMemory;
                return .{ .raw = json_str };
            },
            .null => {
                _ = try source.next(); // consume the null token
                return .{ .raw = null };
            },
            else => {
                // For primitive values, parse and stringify
                const value = try std.json.innerParse(std.json.Value, allocator, source, .{
                    .allocate = .alloc_if_needed,
                });

                const json_str = std.json.Stringify.valueAlloc(allocator, value, .{}) catch return error.OutOfMemory;
                return .{ .raw = json_str };
            },
        }
    }
};
