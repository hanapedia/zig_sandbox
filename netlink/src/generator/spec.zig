/// Type definitions for Netlink yaml specs.
pub const Spec = struct {
    name: []const u8,
    protocol: []const u8,
    @"uapi-header": []const u8,
    protonum: i64,
    doc: []const u8,
    definitions: []Definition,
    @"attribute-sets": []AttributeSet,
    @"sub-messages": ?[]SubMessage = null,
    operations: Operations,
    @"mcast-groups": MCastGroups,
};

pub const Definition = struct {
    name: []const u8,
    type: DefinitionTypes,
    header: ?[]const u8 = null, // unused for now
    @"enum-name": ?[]const u8 = null,
    @"name-prefix": ?[]const u8 = null, // unused
    entries: ?[]Entry = null,
    members: ?[]Member = null,
};

pub const DefinitionTypes = enum {
    @"enum",
    flags,
    @"struct",
};

pub const Entry = struct {
    name: []const u8,
    value: ?i64 = null,
};

pub const Member = struct {
    name: []const u8,
    type: MemberTypes,
    len: ?i64 = null,
    @"enum": ?[]const u8 = null,
    @"enum-as-flags": ?bool = null,
    @"display-hint": ?[]const u8 = null,
    @"byte-order": ?[]const u8 = null,
};

pub const MemberTypes = enum {
    u8,
    u16,
    u32,
    u64,
    s32,
    binary,
    pad,

    pub fn asZigTypeStr(self: MemberTypes) []const u8 {
        return switch (self) {
            .u8 => "u8",
            .u16 => "u16",
            .u32 => "u32",
            .u64 => "u64",
            .s32 => "i32",
            .binary => "[]const u8",
            else => unreachable,
        };
    }
};

pub const AttributeSet = struct {
    name: []const u8,
    @"name-prefix": ?[]const u8 = null, // unused
    @"subset-of": ?[]const u8 = null,
    @"attr-max-name": ?[]const u8 = null, // unused
    attributes: ?[]Attribute = null,
    header: ?[]const u8 = null, // unused
};

pub const Attribute = struct {
    name: []const u8,
    type: ?AttributeTypes = null, // AttributeSet with subset-of do not have types. Use type on the parent
    @"display-hint": ?[]const u8 = null,
    @"struct": ?[]const u8 = null,
    @"nested-attributes": ?[]const u8 = null, // set when type is nest
    @"enum": ?[]const u8 = null,
    @"enum-as-flags": ?bool = null,
    doc: ?[]const u8 = null,
    @"multi-attr": ?bool = null,
    value: ?i64 = null, // ignored for now. mostly for encoding
    @"sub-message": ?[]const u8 = null,
    selector: ?[]const u8 = null,
    @"byte-order": ?[]const u8 = null,
    @"sub-type": ?[]const u8 = null,
    checks: ?Checks = null,
};

pub const AttributeTypes = enum {
    u8,
    u16,
    u32,
    u64,
    s32,
    uint,
    string,
    binary,
    flag,
    nest,
    @"sub-message",
    @"indexed-array",
    pad,

    pub fn asZigType(self: AttributeTypes) type {
        comptime {
            switch (self) {
                .nest, .@"sub-message", .@"indexed-array", .pad => @compileError("asZigType does not support non-scalar type"),
                else => {},
            }
        }
        return switch (self) {
            .u8 => u8,
            .u16 => u16,
            .u32 => u32,
            .u64 => u64,
            .s32 => i32,
            .uint => u32,
            .string => []const u8,
            .binary => []const u8,
            .flag => bool,
            else => unreachable,
        };
    }

    pub fn asZigTypeStr(self: AttributeTypes) ![]const u8 {
        return switch (self) {
            .u8 => "u8",
            .u16 => "u16",
            .u32 => "u32",
            .u64 => "u64",
            .s32 => "i32",
            .uint => "u32",
            .string => "[]const u8",
            .binary => "[]const u8",
            .flag => "bool",
            else => unreachable,
        };
    }
    pub fn asStr(self: AttributeTypes) []const u8 {
        return switch (self) {
            .u8 => ".u8",
            .u16 => ".u16",
            .u32 => ".u32",
            .u64 => ".u64",
            .s32 => ".s32",
            .uint => ".uint",
            .string => ".string",
            .binary => ".binary",
            .flag => ".flag",
            .nest => ".nest",
            .@"sub-message" => ".@\"sub-message\"",
            .@"indexed-array" => ".@\"indexed-array\"",
            .pad => ".pad",
        };
    }
};

pub const Checks = struct {
    @"exact-len": i64,
};

pub const SubMessage = struct {
    name: []const u8,
    formats: []SubMessageFormat,
};

pub const SubMessageFormat = struct {
    value: []const u8,
    @"attribute-set": []const u8,
};

pub const Operations = struct {
    @"enum-model": []const u8,
    @"name-prefix": []const u8,
    list: []Operation,
};

pub const Operation = struct {
    name: []const u8,
    doc: ?[]const u8 = null,
    @"attribute-set": ?[]const u8 = null,
    @"fixed-header": ?[]const u8 = null,
    do: ?Do = null,
    dump: ?Dump = null,
    value: ?i64 = null,
    notify: ?[]const u8 = null,
};

pub const Do = struct {
    request: ?Request = null,
    reply: ?Reply = null,
};

pub const Dump = struct {
    request: ?Request = null,
    reply: ?Reply = null,
};

pub const Request = struct {
    value: i64,
    attributes: ?[]AttributeShort = null,
};

pub const Reply = struct {
    value: i64,
    attributes: []AttributeShort,
};

pub const AttributeShort = struct {
    name: []const u8,
};

pub const MCastGroups = struct {
    list: []MCastGroup,
};

pub const MCastGroup = struct {
    name: []const u8,
    value: i64,
};
