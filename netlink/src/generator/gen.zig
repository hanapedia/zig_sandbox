const std = @import("std");
const s = @import("spec.zig");

pub fn toZigName(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const result = try allocator.dupe(u8, name);
    std.mem.replaceScalar(u8, result, '-', '_');
    if (std.ascii.isDigit(result[0])) {
        defer allocator.free(result);
        return std.fmt.allocPrint(allocator, "@\"{s}\"", .{result});
    }
    return result;
}

fn indent(writer: *std.Io.Writer, level: usize) !void {
    for (0..level) |_| try writer.writeAll("    ");
}

fn writeStructField(writer: *std.Io.Writer, key: []const u8, val: []const u8, level: usize, comment: ?[]const u8) !void {
    if (comment) |c| {
        try indent(writer, level);
        try writer.print("/// {s}\n", .{c});
    }
    try indent(writer, level);
    try writer.print("{s}: {s},\n", .{ key, val });
}

fn writeStructStaticField(writer: *std.Io.Writer, key: []const u8, val: []const u8, level: usize, comment: ?[]const u8) !void {
    if (comment) |c| {
        try indent(writer, level);
        try writer.print("/// {s}\n", .{c});
    }
    try indent(writer, level);
    try writer.print("pub const {s} = {s};\n", .{ key, val });
}

fn writeImports(writer: *std.Io.Writer) !void {
    try writer.print("const codec = @import(\"../codec.zig\");\n\n", .{});
}

fn writeModuleDoc(writer: *std.Io.Writer, doc: ?[]const u8) !void {
    if (doc) |d| try writer.print("/// {s}\n", .{d});
}

fn writeCodecMethods(writer: *std.Io.Writer) !void {
    try indent(writer, 1);
    try writer.print("pub fn decode(buf: []const u8) !@This() {{\n", .{});
    try indent(writer, 2);
    try writer.print("return codec.genericDecode(@This(), buf);\n", .{});
    try indent(writer, 1);
    try writer.print("}}\n\n", .{});

    try indent(writer, 1);
    try writer.print("pub fn encode(self: @This(), buf: []const u8) !usize {{\n", .{});
    try indent(writer, 2);
    try writer.print("return codec.genericEncode(@This(), self, buf);\n", .{});
    try indent(writer, 1);
    try writer.print("}}\n", .{});
}

/// generate zig types for the given netlink spec
pub fn generate(allocator: std.mem.Allocator, writer: *std.Io.Writer, spec: s.Spec) !void {
    try writeModuleDoc(writer, spec.doc);
    try writeImports(writer);
    try generateDefinitions(allocator, writer, spec.definitions);

    var attr_set_map = try AttributeSetsMap.init(allocator, spec.@"attribute-sets");
    defer attr_set_map.deinit();
    try generateAttributeSet(allocator, writer, attr_set_map);
    try generateOperations(allocator, writer, attr_set_map, spec.operations);
}

pub fn generateDefinitions(allocator: std.mem.Allocator, writer: *std.Io.Writer, defs: []s.Definition) !void {
    // loop over defs
    for (defs) |def| {
        switch (def.type) {
            .@"enum" => try writeDefinitionEnum(allocator, writer, def),
            .@"struct" => try writeDefinitionStruct(allocator, writer, def),
            .flags => try writeDefinitionFlags(allocator, writer, def),
        }
    }
}

pub fn writeDefinitionEnum(allocator: std.mem.Allocator, writer: *std.Io.Writer, def: s.Definition) !void {
    if (def.entries == null or def.entries.?.len == 0) return error.InvalidEnumEntries;

    if (def.@"enum-name" != null and !std.mem.eql(u8, def.@"enum-name".?, def.name)) {
        const name = try toZigName(allocator, def.name);
        defer allocator.free(name);
        const enum_name = try toZigName(allocator, def.@"enum-name".?);
        defer allocator.free(enum_name);
        try writer.print("pub const {s} = {s};\n", .{ name, enum_name });
        try writer.print("pub const {s} = enum(u32) {{\n", .{enum_name});
    } else {
        const name = try toZigName(allocator, def.name);
        defer allocator.free(name);
        try writer.print("pub const {s} = enum(u32) {{\n", .{name});
    }

    for (def.entries.?) |entry| {
        const entry_name = try toZigName(allocator, entry.name);
        defer allocator.free(entry_name);
        if (entry.value) |v| {
            try indent(writer, 1);
            try writer.print("{s} = {},\n", .{ entry_name, v });
        } else {
            try indent(writer, 1);
            try writer.print("{s},\n", .{entry_name});
        }
    }
    try writer.print("}};\n\n", .{});
}

