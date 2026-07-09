/// Address configuration over rtnetlink.
const codec = @import("../codec.zig");

pub const ifaddrmsg = extern struct {
    ifa_family: u8,
    ifa_prefixlen: u8,
    ifa_flags: ifa_flags,
    ifa_scope: u8,
    ifa_index: u32,
};

pub const ifa_cacheinfo = extern struct {
    ifa_prefered: u32,
    ifa_valid: u32,
    cstamp: u32,
    tstamp: u32,
};

pub const ifa_flags = packed struct {
    secondary: bool,
    nodad: bool,
    optimistic: bool,
    dadfailed: bool,
    homeaddress: bool,
    deprecated: bool,
    tentative: bool,
    permanent: bool,
    managetempaddr: bool,
    noprefixroute: bool,
    mcautojoin: bool,
    stable_privacy: bool,
    _padding: u20,
};

pub const addr_attrs_fields = enum(u16) {
    address,
    local,
    label,
    broadcast,
    anycast,
    cacheinfo,
    multicast,
    flags,
    rt_priority,
    target_netnsid,
    proto,
};

pub const addr_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = addr_attrs_fields;

    address: codec.ScalarAttr(.binary),
    local: codec.ScalarAttr(.binary),
    label: codec.ScalarAttr(.string),
    broadcast: codec.ScalarAttr(.u32),
    anycast: codec.ScalarAttr(.binary),
    cacheinfo: codec.ScalarAttr(.binary),
    multicast: codec.ScalarAttr(.binary),
    flags: codec.EnumAttr(ifa_flags),
    rt_priority: codec.ScalarAttr(.u32),
    target_netnsid: codec.ScalarAttr(.binary),
    proto: codec.ScalarAttr(.u8),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Add new address
pub const newaddr_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = addr_attrs_fields;

    address: codec.ScalarAttr(.binary),
    label: codec.ScalarAttr(.string),
    local: codec.ScalarAttr(.binary),
    cacheinfo: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Remove address
pub const deladdr_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = addr_attrs_fields;

    address: codec.ScalarAttr(.binary),
    local: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Dump address information.
pub const getaddr_dump_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = addr_attrs_fields;


    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Dump address information.
pub const getaddr_dump_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = addr_attrs_fields;

    address: codec.ScalarAttr(.binary),
    label: codec.ScalarAttr(.string),
    local: codec.ScalarAttr(.binary),
    cacheinfo: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump IPv4/IPv6 multicast addresses.
pub const getmulticast_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = addr_attrs_fields;

    fixed_header: ifaddrmsg,

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump IPv4/IPv6 multicast addresses.
pub const getmulticast_do_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = addr_attrs_fields;

    fixed_header: ifaddrmsg,
    multicast: codec.ScalarAttr(.binary),
    cacheinfo: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump IPv4/IPv6 multicast addresses.
pub const getmulticast_dump_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = addr_attrs_fields;

    fixed_header: ifaddrmsg,

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump IPv4/IPv6 multicast addresses.
pub const getmulticast_dump_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = addr_attrs_fields;

    fixed_header: ifaddrmsg,
    multicast: codec.ScalarAttr(.binary),
    cacheinfo: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

