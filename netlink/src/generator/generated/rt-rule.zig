/// FIB rule management over rtnetlink.
const codec = @import("../codec.zig");

pub const rtgenmsg = extern struct {
    family: u8,
    pad: [3]u8,
};

pub const fib_rule_hdr = extern struct {
    family: u8,
    dst_len: u8,
    src_len: u8,
    tos: u8,
    table: u8,
    res1: [1]u8,
    res2: [1]u8,
    action: fr_act,
    flags: u32,
};

pub const fr_act = enum(u32) {
    unspec,
    to_tbl,
    goto,
    nop,
    res3,
    res4,
    blackhole,
    unreachable,
    prohibit,
};

pub const fib_rule_port_range = extern struct {
    start: u16,
    end: u16,
};

pub const fib_rule_uid_range = extern struct {
    start: u32,
    end: u32,
};

pub const fib_rule_attrs_fields = enum(u16) {
    dst,
    src,
    iifname,
    goto,
    unused2,
    priority,
    unused3,
    unused4,
    unused5,
    fwmark,
    flow,
    tun_id,
    suppress_ifgroup,
    suppress_prefixlen,
    table,
    fwmask,
    oifname,
    pad,
    l3mdev,
    uid_range,
    protocol,
    ip_proto,
    sport_range,
    dport_range,
    dscp,
    flowlabel,
    flowlabel_mask,
    sport_mask,
    dport_mask,
    dscp_mask,
};

pub const fib_rule_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = fib_rule_attrs_fields;

    dst: codec.ScalarAttr(.binary),
    src: codec.ScalarAttr(.binary),
    iifname: codec.ScalarAttr(.string),
    goto: codec.ScalarAttr(.u32),
    priority: codec.ScalarAttr(.u32),
    fwmark: codec.ScalarAttr(.u32),
    flow: codec.ScalarAttr(.u32),
    tun_id: codec.ScalarAttr(.u64),
    suppress_ifgroup: codec.ScalarAttr(.u32),
    suppress_prefixlen: codec.ScalarAttr(.u32),
    table: codec.ScalarAttr(.u32),
    fwmask: codec.ScalarAttr(.u32),
    oifname: codec.ScalarAttr(.string),
    l3mdev: codec.ScalarAttr(.u8),
    uid_range: codec.ScalarAttr(.binary),
    protocol: codec.ScalarAttr(.u8),
    ip_proto: codec.ScalarAttr(.u8),
    sport_range: codec.ScalarAttr(.binary),
    dport_range: codec.ScalarAttr(.binary),
    dscp: codec.ScalarAttr(.u8),
    flowlabel: codec.ScalarAttr(.u32),
    flowlabel_mask: codec.ScalarAttr(.u32),
    sport_mask: codec.ScalarAttr(.u16),
    dport_mask: codec.ScalarAttr(.u16),
    dscp_mask: codec.ScalarAttr(.u8),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Add new FIB rule
pub const newrule_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = fib_rule_attrs_fields;

    iifname: codec.ScalarAttr(.string),
    oifname: codec.ScalarAttr(.string),
    priority: codec.ScalarAttr(.u32),
    fwmark: codec.ScalarAttr(.u32),
    flow: codec.ScalarAttr(.u32),
    tun_id: codec.ScalarAttr(.u64),
    fwmask: codec.ScalarAttr(.u32),
    table: codec.ScalarAttr(.u32),
    suppress_prefixlen: codec.ScalarAttr(.u32),
    suppress_ifgroup: codec.ScalarAttr(.u32),
    goto: codec.ScalarAttr(.u32),
    l3mdev: codec.ScalarAttr(.u8),
    uid_range: codec.ScalarAttr(.binary),
    protocol: codec.ScalarAttr(.u8),
    ip_proto: codec.ScalarAttr(.u8),
    sport_range: codec.ScalarAttr(.binary),
    dport_range: codec.ScalarAttr(.binary),
    dscp: codec.ScalarAttr(.u8),
    flowlabel: codec.ScalarAttr(.u32),
    flowlabel_mask: codec.ScalarAttr(.u32),
    sport_mask: codec.ScalarAttr(.u16),
    dport_mask: codec.ScalarAttr(.u16),
    dscp_mask: codec.ScalarAttr(.u8),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Remove an existing FIB rule
pub const delrule_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = fib_rule_attrs_fields;

    iifname: codec.ScalarAttr(.string),
    oifname: codec.ScalarAttr(.string),
    priority: codec.ScalarAttr(.u32),
    fwmark: codec.ScalarAttr(.u32),
    flow: codec.ScalarAttr(.u32),
    tun_id: codec.ScalarAttr(.u64),
    fwmask: codec.ScalarAttr(.u32),
    table: codec.ScalarAttr(.u32),
    suppress_prefixlen: codec.ScalarAttr(.u32),
    suppress_ifgroup: codec.ScalarAttr(.u32),
    goto: codec.ScalarAttr(.u32),
    l3mdev: codec.ScalarAttr(.u8),
    uid_range: codec.ScalarAttr(.binary),
    protocol: codec.ScalarAttr(.u8),
    ip_proto: codec.ScalarAttr(.u8),
    sport_range: codec.ScalarAttr(.binary),
    dport_range: codec.ScalarAttr(.binary),
    dscp: codec.ScalarAttr(.u8),
    flowlabel: codec.ScalarAttr(.u32),
    flowlabel_mask: codec.ScalarAttr(.u32),
    sport_mask: codec.ScalarAttr(.u16),
    dport_mask: codec.ScalarAttr(.u16),
    dscp_mask: codec.ScalarAttr(.u8),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Dump all FIB rules
pub const getrule_dump_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = fib_rule_attrs_fields;


    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Dump all FIB rules
pub const getrule_dump_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = fib_rule_attrs_fields;

    iifname: codec.ScalarAttr(.string),
    oifname: codec.ScalarAttr(.string),
    priority: codec.ScalarAttr(.u32),
    fwmark: codec.ScalarAttr(.u32),
    flow: codec.ScalarAttr(.u32),
    tun_id: codec.ScalarAttr(.u64),
    fwmask: codec.ScalarAttr(.u32),
    table: codec.ScalarAttr(.u32),
    suppress_prefixlen: codec.ScalarAttr(.u32),
    suppress_ifgroup: codec.ScalarAttr(.u32),
    goto: codec.ScalarAttr(.u32),
    l3mdev: codec.ScalarAttr(.u8),
    uid_range: codec.ScalarAttr(.binary),
    protocol: codec.ScalarAttr(.u8),
    ip_proto: codec.ScalarAttr(.u8),
    sport_range: codec.ScalarAttr(.binary),
    dport_range: codec.ScalarAttr(.binary),
    dscp: codec.ScalarAttr(.u8),
    flowlabel: codec.ScalarAttr(.u32),
    flowlabel_mask: codec.ScalarAttr(.u32),
    sport_mask: codec.ScalarAttr(.u16),
    dport_mask: codec.ScalarAttr(.u16),
    dscp_mask: codec.ScalarAttr(.u8),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

