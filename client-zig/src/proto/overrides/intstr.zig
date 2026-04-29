//! Custom IntOrString type with Kubernetes-compatible JSON parsing.
//! This overrides the generated protobuf type to handle raw int/string values.

const std = @import("std");
const protobuf = @import("protobuf");
const fd = protobuf.fd;

/// Type constants for IntOrString
pub const Type = struct {
    pub const Int: i64 = 0;
    pub const String: i64 = 1;
};

/// IntOrString is a type that can hold an int32 or a string.
/// In Kubernetes JSON, this is serialized as a raw value: 8080 or "http"
/// (not wrapped in an object).
///
/// +protobuf=true
/// +protobuf.options.(gogoproto.goproto_stringer)=false
/// +k8s:openapi-gen=true
pub const IntOrString = struct {
    type: ?i64 = null,
    intVal: ?i32 = null,
    strVal: ?[]const u8 = null,

    pub const _desc_table = .{
        .type = fd(1, .{ .scalar = .int64 }),
        .intVal = fd(2, .{ .scalar = .int32 }),
        .strVal = fd(3, .{ .scalar = .string }),
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

    /// Custom JSON parser that handles Kubernetes IntOrString values.
    /// Kubernetes sends: 8080 (number) or "http" (string)
    /// We detect the type and set appropriate fields.
    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !@This() {
        _ = options;

        const token = try source.next();

        switch (token) {
            .number => |num_str| {
                // It's a number - parse as int32
                const int_val = std.fmt.parseInt(i32, num_str, 10) catch {
                    return error.InvalidNumber; // This is in std.json.ParseError
                };
                return .{
                    .type = Type.Int,
                    .intVal = int_val,
                    .strVal = null,
                };
            },
            .string => |str| {
                // It's a string - dupe and store
                return .{
                    .type = Type.String,
                    .intVal = null,
                    .strVal = try allocator.dupe(u8, str),
                };
            },
            .allocated_string => |str| {
                // Already allocated string
                return .{
                    .type = Type.String,
                    .intVal = null,
                    .strVal = str,
                };
            },
            .null => {
                return .{
                    .type = null,
                    .intVal = null,
                    .strVal = null,
                };
            },
            else => {
                return error.UnexpectedToken;
            },
        }
    }

    /// Helper: Check if this is an integer type
    pub fn isInt(self: @This()) bool {
        return self.type == Type.Int;
    }

    /// Helper: Check if this is a string type
    pub fn isString(self: @This()) bool {
        return self.type == Type.String;
    }

    /// Helper: Get the integer value (returns null if not int type)
    pub fn intValue(self: @This()) ?i32 {
        if (self.type == Type.Int) return self.intVal;
        return null;
    }

    /// Helper: Get the string value (returns null if not string type)
    pub fn stringValue(self: @This()) ?[]const u8 {
        if (self.type == Type.String) return self.strVal;
        return null;
    }
};
