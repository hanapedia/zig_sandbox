const std = @import("std");

pub const V4_PREFIX_LENGTH_LEN: usize = 1;
pub const V4_PREFIX_LENGTH_MAX: u8 = 32;

pub const WITHDRAWN_LENGTH_LEN: usize = 2;
pub const TOTAL_PATH_ATTR_LENGTH_LEN: usize = 2;
pub const MIN_MSG_LEN: usize = WITHDRAWN_LENGTH_LEN + TOTAL_PATH_ATTR_LENGTH_LEN;

// path attr TLV consts
pub const PATH_ATTR_FLAGS_LEN: usize = 1;
pub const PATH_ATTR_TYPE_CODE_LEN: usize = 1;
pub const PATH_ATTR_LENGTH_LEN: usize = 1;
pub const PATH_ATTR_EXT_LENGTH_LEN: usize = 2;

pub const PATH_ATTR_ORIGIN_LEN: usize = 1;
pub const PATH_ATTR_NEXT_HOP_LEN: usize = 4;
pub const PATH_ATTR_MED_LEN: usize = 4;
pub const PATH_ATTR_LOCAL_PREF_LEN: usize = 4;

pub const PATH_ATTR_BASIC_FTL_LEN: usize = PATH_ATTR_FLAGS_LEN + PATH_ATTR_TYPE_CODE_LEN + PATH_ATTR_LENGTH_LEN;
pub const PATH_ATTR_ORIGIN_TOTAL_LEN: usize = PATH_ATTR_BASIC_FTL_LEN + PATH_ATTR_ORIGIN_LEN;
pub const PATH_ATTR_NEXT_HOP_TOTAL_LEN: usize = PATH_ATTR_BASIC_FTL_LEN + PATH_ATTR_NEXT_HOP_LEN;
pub const PATH_ATTR_MED_TOTAL_LEN: usize = PATH_ATTR_BASIC_FTL_LEN + PATH_ATTR_MED_LEN;
pub const PATH_ATTR_LOCAL_PREF_TOTAL_LEN: usize = PATH_ATTR_BASIC_FTL_LEN + PATH_ATTR_LOCAL_PREF_LEN;

pub const AS_PATH_SEG_TYPE_LEN: usize = 1;
pub const AS_PATH_SEG_COUNT_LEN: usize = 1;
pub const MIN_AS_PATH_SEG_LEN: usize = AS_PATH_SEG_TYPE_LEN + AS_PATH_SEG_COUNT_LEN;
pub const AS_PATH_ASN_LEN: usize = 4;

pub const V4Prefix = struct {
    len: u8,
    addr: [4]u8,

    /// Number of prefix bytes on the wire.
    /// This is required since only significant bits of the prefix are encoded.
    pub fn octetsNeeded(self: V4Prefix) u8 {
        return std.math.divCeil(u8, self.len, 8) catch unreachable;
    }

    pub fn decode(buf: []const u8) !struct { prefix: V4Prefix, consumed: usize } {
        if (buf.len < V4_PREFIX_LENGTH_LEN) return error.BufferTooSmall;

        var prefix = V4Prefix{ .len = buf[0], .addr = [_]u8{0} ** 4 };
        if (prefix.len > V4_PREFIX_LENGTH_MAX) return error.InvalidPrefixLen;

        // handle 0.0.0.0/0
        if (prefix.len == 0) return .{ .prefix = prefix, .consumed = V4_PREFIX_LENGTH_LEN };

        const octets_needed = prefix.octetsNeeded();
        if (buf.len < octets_needed + V4_PREFIX_LENGTH_LEN) return error.BufferTooSmall;
        @memcpy(prefix.addr[0..octets_needed], buf[V4_PREFIX_LENGTH_LEN .. V4_PREFIX_LENGTH_LEN + octets_needed]);

        return .{ .prefix = prefix, .consumed = V4_PREFIX_LENGTH_LEN + octets_needed };
    }

    pub fn encode(self: V4Prefix, buf: []u8) !usize {
        const octets_needed = self.octetsNeeded();
        if (buf.len < V4_PREFIX_LENGTH_LEN + octets_needed) return error.BufferTooSmall;
        buf[0] = self.len;
        @memcpy(buf[V4_PREFIX_LENGTH_LEN .. V4_PREFIX_LENGTH_LEN + octets_needed], self.addr[0..octets_needed]);
        return V4_PREFIX_LENGTH_LEN + octets_needed;
    }
};

// path attr flags
pub const AttrFlags = packed struct(u8) {
    _unused: u4 = 0, // bits 3-0
    extended_len: bool, // bit 4
    partial: bool, // bit 5
    transitive: bool, // bit 6
    optional: bool, // bit 7
};

