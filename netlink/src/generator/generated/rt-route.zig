/// Route configuration over rtnetlink.
const codec = @import("../codec.zig");

pub const rtm_type = enum(u32) {
    unspec,
    unicast,
    local,
    broadcast,
    anycast,
    multicast,
    blackhole,
    unreachable,
    prohibit,
    throw,
    nat,
    xresolve,
};

pub const rtmsg = extern struct {
    rtm_family: u8,
    rtm_dst_len: u8,
    rtm_src_len: u8,
    rtm_tos: u8,
    rtm_table: u8,
    rtm_protocol: u8,
    rtm_scope: u8,
    rtm_type: rtm_type,
    rtm_flags: u32,
};

pub const rta_cacheinfo = extern struct {
    rta_clntref: u32,
    rta_lastuse: u32,
    rta_expires: u32,
    rta_error: u32,
    rta_used: u32,
};

pub const metrics_fields = enum(u16) {
    unspec,
    lock,
    mtu,
    window,
    rtt,
    rttvar,
    ssthresh,
    cwnd,
    advmss,
    reordering,
    hoplimit,
    initcwnd,
    features,
    rto_min,
    initrwnd,
    quickack,
    cc_algo,
    fastopen_no_cookie,
};

pub const metrics = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = metrics_fields;

    lock: codec.ScalarAttr(.u32),
    mtu: codec.ScalarAttr(.u32),
    window: codec.ScalarAttr(.u32),
    rtt: codec.ScalarAttr(.u32),
    rttvar: codec.ScalarAttr(.u32),
    ssthresh: codec.ScalarAttr(.u32),
    cwnd: codec.ScalarAttr(.u32),
    advmss: codec.ScalarAttr(.u32),
    reordering: codec.ScalarAttr(.u32),
    hoplimit: codec.ScalarAttr(.u32),
    initcwnd: codec.ScalarAttr(.u32),
    features: codec.ScalarAttr(.u32),
    rto_min: codec.ScalarAttr(.u32),
    initrwnd: codec.ScalarAttr(.u32),
    quickack: codec.ScalarAttr(.u32),
    cc_algo: codec.ScalarAttr(.string),
    fastopen_no_cookie: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const route_attrs_fields = enum(u16) {
    dst,
    src,
    iif,
    oif,
    gateway,
    priority,
    prefsrc,
    metrics,
    multipath,
    protoinfo,
    flow,
    cacheinfo,
    session,
    mp_algo,
    table,
    mark,
    mfc_stats,
    via,
    newdst,
    pref,
    encap_type,
    encap,
    expires,
    pad,
    uid,
    ttl_propagate,
    ip_proto,
    sport,
    dport,
    nh_id,
    flowlabel,
};

pub const route_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = route_attrs_fields;

    dst: codec.ScalarAttr(.binary),
    src: codec.ScalarAttr(.binary),
    iif: codec.ScalarAttr(.u32),
    oif: codec.ScalarAttr(.u32),
    gateway: codec.ScalarAttr(.binary),
    priority: codec.ScalarAttr(.u32),
    prefsrc: codec.ScalarAttr(.binary),
    metrics: codec.NestedAttr(metrics),
    multipath: codec.ScalarAttr(.binary),
    protoinfo: codec.ScalarAttr(.binary),
    flow: codec.ScalarAttr(.u32),
    cacheinfo: codec.ScalarAttr(.binary),
    session: codec.ScalarAttr(.binary),
    mp_algo: codec.ScalarAttr(.binary),
    table: codec.ScalarAttr(.u32),
    mark: codec.ScalarAttr(.u32),
    mfc_stats: codec.ScalarAttr(.binary),
    via: codec.ScalarAttr(.binary),
    newdst: codec.ScalarAttr(.binary),
    pref: codec.ScalarAttr(.u8),
    encap_type: codec.ScalarAttr(.u16),
    encap: codec.ScalarAttr(.binary),
    expires: codec.ScalarAttr(.u32),
    pad: codec.ScalarAttr(.binary),
    uid: codec.ScalarAttr(.u32),
    ttl_propagate: codec.ScalarAttr(.u8),
    ip_proto: codec.ScalarAttr(.u8),
    sport: codec.ScalarAttr(.u16),
    dport: codec.ScalarAttr(.u16),
    nh_id: codec.ScalarAttr(.u32),
    flowlabel: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Dump route information.
pub const getroute_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = route_attrs_fields;

    src: codec.ScalarAttr(.binary),
    dst: codec.ScalarAttr(.binary),
    iif: codec.ScalarAttr(.u32),
    oif: codec.ScalarAttr(.u32),
    ip_proto: codec.ScalarAttr(.u8),
    sport: codec.ScalarAttr(.u16),
    dport: codec.ScalarAttr(.u16),
    mark: codec.ScalarAttr(.u32),
    uid: codec.ScalarAttr(.u32),
    flowlabel: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Dump route information.
