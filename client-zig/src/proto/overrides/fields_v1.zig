//! Custom FieldsV1 type with Kubernetes-compatible JSON parsing.
//! This overrides the generated protobuf type to handle embedded JSON objects.

const std = @import("std");
const protobuf = @import("protobuf");
const fd = protobuf.fd;

/// FieldsV1 stores a set of fields in a data structure like a Trie, in JSON format.
/// In Kubernetes JSON, the embedded object is inlined directly.
///
/// +protobuf.options.(gogoproto.goproto_stringer)=false
pub const FieldsV1 = struct {
    Raw: ?[]const u8 = null,

    pub const _desc_table = .{
        .Raw = fd(1, .{ .scalar = .bytes }),
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

    /// Custom JSON parser that handles Kubernetes FieldsV1.
    /// In Kubernetes JSON, FieldsV1 is an embedded object structure.
    /// We capture the raw JSON bytes.
    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !@This() {
        _ = options;

        const token = try source.peekNextTokenType();

        switch (token) {
            .object_begin, .array_begin => {
                // Parse as Value and re-serialize to capture raw JSON
                const value = try std.json.innerParse(std.json.Value, allocator, source, .{
                    .allocate = .alloc_if_needed,
                    .ignore_unknown_fields = true,
                });

                const json_str = std.json.Stringify.valueAlloc(allocator, value, .{}) catch return error.OutOfMemory;
                return .{ .Raw = json_str };
            },
            .null => {
                _ = try source.next();
                return .{ .Raw = null };
            },
            else => {
                // For primitive values
                const value = try std.json.innerParse(std.json.Value, allocator, source, .{
                    .allocate = .alloc_if_needed,
                });

                const json_str = std.json.Stringify.valueAlloc(allocator, value, .{}) catch return error.OutOfMemory;
                return .{ .Raw = json_str };
            },
        }
    }
};