/// 0x40
pub fn WellKnownTransitive() AttrFlags {
    return AttrFlags{
        .extended_len = false,
        .partial = false,
        .transitive = true,
        .optional = false,
    };
}

/// 0x80
pub fn OptionalNonTransitive() AttrFlags {
    return AttrFlags{
        .extended_len = false,
        .partial = false,
        .transitive = false,
        .optional = true,
    };
}

pub const PathAttrTypeCode = enum(u8) {
    origin = 1,
    as_path = 2,
    next_hop = 3,
    med = 4,
    local_pref = 5,
    _,
};

pub const Origin = enum(u8) { igp = 0, egp = 1, incomplete = 2, _ };

/// AS_PATH segment types
pub const AsSegType = enum(u8) { as_set = 1, as_sequence = 2, _ };

pub const AsPath = struct {
    sequence: []const u32 = &.{},
    set: ?[]const u32 = null, // only for aggregated routes

    pub fn deinit(self: AsPath, allocator: std.mem.Allocator) void {
        allocator.free(self.sequence);
        if (self.set) |s| allocator.free(s);
    }
};

pub const Update = struct {
    withdrawn: []const V4Prefix,
    origin: ?Origin = null,
    as_path: AsPath,
    next_hop: ?[4]u8 = null,
    med: ?u32 = null,
    local_pref: ?u32 = null,
    nlri: []const V4Prefix,

    /// Decode an UPDATE body. Allocates withdrawn, nlri, as_path, and each
    /// segment's asns slice. Call deinit() to free all of them.
    /// Caller must provide buf exactly as long as the Update body.
    pub fn decode(buf: []const u8, allocator: std.mem.Allocator) !Update {
        if (buf.len < MIN_MSG_LEN) return error.BufferTooSmall;
        var pos: usize = 0;
        var update = Update{
            .withdrawn = &.{},
            .as_path = AsPath{ .sequence = &.{}, .set = null },
            .nlri = &.{},
        };

        // parse withdrawn len
        const withdrawn_len = std.mem.readInt(u16, buf[pos..][0..WITHDRAWN_LENGTH_LEN], .big);
        if (buf.len < MIN_MSG_LEN + withdrawn_len) return error.InvalidLength;
        pos += WITHDRAWN_LENGTH_LEN;

        // parse withdrawn routes
        var withdrawn: std.ArrayList(V4Prefix) = .empty;
        while (pos < WITHDRAWN_LENGTH_LEN + withdrawn_len) {
            const prefix_consumed = try V4Prefix.decode(buf[pos..]);
            try withdrawn.append(allocator, prefix_consumed.prefix);
            pos += prefix_consumed.consumed;
        }
        update.withdrawn = try withdrawn.toOwnedSlice(allocator);

        // parse path attrs
        const path_attrs_len = std.mem.readInt(u16, buf[pos..][0..TOTAL_PATH_ATTR_LENGTH_LEN], .big);
        pos += TOTAL_PATH_ATTR_LENGTH_LEN;
        if (buf.len < pos + path_attrs_len) return error.InvalidLength;
        const pos_copy = pos;
        while (pos < pos_copy + path_attrs_len) {
            // flag
            const flags: AttrFlags = @bitCast(buf[pos]);
            pos += PATH_ATTR_FLAGS_LEN;
            // type code
            const type_code: PathAttrTypeCode = @enumFromInt(buf[pos]);
            pos += PATH_ATTR_TYPE_CODE_LEN;
            // length
            var path_attr_len: u16 = PATH_ATTR_LENGTH_LEN;
            if (flags.extended_len) {
                path_attr_len = std.mem.readInt(u16, buf[pos..][0..PATH_ATTR_EXT_LENGTH_LEN], .big);
                pos += PATH_ATTR_EXT_LENGTH_LEN;
            } else {
                path_attr_len = buf[pos];
                pos += PATH_ATTR_LENGTH_LEN;
            }
            // value
            switch (type_code) {
                .origin => { // origin
                    if (path_attr_len != PATH_ATTR_ORIGIN_LEN) return error.InvalidLength;
                    if (update.origin) |_| return error.DuplicatePathAttr;
                    update.origin = @enumFromInt(buf[pos]);
                    pos += path_attr_len;
                },
                .as_path => { // AS path — inner loop over all segments in the attribute
                    const as_path_end = pos + path_attr_len;
                    while (pos < as_path_end) {
                        if (as_path_end - pos < MIN_AS_PATH_SEG_LEN) return error.InvalidLength;
                        const seg_type: AsSegType = @enumFromInt(buf[pos]);
                        const seg_count: usize = @intCast(buf[pos + AS_PATH_SEG_TYPE_LEN]);
                        pos += MIN_AS_PATH_SEG_LEN;

                        // bound check: seg_count ASNs must fit within the attribute
                        if (pos + seg_count * AS_PATH_ASN_LEN > as_path_end) return error.InvalidLength;

                        // parse ASNs
                        var asns: std.ArrayList(u32) = .empty;
                        for (0..seg_count) |_| {
                            try asns.append(allocator, std.mem.readInt(u32, buf[pos..][0..AS_PATH_ASN_LEN], .big));
                            pos += AS_PATH_ASN_LEN;
                        }

                        switch (seg_type) {
                            .as_sequence => {
                                if (update.as_path.sequence.len > 0) return error.DuplicatePathAttr;
                                update.as_path.sequence = try asns.toOwnedSlice(allocator);
                            },
                            .as_set => {
                                if (update.as_path.set != null) return error.DuplicatePathAttr;
                                update.as_path.set = try asns.toOwnedSlice(allocator);
                            },
                            else => pos += seg_count * AS_PATH_ASN_LEN, // skip unknown segment type
                        }
                    }
                },
                .next_hop => { // next hop
                    if (path_attr_len != PATH_ATTR_NEXT_HOP_LEN) return error.InvalidLength;
                    if (update.next_hop) |_| return error.DuplicatePathAttr;
                    update.next_hop = buf[pos..][0..PATH_ATTR_NEXT_HOP_LEN].*;
                    pos += path_attr_len;
                },
                .med => { // MED
                    if (path_attr_len != PATH_ATTR_MED_LEN) return error.InvalidLength;
                    if (update.med) |_| return error.DuplicatePathAttr;
                    update.med = std.mem.readInt(u32, buf[pos..][0..PATH_ATTR_MED_LEN], .big);
                    pos += path_attr_len;
                },
                .local_pref => { // local pref
                    if (path_attr_len != PATH_ATTR_LOCAL_PREF_LEN) return error.InvalidLength;
                    if (update.local_pref) |_| return error.DuplicatePathAttr;
                    update.local_pref = std.mem.readInt(u32, buf[pos..][0..PATH_ATTR_LOCAL_PREF_LEN], .big);
                    pos += path_attr_len;
                },
                else => {
                    if (flags.optional) pos += path_attr_len;
                    pos += path_attr_len;
                },
            }
        }

        // parse NLRI
        var nlri: std.ArrayList(V4Prefix) = .empty;
        while (pos < buf.len) {
            const prefix_consumed = try V4Prefix.decode(buf[pos..]);
            try nlri.append(allocator, prefix_consumed.prefix);
            pos += prefix_consumed.consumed;
        }
        update.nlri = try nlri.toOwnedSlice(allocator);

        return update;
    }

    /// Free all memory allocated by decode().
    pub fn deinit(self: Update, allocator: std.mem.Allocator) void {
        allocator.free(self.withdrawn);
        allocator.free(self.nlri);
        self.as_path.deinit(allocator);
    }

    /// Encode an UPDATE body into buf. Returns bytes written.
    /// No allocation — reads directly from the struct fields.
    pub fn encode(self: Update, buf: []u8) !usize {
        if (buf.len < MIN_MSG_LEN) return error.BufferTooSmall;
        var pos: usize = 0;
        // withdrawn_len (2)
        var withdrawn_total_len: usize = 0;
        for (self.withdrawn) |prefix| {
            withdrawn_total_len += V4_PREFIX_LENGTH_LEN + prefix.octetsNeeded();
        }
        std.mem.writeInt(u16, buf[pos..][0..WITHDRAWN_LENGTH_LEN], @intCast(withdrawn_total_len), .big);
        pos += WITHDRAWN_LENGTH_LEN;

        // withdrawn_prefix (N)
        if (buf.len < pos + withdrawn_total_len) return error.BufferTooSmall;
        for (self.withdrawn) |prefix| {
            const withdrawn_written = try prefix.encode(buf[pos..]);
            pos += withdrawn_written;
        }

        // total attr len (2)
        if (buf.len < pos + TOTAL_PATH_ATTR_LENGTH_LEN) return error.BufferTooSmall;
        var total_attr_len: usize = 0;
        if (self.origin) |_| total_attr_len += PATH_ATTR_ORIGIN_TOTAL_LEN;
        if (self.next_hop) |_| total_attr_len += PATH_ATTR_NEXT_HOP_TOTAL_LEN;
        if (self.med) |_| total_attr_len += PATH_ATTR_MED_TOTAL_LEN;
        if (self.local_pref) |_| total_attr_len += PATH_ATTR_LOCAL_PREF_TOTAL_LEN;
        if (self.as_path.sequence.len > 0 or self.as_path.set != null) {
            total_attr_len += PATH_ATTR_BASIC_FTL_LEN;
            if (self.as_path.sequence.len > 0) total_attr_len += MIN_AS_PATH_SEG_LEN + AS_PATH_ASN_LEN * self.as_path.sequence.len;
            if (self.as_path.set) |s| total_attr_len += MIN_AS_PATH_SEG_LEN + AS_PATH_ASN_LEN * s.len;
        }
        std.mem.writeInt(u16, buf[pos..][0..TOTAL_PATH_ATTR_LENGTH_LEN], @intCast(total_attr_len), .big);
        pos += TOTAL_PATH_ATTR_LENGTH_LEN;

        if (buf.len < pos + total_attr_len) return error.BufferTooSmall;

        // path attr
        if (self.origin) |o| {
            buf[pos] = @bitCast(WellKnownTransitive()); // flags
            pos += PATH_ATTR_FLAGS_LEN;
            buf[pos] = @intFromEnum(PathAttrTypeCode.origin); // types code
            pos += PATH_ATTR_TYPE_CODE_LEN;
            buf[pos] = PATH_ATTR_ORIGIN_LEN; // len
            pos += PATH_ATTR_LENGTH_LEN;
            buf[pos] = @intFromEnum(o); // val
            pos += PATH_ATTR_ORIGIN_LEN;
        }

        if (self.next_hop) |n| {
            buf[pos] = @bitCast(WellKnownTransitive()); // flags
            pos += PATH_ATTR_FLAGS_LEN;
            buf[pos] = @intFromEnum(PathAttrTypeCode.next_hop); // types code
            pos += PATH_ATTR_TYPE_CODE_LEN;
            buf[pos] = PATH_ATTR_NEXT_HOP_LEN; // len
            pos += PATH_ATTR_LENGTH_LEN;
            @memcpy(buf[pos..][0..PATH_ATTR_NEXT_HOP_LEN], n[0..]); // val
            pos += PATH_ATTR_NEXT_HOP_LEN;
        }

        if (self.med) |m| {
            buf[pos] = @bitCast(OptionalNonTransitive()); // flags
            pos += PATH_ATTR_FLAGS_LEN;
            buf[pos] = @intFromEnum(PathAttrTypeCode.med); // types code
            pos += PATH_ATTR_TYPE_CODE_LEN;
            buf[pos] = PATH_ATTR_MED_LEN; // len
            pos += PATH_ATTR_LENGTH_LEN;
            std.mem.writeInt(u32, buf[pos..][0..PATH_ATTR_MED_LEN], m, .big); // val
            pos += PATH_ATTR_MED_LEN;
        }

        if (self.local_pref) |l| {
            buf[pos] = @bitCast(WellKnownTransitive()); // flags
            pos += PATH_ATTR_FLAGS_LEN;
            buf[pos] = @intFromEnum(PathAttrTypeCode.local_pref); // types code
            pos += PATH_ATTR_TYPE_CODE_LEN;
            buf[pos] = PATH_ATTR_LOCAL_PREF_LEN; // len
            pos += PATH_ATTR_LENGTH_LEN;
            std.mem.writeInt(u32, buf[pos..][0..PATH_ATTR_LOCAL_PREF_LEN], l, .big); // val
            pos += PATH_ATTR_LOCAL_PREF_LEN;
        }

        if (self.as_path.sequence.len > 0 or self.as_path.set != null) {
            buf[pos] = @bitCast(WellKnownTransitive()); // flags
            pos += PATH_ATTR_FLAGS_LEN;
            buf[pos] = @intFromEnum(PathAttrTypeCode.as_path); // types code
            pos += PATH_ATTR_TYPE_CODE_LEN;

            var as_path_value_len: usize = 0;
            if (self.as_path.sequence.len > 0) as_path_value_len += AS_PATH_SEG_TYPE_LEN + AS_PATH_SEG_COUNT_LEN + self.as_path.sequence.len * AS_PATH_ASN_LEN;
            if (self.as_path.set) |s| as_path_value_len += AS_PATH_SEG_TYPE_LEN + AS_PATH_SEG_COUNT_LEN + s.len * AS_PATH_ASN_LEN;
            buf[pos] = @intCast(as_path_value_len);
            pos += PATH_ATTR_LENGTH_LEN;

            // sequence
            if (self.as_path.sequence.len > 0) {
                buf[pos] = @intFromEnum(AsSegType.as_sequence); // seg type
                pos += AS_PATH_SEG_TYPE_LEN;
                buf[pos] = @intCast(self.as_path.sequence.len); // count
                pos += AS_PATH_SEG_COUNT_LEN;
                for (self.as_path.sequence) |asn| {
                    std.mem.writeInt(u32, buf[pos..][0..AS_PATH_ASN_LEN], asn, .big);
                    pos += AS_PATH_ASN_LEN;
                }
            }

            // set
            if (self.as_path.set) |s| {
                buf[pos] = @intFromEnum(AsSegType.as_set); // seg type
                pos += AS_PATH_SEG_TYPE_LEN;
                buf[pos] = @intCast(s.len); // count
                pos += AS_PATH_SEG_COUNT_LEN;
                for (s) |asn| {
                    std.mem.writeInt(u32, buf[pos..][0..AS_PATH_ASN_LEN], asn, .big);
                    pos += AS_PATH_ASN_LEN;
                }
            }
        }

        // nlri
        if (self.nlri.len == 0) return pos;
        var nlri_total_len: usize = 0;
        for (self.nlri) |prefix| {
            nlri_total_len += V4_PREFIX_LENGTH_LEN + prefix.octetsNeeded();
        }
        if (buf.len < pos + nlri_total_len) return error.BufferTooSmall;
        for (self.nlri) |prefix| {
            const nlri_written = try prefix.encode(buf[pos..]);
            pos += nlri_written;
        }
        return pos;
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

test "V4Prefix: octetsNeeded" {
    const p = V4Prefix{ .len = 0, .addr = .{ 0, 0, 0, 0 } };
    try std.testing.expectEqual(@as(u8, 0), p.octetsNeeded());
    try std.testing.expectEqual(@as(u8, 1), (V4Prefix{ .len = 1, .addr = .{ 0, 0, 0, 0 } }).octetsNeeded());
    try std.testing.expectEqual(@as(u8, 1), (V4Prefix{ .len = 8, .addr = .{ 0, 0, 0, 0 } }).octetsNeeded());
    try std.testing.expectEqual(@as(u8, 2), (V4Prefix{ .len = 9, .addr = .{ 0, 0, 0, 0 } }).octetsNeeded());
    try std.testing.expectEqual(@as(u8, 3), (V4Prefix{ .len = 24, .addr = .{ 0, 0, 0, 0 } }).octetsNeeded());
    try std.testing.expectEqual(@as(u8, 4), (V4Prefix{ .len = 32, .addr = .{ 0, 0, 0, 0 } }).octetsNeeded());
}

test "V4Prefix: decode 10.1.0.0/16" {
    // len=16 → 2 prefix bytes; consumed = 1 (len field) + 2 = 3
    const buf = [_]u8{ 0x10, 0x0A, 0x01 };
    const r = try V4Prefix.decode(&buf);
    try std.testing.expectEqual(@as(u8, 16), r.prefix.len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 10, 1, 0, 0 }, &r.prefix.addr);
    try std.testing.expectEqual(@as(usize, 3), r.consumed);
}

test "V4Prefix: decode default route 0.0.0.0/0" {
    // len=0 → 0 prefix bytes; consumed = 1
    const buf = [_]u8{0x00};
    const r = try V4Prefix.decode(&buf);
    try std.testing.expectEqual(@as(u8, 0), r.prefix.len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 0, 0, 0, 0 }, &r.prefix.addr);
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
}

