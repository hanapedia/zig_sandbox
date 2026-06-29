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

pub fn generate(allocator: std.mem.Allocator, writer: *std.Io.Writer, spec: s.Spec) !void {
    try generateDefinitions(allocator, writer, spec.definitions);

    var attr_set_map = try AttributeSetsMap.init(allocator, spec.@"attribute-sets");
    defer attr_set_map.deinit();
    try generateAttributeSetEnums(allocator, writer, attr_set_map);
    // try generateOperations(allocator, writer, spec.operations);
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
    try writer.print("}};\n", .{});
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
    try writer.print("}};\n", .{});
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

    try writer.print("}};\n", .{});
}

const IndexedAttributeSet = struct {
    attr_set: s.AttributeSet,
    attr_map: std.StringHashMap(s.Attribute),
};

const AttributeSetsMap = struct {
    data: std.StringHashMap(IndexedAttributeSet),

    pub fn init(allocator: std.mem.Allocator, attr_sets: []s.AttributeSet) !AttributeSetsMap {
        var attr_set_map = std.StringHashMap(IndexedAttributeSet).init(allocator);
        for (attr_sets) |attr_set| {
            var attr_map = std.StringHashMap(s.Attribute).init(allocator);
            if (attr_set.@"subset-of" == null) {
                if (attr_set.attributes) |attrs| {
                    for (attrs) |attr| {
                        try attr_map.put(attr.name, attr);
                    }
                }
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

pub fn generateAttributeSetEnums(allocator: std.mem.Allocator, writer: *std.Io.Writer, attr_set_map: AttributeSetsMap) !void {
    var it = attr_set_map.data.keyIterator();
    while (it.next()) |attr_set_name| {
        const attr_set = attr_set_map.data.get(attr_set_name.*).?.attr_set;
        const name = try toZigName(allocator, attr_set.name);
        defer allocator.free(name);
        try writer.print("pub const {s} = enum(u16) {{\n", .{name});

        if (attr_set.@"subset-of") |_| {
            const parent = attr_set_map.data.get(attr_set.@"subset-of".?) orelse return error.UnknownParentSet;
            for (attr_set.attributes.?) |attr| {
                const parent_attr = parent.attr_map.get(attr.name) orelse return error.UnknownAttribute;
                try writeAttributeEnumEntry(allocator, writer, parent_attr);
            }
        } else {
            for (attr_set.attributes.?) |attr| {
                try writeAttributeEnumEntry(allocator, writer, attr);
            }
        }
        try writer.print("}};\n", .{});
    }
}

pub fn writeAttributeEnumEntry(allocator: std.mem.Allocator, writer: *std.Io.Writer, attr: s.Attribute) !void {
    const name = try toZigName(allocator, attr.name);
    defer allocator.free(name);
    try indent(writer, 1);
    try writer.print("{s},\n", .{name});
}

// pub fn generateOperations(allocator: std.mem.Allocator, writer: std.Io.Writer, ops: s.Operations) !void {}