pub fn writeDefinitionStruct(allocator: std.mem.Allocator, writer: *std.Io.Writer, def: s.Definition) !void {
    if (def.members == null or def.members.?.len == 0) return error.InvalidStructMembers;

    const name = try toZigName(allocator, def.name);
    defer allocator.free(name);

    try writer.print("pub const {s} = extern struct {{\n", .{name});

    for (def.members.?) |member| {
        const mem_name = try toZigName(allocator, member.name);
        defer allocator.free(mem_name);
        if (member.type == .pad and member.len != null) {
            if (member.len) |l| {
                const mem_type = try std.fmt.allocPrint(allocator, "[{}]u8", .{l});
                defer allocator.free(mem_type);
                try writeStructField(writer, mem_name, mem_type, 1, null);
            } else return error.InvalidPaddingLength;
        } else {
            if (member.@"enum") |e| {
                const mem_type = try toZigName(allocator, e);
                defer allocator.free(mem_type);
                try writeStructField(writer, mem_name, mem_type, 1, null);
            } else {
                try writeStructField(writer, mem_name, member.type.asZigTypeStr(), 1, null);
            }
        }
    }
    try writer.print("}};\n\n", .{});
}

pub fn writeDefinitionFlags(allocator: std.mem.Allocator, writer: *std.Io.Writer, def: s.Definition) !void {
    if (def.entries == null or def.entries.?.len == 0) return error.InvalidEnumEntries;

    if (def.@"enum-name" != null and !std.mem.eql(u8, def.@"enum-name".?, def.name)) {
        const name = try toZigName(allocator, def.name);
        defer allocator.free(name);
        const enum_name = try toZigName(allocator, def.@"enum-name".?);
        defer allocator.free(enum_name);
        try writer.print("pub const {s} = {s};\n", .{ name, enum_name });
        try writer.print("pub const {s} = packed struct {{\n", .{enum_name});
    } else {
        const name = try toZigName(allocator, def.name);
        defer allocator.free(name);
        try writer.print("pub const {s} = packed struct {{\n", .{name});
    }

    for (def.entries.?) |entry| {
        const entry_name = try toZigName(allocator, entry.name);
        defer allocator.free(entry_name);
        try writeStructField(writer, entry_name, "bool", 1, null);
    }
    // write pad
    const pad_type = try std.fmt.allocPrint(allocator, "u{}", .{32 - def.entries.?.len});
    defer allocator.free(pad_type);
    try writeStructField(writer, "_padding", pad_type, 1, null);

    try writer.print("}};\n\n", .{});
}

const IndexedAttributeSet = struct {
    attr_set: s.AttributeSet,
    attr_map: std.StringHashMap(s.Attribute),
};

const AttributeSetsMap = struct {
    data: std.StringHashMap(IndexedAttributeSet),

    // TODO: run the loop twice to fill the subset attributes sets
    pub fn init(allocator: std.mem.Allocator, attr_sets: []s.AttributeSet) !AttributeSetsMap {
        var attr_set_map = std.StringHashMap(IndexedAttributeSet).init(allocator);
        var child_attr_sets: std.ArrayList(s.AttributeSet) = .empty;
        defer child_attr_sets.deinit(allocator);
        for (attr_sets) |attr_set| {
            var attr_map = std.StringHashMap(s.Attribute).init(allocator);
            if (attr_set.@"subset-of" != null) {
                try child_attr_sets.append(allocator, attr_set);
                continue;
            }
            if (attr_set.attributes) |attrs| {
                for (attrs) |attr| {
                    try attr_map.put(attr.name, attr);
                }
            }
            try attr_set_map.put(attr_set.name, .{ .attr_set = attr_set, .attr_map = attr_map });
        }

        for (child_attr_sets.items) |attr_set| {
            var attr_map = std.StringHashMap(s.Attribute).init(allocator);
            const parent = attr_set_map.get(attr_set.@"subset-of".?) orelse return error.UnknownAttributeSet;
            for (attr_set.attributes.?) |attr| {
                const parent_attr = parent.attr_map.get(attr.name) orelse return error.UnknownAttribute;
                try attr_map.put(attr.name, parent_attr);
            }
            try attr_set_map.put(attr_set.name, .{ .attr_set = attr_set, .attr_map = attr_map });
        }
        return .{ .data = attr_set_map };
    }

    pub fn deinit(self: *AttributeSetsMap) void {
        var it = self.data.keyIterator();
        while (it.next()) |key| {
            var val = self.data.get(key.*).?;
            val.attr_map.deinit();
        }
        self.data.deinit();
    }
};