test "V4Prefix: decode 10.1.2.3/32" {
    // len=32 → 4 prefix bytes; consumed = 5
    const buf = [_]u8{ 0x20, 0x0A, 0x01, 0x02, 0x03 };
    const r = try V4Prefix.decode(&buf);
    try std.testing.expectEqual(@as(u8, 32), r.prefix.len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 10, 1, 2, 3 }, &r.prefix.addr);
    try std.testing.expectEqual(@as(usize, 5), r.consumed);
}

test "V4Prefix: encode 10.1.0.0/16" {
    const pref = V4Prefix{ .len = 16, .addr = .{ 10, 1, 0, 0 } };
    var buf = [_]u8{0} ** 8;
    const n = try pref.encode(&buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqual(@as(u8, 0x10), buf[0]); // len=16
    try std.testing.expectEqual(@as(u8, 0x0A), buf[1]); // 10
    try std.testing.expectEqual(@as(u8, 0x01), buf[2]); // 1
}

test "V4Prefix: encode/decode round-trip" {
    const original = V4Prefix{ .len = 24, .addr = .{ 192, 168, 1, 0 } };
    var buf = [_]u8{0} ** 8;
    const n = try original.encode(&buf);
    const r = try V4Prefix.decode(buf[0..n]);
    try std.testing.expectEqual(original.len, r.prefix.len);
    try std.testing.expectEqualSlices(u8, &original.addr, &r.prefix.addr);
}

test "V4Prefix: error on prefix length > 32" {
    const buf = [_]u8{ 0x21, 0x0A }; // len=33
    try std.testing.expectError(error.InvalidPrefixLen, V4Prefix.decode(&buf));
}

test "V4Prefix: error on buffer too small for prefix data" {
    // len=24 → needs 3 prefix bytes, but only 1 byte follows the length field
    const buf = [_]u8{ 0x18, 0x0A };
    try std.testing.expectError(error.BufferTooSmall, V4Prefix.decode(&buf));
}

test "decode: minimal UPDATE — End-of-RIB marker (RFC 4724)" {
    // All-zero UPDATE: no withdrawn, no path attributes, no NLRI.
    const buf = [_]u8{
        0x00, 0x00, // withdrawn_routes_len = 0
        0x00, 0x00, // total_path_attr_len  = 0
        // no NLRI
    };
    const u = try Update.decode(&buf, std.testing.allocator);
    defer u.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), u.withdrawn.len);
    try std.testing.expectEqual(@as(usize, 0), u.nlri.len);
    try std.testing.expectEqual(@as(?Origin, null), u.origin);
    try std.testing.expectEqual(@as(?[4]u8, null), u.next_hop);
}

