//! Custom Time and MicroTime types with Kubernetes-compatible JSON parsing.
//! These override the generated protobuf types to handle RFC3339 timestamp strings.

const std = @import("std");
const protobuf = @import("protobuf");
const fd = protobuf.fd;

/// Time is a wrapper around time.Time which supports correct
/// marshaling to YAML and JSON. In Kubernetes JSON, this is serialized
/// as an RFC3339 string like "2026-04-29T14:08:05Z".
///
/// +protobuf.options.marshal=false
/// +protobuf.as=Timestamp
/// +protobuf.options.(gogoproto.goproto_stringer)=false
pub const Time = struct {
    seconds: ?i64 = null,
    nanos: ?i32 = null,

    pub const _desc_table = .{
        .seconds = fd(1, .{ .scalar = .int64 }),
        .nanos = fd(2, .{ .scalar = .int32 }),
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

    /// Custom JSON parser that handles Kubernetes RFC3339 timestamp strings.
    /// Kubernetes sends: "2026-04-29T14:08:05Z"
    /// We convert to: {seconds: i64, nanos: i32}
    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !@This() {
        _ = allocator;
        _ = options;

        // Get the next token - should be a string for RFC3339 timestamp
        const token = try source.next();

        switch (token) {
            .string, .allocated_string => |str| {
                return parseRfc3339(str);
            },
            .null => {
                // null timestamp
                return .{ .seconds = null, .nanos = null };
            },
            else => {
                return error.UnexpectedToken;
            },
        }
    }

    /// Parse RFC3339 timestamp string into seconds and nanos.
    /// Format: "2006-01-02T15:04:05Z" or "2006-01-02T15:04:05.999999999Z"
    fn parseRfc3339(str: []const u8) error{UnexpectedToken}!@This() {
        if (str.len < 20) return error.UnexpectedToken;

        // Parse date components: YYYY-MM-DDTHH:MM:SS
        const year = std.fmt.parseInt(i32, str[0..4], 10) catch return error.UnexpectedToken;
        const month = std.fmt.parseInt(u4, str[5..7], 10) catch return error.UnexpectedToken;
        const day = std.fmt.parseInt(u5, str[8..10], 10) catch return error.UnexpectedToken;
        const hour = std.fmt.parseInt(u5, str[11..13], 10) catch return error.UnexpectedToken;
        const minute = std.fmt.parseInt(u6, str[14..16], 10) catch return error.UnexpectedToken;
        const second = std.fmt.parseInt(u6, str[17..19], 10) catch return error.UnexpectedToken;

        // Convert to epoch seconds using Zig's datetime
        const epoch_day = epochDaysFromDate(year, month, day);
        const day_seconds: i64 = @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second);
        const seconds: i64 = epoch_day * 86400 + day_seconds;

        // Parse optional fractional seconds
        var nanos: i32 = 0;
        if (str.len > 20 and str[19] == '.') {
            // Find end of fractional part (before 'Z' or '+' or '-')
            var frac_end: usize = 20;
            while (frac_end < str.len and str[frac_end] >= '0' and str[frac_end] <= '9') {
                frac_end += 1;
            }
            const frac_str = str[20..frac_end];
            if (frac_str.len > 0) {
                // Pad or truncate to 9 digits for nanoseconds
                var frac_val: i32 = 0;
                for (frac_str, 0..) |c, i| {
                    if (i >= 9) break;
                    frac_val = frac_val * 10 + @as(i32, c - '0');
                }
                // Pad with zeros if less than 9 digits
                var remaining = 9 - @min(frac_str.len, 9);
                while (remaining > 0) : (remaining -= 1) {
                    frac_val *= 10;
                }
                nanos = frac_val;
            }
        }

        return .{ .seconds = seconds, .nanos = nanos };
    }

    /// Calculate days since Unix epoch (1970-01-01) for a given date.
    fn epochDaysFromDate(year: i32, month: u4, day: u5) i64 {
        // Algorithm from http://howardhinnant.github.io/date_algorithms.html
        var y: i32 = year;
        const m: i32 = @intCast(month);
        const d: i32 = @intCast(day);

        if (m <= 2) y -= 1;
        const era: i32 = @divFloor(y, 400);
        const yoe: i32 = @mod(y, 400); // year of era [0, 399]
        const doy: i32 = @divFloor(153 * (m + (if (m > 2) @as(i32, -3) else 9)) + 2, 5) + d - 1; // day of year [0, 365]
        const doe: i32 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy; // day of era [0, 146096]
        const days: i64 = @as(i64, era) * 146097 + @as(i64, doe) - 719468;
        return days;
    }
};

/// MicroTime is version of Time with microsecond level precision.
/// Same JSON format as Time (RFC3339 string).
///
/// +protobuf.options.marshal=false
/// +protobuf.as=Timestamp
/// +protobuf.options.(gogoproto.goproto_stringer)=false
pub const MicroTime = struct {
    seconds: ?i64 = null,
    nanos: ?i32 = null,

    pub const _desc_table = .{
        .seconds = fd(1, .{ .scalar = .int64 }),
        .nanos = fd(2, .{ .scalar = .int32 }),
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

    /// Custom JSON parser - same as Time.
    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !@This() {
        const time_result = try Time.jsonParse(allocator, source, options);
        return .{ .seconds = time_result.seconds, .nanos = time_result.nanos };
    }
};