// generates struct definitions for attribute set and enum definitions for attribute set fields.
pub fn generateAttributeSet(allocator: std.mem.Allocator, writer: *std.Io.Writer, attr_set_map: AttributeSetsMap) !void {
    var it = attr_set_map.data.keyIterator();
    while (it.next()) |attr_set_name| {
        const idx_attr_set = attr_set_map.data.get(attr_set_name.*).?;
        const name = try toZigName(allocator, idx_attr_set.attr_set.name);
        defer allocator.free(name);
        const enum_name = try std.fmt.allocPrint(allocator, "{s}_fields", .{name});
        defer allocator.free(enum_name);
        try writer.print("pub const {s} = enum(u16) {{\n", .{enum_name});
        for (idx_attr_set.attr_set.attributes.?) |attr| {
            try writeAttributeEnumEntry(allocator, writer, attr);
        }
        try writer.print("}};\n\n", .{});

        try writer.print("pub const {s} = struct {{\n", .{name});
        // write the Enum field
        try writeStructStaticField(writer, "Enum", enum_name, 1, "enum for mapping attr name to nla_type value");
        try writer.print("\n", .{});

        for (idx_attr_set.attr_set.attributes.?) |_attr| {
            const attr = idx_attr_set.attr_map.get(_attr.name) orelse return error.UnknownAttribute;
            writeAttributeStructEntry(allocator, writer, attr) catch |err| {
                std.debug.print("{s}", .{idx_attr_set.attr_set.name});
                return err;
            };
        }
        // write the generic codec methods
        try writer.print("\n", .{});
        try writeCodecMethods(writer);
        try writer.print("}};\n\n", .{});
    }
}

pub fn writeAttributeEnumEntry(allocator: std.mem.Allocator, writer: *std.Io.Writer, attr: s.Attribute) !void {
    const name = try toZigName(allocator, attr.name);
    defer allocator.free(name);
    try indent(writer, 1);
    try writer.print("{s},\n", .{name});
}

pub fn writeAttributeStructEntry(allocator: std.mem.Allocator, writer: *std.Io.Writer, attr: s.Attribute) !void {
    if (attr.@"enum") |enum_name| {
        try writeAttributeStructEnumField(allocator, writer, attr.name, enum_name, attr.doc);
        return;
    }
    if (attr.type == null) {
        std.debug.print("{}\n\n", .{attr});
        return error.UnknownAttribute;
    }
    switch (attr.type.?) {
        .u8, .u16, .u32, .u64, .s32, .uint, .string, .binary, .flag => |t| try writeAttributeStructScalarField(allocator, writer, attr.name, t, attr.doc),
        .nest => try writeAttributeStructNestedField(allocator, writer, attr.name, attr.@"nested-attributes", attr.doc),
        .pad, .unused => {},
        .@"sub-message", .@"indexed-array" => {},
    }
}

pub fn writeAttributeStructScalarField(allocator: std.mem.Allocator, writer: *std.Io.Writer, _name: []const u8, scalar_type: s.AttributeTypes, doc: ?[]const u8) !void {
    const name = try toZigName(allocator, _name);
    defer allocator.free(name);

    const val = try std.fmt.allocPrint(allocator, "codec.ScalarAttr({s})", .{scalar_type.asStr()});
    defer allocator.free(val);

    try writeStructField(writer, name, val, 1, doc);
}