test "decode: withdrawn-only UPDATE" {
    // Withdraw 10.0.0.0/8 — no path attributes, no NLRI.
    const buf = [_]u8{
        0x00, 0x02, // withdrawn_routes_len = 2
        0x08, 0x0A, // 10.0.0.0/8: len=8, prefix=[0x0A]
        0x00, 0x00, // total_path_attr_len = 0
        // no NLRI
    };
    const u = try Update.decode(&buf, std.testing.allocator);
    defer u.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), u.withdrawn.len);
    try std.testing.expectEqual(@as(u8, 8), u.withdrawn[0].len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 10, 0, 0, 0 }, &u.withdrawn[0].addr);
    try std.testing.expectEqual(@as(usize, 0), u.nlri.len);
}

test "decode: announce prefix with ORIGIN + AS_PATH + NEXT_HOP" {
    // Announce 10.1.0.0/24 with:
    //   ORIGIN = IGP
    //   AS_PATH = AS_SEQUENCE [65001]  (4-byte AS encoding)
    //   NEXT_HOP = 10.0.0.1
    const buf = [_]u8{
        0x00, 0x00, // withdrawn_routes_len = 0
        0x00, 0x14, // total_path_attr_len = 20
        // ORIGIN = IGP (4 bytes)
        0x40, 0x01,
        0x01, 0x00,
        // AS_PATH: AS_SEQUENCE [65001] (9 bytes)
        // flags=0x40 type=0x02 len=6 | seg_type=AS_SEQUENCE count=1 AS=65001
        0x40, 0x02,
        0x06, 0x02,
        0x01, 0x00,
        0x00, 0xFD,
        0xE9,
        // NEXT_HOP = 10.0.0.1 (7 bytes)
        0x40,
        0x03, 0x04,
        0x0A, 0x00,
        0x00, 0x01,
        // NLRI: 10.1.0.0/24
        0x18, 0x0A,
        0x01, 0x00,
    };
    const u = try Update.decode(&buf, std.testing.allocator);
    defer u.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), u.withdrawn.len);
    try std.testing.expectEqual(Origin.igp, u.origin.?);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 10, 0, 0, 1 }, &u.next_hop.?);

    try std.testing.expectEqual(@as(usize, 1), u.as_path.sequence.len);
    try std.testing.expectEqual(@as(u32, 65001), u.as_path.sequence[0]);
    try std.testing.expectEqual(@as(?[]const u32, null), u.as_path.set);

    try std.testing.expectEqual(@as(usize, 1), u.nlri.len);
    try std.testing.expectEqual(@as(u8, 24), u.nlri[0].len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 10, 1, 0, 0 }, &u.nlri[0].addr);
}

