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
pub fn decode(comptime T: type, buf: []const u8) !T {
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
            if (@intFromEnum(@field(T.Enum, field.name)) == header.type) {
                @field(result, field.name) = try field.type.decode(value_bytes);
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
pub fn encode(comptime T: type, obj: T, buf: []u8) !usize {
    comptime {
        if (@typeInfo(T) != .@"struct") @compileError("encode requires a struct type");
        if (!@hasDecl(T, "Enum")) @compileError("encode requires T to have a pub const Enum");
    }

    var offset: usize = 0;
    inline for (std.meta.fields(T)) |field_meta| {
        if (offset + @sizeOf(AttrHeader) > buf.len) return error.BufferTooSmall;
        const field = @field(obj, field_meta.name) orelse continue;
        const len = try field.encode(buf[offset + @sizeOf(AttrHeader) ..]);
        const header = AttrHeader{
            .len = @intCast(@sizeOf(AttrHeader) + len),
            .type = @intFromEnum(@field(T.Enum, field_meta.name)),
        };

        @memcpy(buf[offset..][0..@sizeOf(AttrHeader)], std.mem.asBytes(&header)); // write header
        offset += std.mem.alignForward(usize, @sizeOf(AttrHeader) + len, AttrHeader.ALIGNTO);
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
            if (buf.len < @sizeOf(T)) return error.BufferTooSmall;
            const value: T = switch (kind) {
                .u8 => std.mem.readInt(u8, buf[0..@sizeOf(u8)], .little),
                .u16 => std.mem.readInt(u16, buf[0..@sizeOf(u16)], .little),
                .u32 => std.mem.readInt(u32, buf[0..@sizeOf(u32)], .little),
                .u64 => std.mem.readInt(u64, buf[0..@sizeOf(u64)], .little),
                .s32 => std.mem.readInt(i32, buf[0..@sizeOf(i32)], .little),
                .uint => std.mem.readInt(u32, buf[0..@sizeOf(u32)], .little),
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
