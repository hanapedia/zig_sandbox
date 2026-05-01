//! Custom Quantity types with Kubernetes-compatible JSON parsing.
//! These override the generated protobuf types to handle quantity strings.

const std = @import("std");
const protobuf = @import("protobuf");
const fd = protobuf.fd;

/// Quantity is a fixed-point representation of a number.
/// In Kubernetes JSON, this is serialized as a string like "100m", "1Gi", "500Mi".
///
/// +protobuf=true
/// +protobuf.embed=string
/// +protobuf.options.marshal=false
/// +protobuf.options.(gogoproto.goproto_stringer)=false
/// +k8s:deepcopy-gen=true
/// +k8s:openapi-gen=true
pub const Quantity = struct {
    string: ?[]const u8 = null,

    pub const _desc_table = .{
        .string = fd(1, .{ .scalar = .string }),
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

    /// Custom JSON parser that handles Kubernetes quantity strings.
    /// Kubernetes sends: "100m" or "1Gi" (plain string)
    /// We store it in the string field.
    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !@This() {
        _ = options;

        const token = try source.next();

        switch (token) {
            .string => |str| {
                // Non-allocated string - need to dupe
                return .{ .string = try allocator.dupe(u8, str) };
            },
            .allocated_string => |str| {
                // Already allocated
                return .{ .string = str };
            },
            .null => {
                return .{ .string = null };
            },
            else => {
                return error.UnexpectedToken;
            },
        }
    }
};

/// QuantityValue makes it possible to use a Quantity as value for a command
/// line parameter. Same JSON format as Quantity.
///
/// +protobuf=true
/// +protobuf.embed=string
/// +protobuf.options.marshal=false
/// +protobuf.options.(gogoproto.goproto_stringer)=false
/// +k8s:deepcopy-gen=true
pub const QuantityValue = struct {
    string: ?[]const u8 = null,

    pub const _desc_table = .{
        .string = fd(1, .{ .scalar = .string }),
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

    /// Custom JSON parser - same as Quantity.
    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !@This() {
        const qty = try Quantity.jsonParse(allocator, source, options);
        return .{ .string = qty.string };
    }
};