test "decode: multiple NLRI prefixes" {
    // Announce 10.1.0.0/24 and 192.168.0.0/16 with minimal required attributes.
    const buf = [_]u8{
        0x00, 0x00, // withdrawn_routes_len = 0
        0x00, 0x14, // total_path_attr_len = 20 (same attrs as above)
        0x40, 0x01, 0x01, 0x00, // ORIGIN = IGP
        0x40, 0x02, 0x06, 0x02, 0x01, 0x00, 0x00, 0xFD, 0xE9, // AS_PATH
        0x40, 0x03, 0x04, 0x0A, 0x00, 0x00, 0x01, // NEXT_HOP
        // NLRI: 10.1.0.0/24
        0x18, 0x0A, 0x01, 0x00,
        // NLRI: 192.168.0.0/16
        0x10, 0xC0, 0xA8,
    };
    const u = try Update.decode(&buf, std.testing.allocator);
    defer u.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), u.nlri.len);
    try std.testing.expectEqual(@as(u8, 24), u.nlri[0].len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 10, 1, 0, 0 }, &u.nlri[0].addr);
    try std.testing.expectEqual(@as(u8, 16), u.nlri[1].len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 192, 168, 0, 0 }, &u.nlri[1].addr);
}

test "decode: MED optional attribute" {
    // Same as announce test but with MED=100 added.
    // MED: flags=0x80 (optional, non-transitive), type=4, len=4, value=100
    const buf = [_]u8{
        0x00, 0x00, // withdrawn_routes_len = 0
        0x00, 0x1B, // total_path_attr_len = 27 (20 + 7 for MED)
        0x40, 0x01, 0x01, 0x00, // ORIGIN = IGP
        0x40, 0x02, 0x06, 0x02, 0x01, 0x00, 0x00, 0xFD, 0xE9, // AS_PATH
        0x40, 0x03, 0x04, 0x0A, 0x00, 0x00, 0x01, // NEXT_HOP
        // MED = 100
        0x80, 0x04, 0x04, 0x00, 0x00, 0x00, 0x64,
        // NLRI: 10.1.0.0/24
        0x18, 0x0A, 0x01, 0x00,
    };
    const u = try Update.decode(&buf, std.testing.allocator);
    defer u.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u32, 100), u.med);
}