// TODO: generate with struct type definition not the enum of fields
pub fn writeAttributeStructNestedField(allocator: std.mem.Allocator, writer: *std.Io.Writer, _name: []const u8, _nested_type: ?[]const u8, doc: ?[]const u8) !void {
    if (_nested_type == null) return error.NestedTypeAttrSetNull;
    const name = try toZigName(allocator, _name);
    defer allocator.free(name);

    const nested_type = try toZigName(allocator, _nested_type.?);
    defer allocator.free(nested_type);

    const val = try std.fmt.allocPrint(allocator, "codec.NestedAttr({s})", .{nested_type});
    defer allocator.free(val);

    try writeStructField(writer, name, val, 1, doc);
}

pub fn writeAttributeStructEnumField(allocator: std.mem.Allocator, writer: *std.Io.Writer, _name: []const u8, _enum_name: []const u8, doc: ?[]const u8) !void {
    const name = try toZigName(allocator, _name);
    defer allocator.free(name);

    const enum_name = try toZigName(allocator, _enum_name);
    defer allocator.free(enum_name);

    const val = try std.fmt.allocPrint(allocator, "codec.EnumAttr({s})", .{enum_name});
    defer allocator.free(val);

    try writeStructField(writer, name, val, 1, doc);
}

// TODO: add codec methods
pub fn generateOperations(allocator: std.mem.Allocator, writer: *std.Io.Writer, attr_set_map: AttributeSetsMap, ops: s.Operations) !void {
    for (ops.list) |op| {
        // skip notify for now
        if (op.notify) |_| continue;
        if (op.@"attribute-set" == null) continue;

        const attr_set = attr_set_map.data.get(op.@"attribute-set".?) orelse return error.UnknownAttributeSet;

        // generate req/res types for Do
        if (op.do) |do| {
            if (do.request) |req| {
                try writeOperationStructs(allocator, writer, op.name, attr_set, op.@"fixed-header", req.attributes, "do", "request", op.doc);
            }
            if (do.reply) |reply| {
                try writeOperationStructs(allocator, writer, op.name, attr_set, op.@"fixed-header", reply.attributes, "do", "reply", op.doc);
            }
        }
        // generate req/res types for Dump
        if (op.dump) |dump| {
            if (dump.request) |req| {
                try writeOperationStructs(allocator, writer, op.name, attr_set, op.@"fixed-header", req.attributes, "dump", "request", op.doc);
            }
            if (dump.reply) |reply| {
                try writeOperationStructs(allocator, writer, op.name, attr_set, op.@"fixed-header", reply.attributes, "dump", "reply", op.doc);
            }
        }
    }
}

pub fn writeOperationStructs(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    op_name: []const u8,
    idx_attr_set: IndexedAttributeSet,
    fixed_header: ?[]const u8,
    attr_shorts: ?[]s.AttributeShort,
    op_type: []const u8,
    payload_type: []const u8,
    doc: ?[]const u8,
) !void {
    const _name = try std.fmt.allocPrint(allocator, "{s}_{s}_{s}", .{ op_name, op_type, payload_type });
    defer allocator.free(_name);
    const name = try toZigName(allocator, _name);
    defer allocator.free(name);

    const attr_set_name = try toZigName(allocator, idx_attr_set.attr_set.name);
    defer allocator.free(attr_set_name);
    const enum_name = try std.fmt.allocPrint(allocator, "{s}_fields", .{attr_set_name});
    defer allocator.free(enum_name);

    if (doc) |d| try writer.print("/// {s}\n", .{d});
    try writer.print("pub const {s} = struct {{\n", .{name});
    try writeStructStaticField(writer, "Enum", enum_name, 1, "enum for mapping attr name to nla_type value");
    try writer.print("\n", .{});

    if (fixed_header) |fh| {
        const fh_name = try toZigName(allocator, fh);
        defer allocator.free(fh_name);
        try indent(writer, 1);
        try writer.print("fixed_header: {s},\n", .{fh_name});
    }
    if (attr_shorts) |as| {
        for (as) |attr_short| {
            const attr = idx_attr_set.attr_map.get(attr_short.name) orelse return error.UnknownAttribute;
            try writeAttributeStructEntry(allocator, writer, attr);
        }
    }
    // write generic codec methods
    try writer.print("\n", .{});
    try writeCodecMethods(writer);
    try writer.print("}};\n\n", .{});
}
