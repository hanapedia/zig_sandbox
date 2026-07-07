const std = @import("std");
const spec = @import("spec.zig");

pub const AttrHeader = extern struct {
    len: u16,
    type: u16,

    pub const ALIGNTO: usize = 4;
};

/// Generic attribute decoder for netlink attribute-set structs.
/// Assumptions:
/// - T is a struct with all optional fields defaulting to null
/// - T has a pub const Enum of type enum(u16) mapping attribute names to nla_type values
/// - Field names in T match the corresponding Enum member names exactly
/// - buf contains only the attribute payload (nlmsghdr and any fixed header already stripped)
/// - buf is valid for the lifetime of the returned T (string/binary fields are zero-copy slices into buf)
/// - Unknown nla_types in buf are silently skipped
/// - Each attribute appears at most once; duplicate nla_types overwrite earlier values
pub fn genericDecode(comptime T: type, buf: []const u8) !T {
    comptime {
        if (@typeInfo(T) != .@"struct") @compileError("decode requires a struct type");
        if (!@hasDecl(T, "Enum")) @compileError("decode requires T to have a pub const Enum");
    }
    var result: T = .{};
    var offset: usize = 0;
    while (offset < buf.len) {
        if (offset + @sizeOf(AttrHeader) > buf.len) return error.BufferTooSmall;
        const header = std.mem.bytesToValue(AttrHeader, buf[offset..][0..@sizeOf(AttrHeader)]);
        const len: usize = @intCast(header.len);
        if (len < @sizeOf(AttrHeader)) return error.InvalidAttrLen;

        if (offset + len > buf.len) return error.BufferTooSmall;
        const value_bytes = buf[offset + @sizeOf(AttrHeader) .. offset + len];
        inline for (std.meta.fields(T)) |field| {
            if (!@hasField(T.Enum, field.name)) continue;
            if (@intFromEnum(@field(T.Enum, field.name)) == header.type) {
                const FieldType = @typeInfo(field.type).optional.child;
                @field(result, field.name) = try FieldType.decode(value_bytes);
            }
        }

        offset += std.mem.alignForward(usize, len, AttrHeader.ALIGNTO);
    }

    return result;
}

/// Generic attribute encoder for netlink attribute-set structs.
/// Assumptions:
/// - T is a struct with all optional fields defaulting to null
/// - T has a pub const Enum of type enum(u16) mapping attribute names to nla_type values
/// - Field names in T match the corresponding Enum member names exactly
/// - buf is large enough to hold all encoded attributes including headers and alignment padding
/// - Null fields are skipped and not written to buf
/// - Each attribute is padded to AttrHeader.ALIGNTO byte alignment on the wire
pub fn genericEncode(comptime T: type, obj: T, buf: []u8) !usize {
    comptime {
        if (@typeInfo(T) != .@"struct") @compileError("encode requires a struct type");
        if (!@hasDecl(T, "Enum")) @compileError("encode requires T to have a pub const Enum");
    }

    var offset: usize = 0;
    inline for (std.meta.fields(T)) |field_meta| {
        if (@field(obj, field_meta.name)) |field| {
            if (!@hasField(T.Enum, field_meta.name)) continue;
            if (offset + @sizeOf(AttrHeader) > buf.len) return error.BufferTooSmall;
            const len = try field.encode(buf[offset + @sizeOf(AttrHeader) ..]);
            const header = AttrHeader{
                .len = @intCast(@sizeOf(AttrHeader) + len),
                .type = @intFromEnum(@field(T.Enum, field_meta.name)),
            };

            @memcpy(buf[offset..][0..@sizeOf(AttrHeader)], std.mem.asBytes(&header)); // write header
            offset += std.mem.alignForward(usize, @sizeOf(AttrHeader) + len, AttrHeader.ALIGNTO);
        }
    }
    return offset;
}

/// TODO: consideration for non-host endian fields
pub fn ScalarAttr(attr_type: spec.AttributeTypes) type {
    const T = attr_type.asZigType();
    return struct {
        comptime {
            switch (attr_type) {
                .nest, .@"sub-message", .@"indexed-array", .pad => @compileError("ScalarAttr does not support non-scalar type"),
                else => {},
            }
        }
        const Self = @This();
        pub const kind = attr_type;
        value: T,

        /// buf content is not copied. caller must keep buf until done using.
        pub fn decode(buf: []const u8) !Self {
            const value: T = switch (kind) {
                inline .u8, .u16, .u32, .u64, .s32, .uint => ints: {
                    if (buf.len < @sizeOf(T)) return error.BufferTooSmall;
                    break :ints std.mem.readInt(T, buf[0..@sizeOf(T)], .little);
                },
                .string => buf,
                .binary => buf,
                .flag => true,
                else => unreachable,
            };
            return Self{ .value = value };
        }

        pub fn encode(self: Self, buf: []u8) !usize {
            switch (kind) {
                inline .u8, .u16, .u32, .u64, .s32, .uint => |k| {
                    const U = comptime k.asZigType();
                    if (buf.len < @sizeOf(U)) return error.BufferTooSmall;
                    std.mem.writeInt(U, buf[0..@sizeOf(U)], self.value, .little);
                    return @sizeOf(U);
                },
                .string, .binary => {
                    if (buf.len < self.value.len) return error.BufferTooSmall;
                    @memcpy(buf[0..self.value.len], self.value);
                    return self.value.len;
                },
                .flag => return 0, // no data, just attr header.
                else => unreachable,
            }
        }
    };
}