test "decode: AS_SEQUENCE with two ASNs" {
    // AS_PATH: one AS_SEQUENCE segment carrying [65001, 65002]
    // segment data: type=2 count=2 AS=65001 AS=65002 = 10 bytes
    // attribute: flags=0x40, type=0x02, len=10 → 13 bytes total
    // total path attr len = 4 (ORIGIN) + 13 (AS_PATH) + 7 (NEXT_HOP) = 24 = 0x18
    const buf = [_]u8{
        0x00, 0x00, // withdrawn_routes_len = 0
        0x00, 0x18, // total_path_attr_len = 24
        0x40, 0x01, 0x01, 0x00, // ORIGIN = IGP
        // AS_PATH: AS_SEQUENCE [65001, 65002] (13 bytes)
        0x40, 0x02, 0x0A, 0x02,
        0x02, 0x00, 0x00, 0xFD,
        0xE9, 0x00, 0x00, 0xFD,
        0xEA,
        0x40, 0x03, 0x04, 0x0A, 0x00, 0x00, 0x01, // NEXT_HOP
        // NLRI: 10.1.0.0/24
        0x18, 0x0A, 0x01, 0x00,
    };
    const u = try Update.decode(&buf, std.testing.allocator);
    defer u.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), u.as_path.sequence.len);
    try std.testing.expectEqual(@as(u32, 65001), u.as_path.sequence[0]);
    try std.testing.expectEqual(@as(u32, 65002), u.as_path.sequence[1]);
    try std.testing.expectEqual(@as(?[]const u32, null), u.as_path.set);
}