pub const getroute_do_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = route_attrs_fields;

    dst: codec.ScalarAttr(.binary),
    src: codec.ScalarAttr(.binary),
    iif: codec.ScalarAttr(.u32),
    oif: codec.ScalarAttr(.u32),
    gateway: codec.ScalarAttr(.binary),
    priority: codec.ScalarAttr(.u32),
    prefsrc: codec.ScalarAttr(.binary),
    metrics: codec.NestedAttr(metrics),
    multipath: codec.ScalarAttr(.binary),
    flow: codec.ScalarAttr(.u32),
    cacheinfo: codec.ScalarAttr(.binary),
    table: codec.ScalarAttr(.u32),
    mark: codec.ScalarAttr(.u32),
    mfc_stats: codec.ScalarAttr(.binary),
    via: codec.ScalarAttr(.binary),
    newdst: codec.ScalarAttr(.binary),
    pref: codec.ScalarAttr(.u8),
    encap_type: codec.ScalarAttr(.u16),
    encap: codec.ScalarAttr(.binary),
    expires: codec.ScalarAttr(.u32),
    pad: codec.ScalarAttr(.binary),
    uid: codec.ScalarAttr(.u32),
    ttl_propagate: codec.ScalarAttr(.u8),
    ip_proto: codec.ScalarAttr(.u8),
    sport: codec.ScalarAttr(.u16),
    dport: codec.ScalarAttr(.u16),
    nh_id: codec.ScalarAttr(.u32),
    flowlabel: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Dump route information.
pub const getroute_dump_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = route_attrs_fields;


    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Dump route information.
pub const getroute_dump_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = route_attrs_fields;

    dst: codec.ScalarAttr(.binary),
    src: codec.ScalarAttr(.binary),
    iif: codec.ScalarAttr(.u32),
    oif: codec.ScalarAttr(.u32),
    gateway: codec.ScalarAttr(.binary),
    priority: codec.ScalarAttr(.u32),
    prefsrc: codec.ScalarAttr(.binary),
    metrics: codec.NestedAttr(metrics),
    multipath: codec.ScalarAttr(.binary),
    flow: codec.ScalarAttr(.u32),
    cacheinfo: codec.ScalarAttr(.binary),
    table: codec.ScalarAttr(.u32),
    mark: codec.ScalarAttr(.u32),
    mfc_stats: codec.ScalarAttr(.binary),
    via: codec.ScalarAttr(.binary),
    newdst: codec.ScalarAttr(.binary),
    pref: codec.ScalarAttr(.u8),
    encap_type: codec.ScalarAttr(.u16),
    encap: codec.ScalarAttr(.binary),
    expires: codec.ScalarAttr(.u32),
    pad: codec.ScalarAttr(.binary),
    uid: codec.ScalarAttr(.u32),
    ttl_propagate: codec.ScalarAttr(.u8),
    ip_proto: codec.ScalarAttr(.u8),
    sport: codec.ScalarAttr(.u16),
    dport: codec.ScalarAttr(.u16),
    nh_id: codec.ScalarAttr(.u32),
    flowlabel: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Create a new route
pub const newroute_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = route_attrs_fields;

    dst: codec.ScalarAttr(.binary),
    src: codec.ScalarAttr(.binary),
    iif: codec.ScalarAttr(.u32),
    oif: codec.ScalarAttr(.u32),
    gateway: codec.ScalarAttr(.binary),
    priority: codec.ScalarAttr(.u32),
    prefsrc: codec.ScalarAttr(.binary),
    metrics: codec.NestedAttr(metrics),
    multipath: codec.ScalarAttr(.binary),
    flow: codec.ScalarAttr(.u32),
    cacheinfo: codec.ScalarAttr(.binary),
    table: codec.ScalarAttr(.u32),
    mark: codec.ScalarAttr(.u32),
    mfc_stats: codec.ScalarAttr(.binary),
    via: codec.ScalarAttr(.binary),
    newdst: codec.ScalarAttr(.binary),
    pref: codec.ScalarAttr(.u8),
    encap_type: codec.ScalarAttr(.u16),
    encap: codec.ScalarAttr(.binary),
    expires: codec.ScalarAttr(.u32),
    pad: codec.ScalarAttr(.binary),
    uid: codec.ScalarAttr(.u32),
    ttl_propagate: codec.ScalarAttr(.u8),
    ip_proto: codec.ScalarAttr(.u8),
    sport: codec.ScalarAttr(.u16),
    dport: codec.ScalarAttr(.u16),
    nh_id: codec.ScalarAttr(.u32),
    flowlabel: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Delete an existing route
pub const delroute_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = route_attrs_fields;

    dst: codec.ScalarAttr(.binary),
    src: codec.ScalarAttr(.binary),
    iif: codec.ScalarAttr(.u32),
    oif: codec.ScalarAttr(.u32),
    gateway: codec.ScalarAttr(.binary),
    priority: codec.ScalarAttr(.u32),
    prefsrc: codec.ScalarAttr(.binary),
    metrics: codec.NestedAttr(metrics),
    multipath: codec.ScalarAttr(.binary),
    flow: codec.ScalarAttr(.u32),
    cacheinfo: codec.ScalarAttr(.binary),
    table: codec.ScalarAttr(.u32),
    mark: codec.ScalarAttr(.u32),
    mfc_stats: codec.ScalarAttr(.binary),
    via: codec.ScalarAttr(.binary),
    newdst: codec.ScalarAttr(.binary),
    pref: codec.ScalarAttr(.u8),
    encap_type: codec.ScalarAttr(.u16),
    encap: codec.ScalarAttr(.binary),
    expires: codec.ScalarAttr(.u32),
    pad: codec.ScalarAttr(.binary),
    uid: codec.ScalarAttr(.u32),
    ttl_propagate: codec.ScalarAttr(.u8),
    ip_proto: codec.ScalarAttr(.u8),
    sport: codec.ScalarAttr(.u16),
    dport: codec.ScalarAttr(.u16),
    nh_id: codec.ScalarAttr(.u32),
    flowlabel: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