pub fn EnumAttr(T: type) type {
    comptime {
        if (@typeInfo(T) != .@"enum") @compileError("EnumAttr requires an enum type, got: " ++ @typeName(T));
    }

    return struct {
        const Self = @This();
        value: T,

        const Tag = @typeInfo(T).@"enum".tag_type;

        pub fn decode(buf: []const u8) !Self {
            if (buf.len < @sizeOf(Tag)) return error.BufferTooSmall;
            const value: Tag = std.mem.readInt(Tag, buf[0..@sizeOf(Tag)], .little);
            return Self{ .value = @enumFromInt(value) };
        }

        pub fn encode(self: Self, buf: []u8) !usize {
            if (buf.len < @sizeOf(Tag)) return error.BufferTooSmall;
            std.mem.writeInt(Tag, buf[0..@sizeOf(Tag)], @intFromEnum(self.value), .little);
            return @sizeOf(Tag);
        }
    };
}

pub fn NestedAttr(T: type) type {
    comptime {
        if (@typeInfo(T) != .@"struct") @compileError("NestedAttr requires a struct type");
        if (!@hasDecl(T, "Enum")) @compileError("NestedAttr requires T to have a pub const Enum");
        if (!@hasDecl(T, "decode")) @compileError("NestedAttr requires T to have a decode method");
        if (!@hasDecl(T, "encode")) @compileError("NestedAttr requires T to have an encode method");
    }

    return struct {
        const Self = @This();
        value: T,

        pub fn decode(buf: []const u8) !Self {
            return Self{ .value = try T.decode(buf) };
        }

        pub fn encode(self: Self, buf: []u8) !usize {
            return T.encode(self.value, buf);
        }
    };
}

test "ScalarAttr u32 encode decode round trip" {
    const TestEnum = enum(u16) { mtu = 1, _ };
    const TestAttrs = struct {
        pub const Enum = TestEnum;
        mtu: ?ScalarAttr(.u32) = null,
    };

    var buf: [64]u8 = std.mem.zeroes([64]u8);
    const input = TestAttrs{ .mtu = .{ .value = 1500 } };

    const written = try genericEncode(TestAttrs, input, &buf);
    const result = try genericDecode(TestAttrs, buf[0..written]);

    try std.testing.expectEqual(@as(u32, 1500), result.mtu.?.value);
}

test "ScalarAttr string encode decode round trip" {
    const TestEnum = enum(u16) { ifname = 1, _ };
    const TestAttrs = struct {
        pub const Enum = TestEnum;
        ifname: ?ScalarAttr(.string) = null,
    };

    var buf: [64]u8 = std.mem.zeroes([64]u8);
    const input = TestAttrs{ .ifname = .{ .value = "eth0" } };

    const written = try genericEncode(TestAttrs, input, &buf);
    const result = try genericDecode(TestAttrs, buf[0..written]);

    try std.testing.expectEqualStrings("eth0", result.ifname.?.value);
}

test "null fields are skipped in encode" {
    const TestEnum = enum(u16) { mtu = 1, ifname = 2, _ };
    const TestAttrs = struct {
        pub const Enum = TestEnum;
        mtu: ?ScalarAttr(.u32) = null,
        ifname: ?ScalarAttr(.string) = null,
    };

    var buf: [64]u8 = std.mem.zeroes([64]u8);
    const input = TestAttrs{ .mtu = .{ .value = 42 } };

    const written = try genericEncode(TestAttrs, input, &buf);
    const result = try genericDecode(TestAttrs, buf[0..written]);

    try std.testing.expectEqual(@as(u32, 42), result.mtu.?.value);
    try std.testing.expect(result.ifname == null);
}

test "NestedAttr encode decode round trip" {
    const InnerEnum = enum(u16) { speed = 1, _ };
    const InnerAttrs = struct {
        pub const Enum = InnerEnum;
        speed: ?ScalarAttr(.u32) = null,

        pub fn decode(buf: []const u8) !@This() {
            return genericDecode(@This(), buf);
        }
        pub fn encode(self: @This(), buf: []u8) !usize {
            return genericEncode(@This(), self, buf);
        }
    };

    const OuterEnum = enum(u16) { link = 1, _ };
    const OuterAttrs = struct {
        pub const Enum = OuterEnum;
        link: ?NestedAttr(InnerAttrs) = null,
    };

    var buf: [64]u8 = std.mem.zeroes([64]u8);
    const input = OuterAttrs{ .link = .{ .value = .{ .speed = .{ .value = 1000 } } } };

    const written = try genericEncode(OuterAttrs, input, &buf);
    const result = try genericDecode(OuterAttrs, buf[0..written]);

    try std.testing.expectEqual(@as(u32, 1000), result.link.?.value.speed.?.value);
}