test "decode: AS_PATH with both AS_SEQUENCE and AS_SET segments" {
    // Aggregated route: AS_SEQUENCE [65001] followed by AS_SET {65010, 65011}
    // Both segments packed into one AS_PATH attribute.
    //
    // AS_SEQUENCE segment: type=2 count=1 AS=65001          = 6 bytes
    // AS_SET segment:      type=1 count=2 AS=65010 AS=65011 = 10 bytes
    // total segment data = 16 bytes → path_attr_len = 16
    //
    // AS_PATH attribute: flags=0x40 type=0x02 len=16 + 16 bytes = 19 bytes total
    // total path attr len = 4 (ORIGIN) + 19 (AS_PATH) + 7 (NEXT_HOP) = 30 = 0x1E
    const buf = [_]u8{
        0x00, 0x00, // withdrawn_routes_len = 0
        0x00, 0x1E, // total_path_attr_len = 30
        0x40, 0x01, 0x01, 0x00, // ORIGIN = IGP
        // AS_PATH (19 bytes): flags=0x40 type=0x02 len=16
        0x40, 0x02, 0x10,
        // segment 1: AS_SEQUENCE [65001]
        0x02,
        0x01, 0x00, 0x00, 0xFD,
        0xE9,
        // segment 2: AS_SET {65010, 65011}
        0x01, 0x02, 0x00,
        0x00, 0xFD, 0xF2, 0x00,
        0x00, 0xFD, 0xF3,
        0x40, 0x03, 0x04, 0x0A, 0x00, 0x00, 0x01, // NEXT_HOP = 10.0.0.1
        // NLRI: 10.1.0.0/24
        0x18, 0x0A, 0x01, 0x00,
    };
    const u = try Update.decode(&buf, std.testing.allocator);
    defer u.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), u.as_path.sequence.len);
    try std.testing.expectEqual(@as(u32, 65001), u.as_path.sequence[0]);
    try std.testing.expectEqual(@as(usize, 2), u.as_path.set.?.len);
    try std.testing.expectEqual(@as(u32, 65010), u.as_path.set.?[0]);
    try std.testing.expectEqual(@as(u32, 65011), u.as_path.set.?[1]);
}

test "decode: unknown optional attribute is silently skipped" {
    // RFC 4271 §9: unknown optional attributes must be ignored.
    // Unknown attr: flags=0x80 (optional), type=0xFF, len=2, data=0xDEAD
    const buf = [_]u8{
        0x00, 0x00, // withdrawn_routes_len = 0
        0x00, 0x19, // total_path_attr_len = 25 (20 + 5 for unknown)
        0x40, 0x01, 0x01, 0x00, // ORIGIN = IGP
        0x40, 0x02, 0x06, 0x02, 0x01, 0x00, 0x00, 0xFD, 0xE9, // AS_PATH
        0x40, 0x03, 0x04, 0x0A, 0x00, 0x00, 0x01, // NEXT_HOP
        // Unknown optional attribute (must be skipped)
        0x80, 0xFF, 0x02, 0xDE, 0xAD,
        // NLRI
        0x18, 0x0A,
        0x01, 0x00,
    };
    // Must not return an error.
    const u = try Update.decode(&buf, std.testing.allocator);
    defer u.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), u.nlri.len);
}

test "decode: error on buffer shorter than 4 bytes" {
    const buf = [_]u8{ 0x00, 0x00, 0x00 }; // need at least 4
    try std.testing.expectError(error.BufferTooSmall, Update.decode(&buf, std.testing.allocator));
}

test "decode: error when withdrawn_len overruns buffer" {
    const buf = [_]u8{
        0x00, 0x10, // withdrawn_routes_len = 16, but only 2 bytes follow
        0x08, 0x0A,
    };
    try std.testing.expectError(error.InvalidLength, Update.decode(&buf, std.testing.allocator));
}

test "decode: error when path_attr_len overruns buffer" {
    const buf = [_]u8{
        0x00, 0x00, // withdrawn_routes_len = 0
        0x00, 0x10, // total_path_attr_len = 16, but nothing follows
    };
    try std.testing.expectError(error.InvalidLength, Update.decode(&buf, std.testing.allocator));
}

test "encode/decode round-trip: default route withdrawn exposes missing prefix len-byte bug" {
    // 0.0.0.0/0 has octetsNeeded()=0. If withdrawn_total_len omits V4_PREFIX_LENGTH_LEN,
    // it stays 0 and the wire length field is 0, causing decode to skip all withdrawn prefixes.
    const allocator = std.testing.allocator;
    const sequence = [_]u32{65001};
    const original = Update{
        .withdrawn = &[_]V4Prefix{.{ .len = 0, .addr = .{ 0, 0, 0, 0 } }},
        .origin = .igp,
        .as_path = .{ .sequence = &sequence },
        .next_hop = .{ 10, 0, 0, 1 },
        .nlri = &[_]V4Prefix{.{ .len = 24, .addr = .{ 10, 1, 0, 0 } }},
    };
    var buf: [256]u8 = undefined;
    const n = try original.encode(&buf);
    const decoded = try Update.decode(buf[0..n], allocator);
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), decoded.withdrawn.len);
    try std.testing.expectEqual(@as(u8, 0), decoded.withdrawn[0].len);
}

test "encode/decode round-trip" {
    const allocator = std.testing.allocator;

    const sequence = [_]u32{65001};
    const original = Update{
        .withdrawn = &[_]V4Prefix{.{ .len = 8, .addr = .{ 10, 0, 0, 0 } }},
        .origin = .igp,
        .as_path = .{ .sequence = &sequence },
        .next_hop = .{ 10, 0, 0, 1 },
        .med = 200,
        .nlri = &[_]V4Prefix{.{ .len = 24, .addr = .{ 10, 1, 0, 0 } }},
    };

    var buf: [256]u8 = undefined;
    const n = try original.encode(&buf);

    const decoded = try Update.decode(buf[0..n], allocator);
    defer decoded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded.withdrawn.len);
    try std.testing.expectEqual(@as(u8, 8), decoded.withdrawn[0].len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 10, 0, 0, 0 }, &decoded.withdrawn[0].addr);

    try std.testing.expectEqual(original.origin, decoded.origin);
    try std.testing.expectEqualSlices(u8, &original.next_hop.?, &decoded.next_hop.?);
    try std.testing.expectEqual(original.med, decoded.med);

    try std.testing.expectEqual(@as(usize, 1), decoded.as_path.sequence.len);
    try std.testing.expectEqual(@as(u32, 65001), decoded.as_path.sequence[0]);
    try std.testing.expectEqual(@as(?[]const u32, null), decoded.as_path.set);

    try std.testing.expectEqual(@as(usize, 1), decoded.nlri.len);
    try std.testing.expectEqual(@as(u8, 24), decoded.nlri[0].len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 10, 1, 0, 0 }, &decoded.nlri[0].addr);
}
