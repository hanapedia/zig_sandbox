/// IP neighbour management over rtnetlink.
const codec = @import("../codec.zig");

pub const ndmsg = extern struct {
    ndm_family: u8,
    ndm_pad: [3]u8,
    ndm_ifindex: i32,
    ndm_state: nud_state,
    ndm_flags: ntf_flags,
    ndm_type: rtm_type,
};

pub const ndtmsg = extern struct {
    family: u8,
    pad: [3]u8,
};

pub const nud_state = packed struct {
    incomplete: bool,
    reachable: bool,
    stale: bool,
    delay: bool,
    probe: bool,
    failed: bool,
    noarp: bool,
    permanent: bool,
    _padding: u24,
};

pub const ntf_flags = packed struct {
    use: bool,
    self: bool,
    master: bool,
    proxy: bool,
    ext_learned: bool,
    offloaded: bool,
    sticky: bool,
    router: bool,
    _padding: u24,
};

pub const ntf_ext_flags = packed struct {
    managed: bool,
    locked: bool,
    ext_validated: bool,
    _padding: u29,
};

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

pub const nda_cacheinfo = extern struct {
    confirmed: u32,
    used: u32,
    updated: u32,
    refcnt: u32,
};

pub const ndt_config = extern struct {
    key_len: u16,
    entry_size: u16,
    entries: u32,
    last_flush: u32,
    last_rand: u32,
    hash_rnd: u32,
    hash_mask: u32,
    hash_chain_gc: u32,
    proxy_qlen: u32,
};

pub const ndt_stats = extern struct {
    allocs: u64,
    destroys: u64,
    hash_grows: u64,
    res_failed: u64,
    lookups: u64,
    hits: u64,
    rcv_probes_mcast: u64,
    rcv_probes_ucast: u64,
    periodic_gc_runs: u64,
    forced_gc_runs: u64,
    table_fulls: u64,
};

pub const ndtpa_attrs_fields = enum(u16) {
    ifindex,
    refcnt,
    reachable_time,
    base_reachable_time,
    retrans_time,
    gc_staletime,
    delay_probe_time,
    queue_len,
    app_probes,
    ucast_probes,
    mcast_probes,
    anycast_delay,
    proxy_delay,
    proxy_qlen,
    locktime,
    queue_lenbytes,
    mcast_reprobes,
    pad,
    interval_probe_time_ms,
};

pub const ndtpa_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = ndtpa_attrs_fields;

    ifindex: codec.ScalarAttr(.u32),
    refcnt: codec.ScalarAttr(.u32),
    reachable_time: codec.ScalarAttr(.u64),
    base_reachable_time: codec.ScalarAttr(.u64),
    retrans_time: codec.ScalarAttr(.u64),
    gc_staletime: codec.ScalarAttr(.u64),
    delay_probe_time: codec.ScalarAttr(.u64),
    queue_len: codec.ScalarAttr(.u32),
    app_probes: codec.ScalarAttr(.u32),
    ucast_probes: codec.ScalarAttr(.u32),
    mcast_probes: codec.ScalarAttr(.u32),
    anycast_delay: codec.ScalarAttr(.u64),
    proxy_delay: codec.ScalarAttr(.u64),
    proxy_qlen: codec.ScalarAttr(.u32),
    locktime: codec.ScalarAttr(.u64),
    queue_lenbytes: codec.ScalarAttr(.u32),
    mcast_reprobes: codec.ScalarAttr(.u32),
    interval_probe_time_ms: codec.ScalarAttr(.u64),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const neighbour_attrs_fields = enum(u16) {
    unspec,
    dst,
    lladdr,
    cacheinfo,
    probes,
    vlan,
    port,
    vni,
    ifindex,
    master,
    link_netnsid,
    src_vni,
    protocol,
    nh_id,
    fdb_ext_attrs,
    flags_ext,
    ndm_state_mask,
    ndm_flags_mask,
};

pub const neighbour_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = neighbour_attrs_fields;

    unspec: codec.ScalarAttr(.binary),
    dst: codec.ScalarAttr(.binary),
    lladdr: codec.ScalarAttr(.binary),
    cacheinfo: codec.ScalarAttr(.binary),
    probes: codec.ScalarAttr(.u32),
    vlan: codec.ScalarAttr(.u16),
    port: codec.ScalarAttr(.u16),
    vni: codec.ScalarAttr(.u32),
    ifindex: codec.ScalarAttr(.u32),
    master: codec.ScalarAttr(.u32),
    link_netnsid: codec.ScalarAttr(.s32),
    src_vni: codec.ScalarAttr(.u32),
    protocol: codec.ScalarAttr(.u8),
    nh_id: codec.ScalarAttr(.u32),
    fdb_ext_attrs: codec.ScalarAttr(.binary),
    flags_ext: codec.EnumAttr(ntf_ext_flags),
    ndm_state_mask: codec.ScalarAttr(.u16),
    ndm_flags_mask: codec.ScalarAttr(.u8),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const ndt_attrs_fields = enum(u16) {
    name,
    thresh1,
    thresh2,
    thresh3,
    config,
    parms,
    stats,
    gc_interval,
    pad,
};

pub const ndt_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = ndt_attrs_fields;

    name: codec.ScalarAttr(.string),
    thresh1: codec.ScalarAttr(.u32),
    thresh2: codec.ScalarAttr(.u32),
    thresh3: codec.ScalarAttr(.u32),
    config: codec.ScalarAttr(.binary),
    parms: codec.NestedAttr(ndtpa_attrs),
    stats: codec.ScalarAttr(.binary),
    gc_interval: codec.ScalarAttr(.u64),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Add new neighbour entry
pub const newneigh_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = neighbour_attrs_fields;

    fixed_header: ndmsg,
    dst: codec.ScalarAttr(.binary),
    lladdr: codec.ScalarAttr(.binary),
    probes: codec.ScalarAttr(.u32),
    vlan: codec.ScalarAttr(.u16),
    port: codec.ScalarAttr(.u16),
    vni: codec.ScalarAttr(.u32),
    ifindex: codec.ScalarAttr(.u32),
    master: codec.ScalarAttr(.u32),
    protocol: codec.ScalarAttr(.u8),
    nh_id: codec.ScalarAttr(.u32),
    flags_ext: codec.EnumAttr(ntf_ext_flags),
    fdb_ext_attrs: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Remove an existing neighbour entry
pub const delneigh_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = neighbour_attrs_fields;

    fixed_header: ndmsg,
    dst: codec.ScalarAttr(.binary),
    ifindex: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get or dump neighbour entries
pub const getneigh_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = neighbour_attrs_fields;

    fixed_header: ndmsg,
    dst: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get or dump neighbour entries
pub const getneigh_do_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = neighbour_attrs_fields;

    fixed_header: ndmsg,
    dst: codec.ScalarAttr(.binary),
    lladdr: codec.ScalarAttr(.binary),
    probes: codec.ScalarAttr(.u32),
    vlan: codec.ScalarAttr(.u16),
    port: codec.ScalarAttr(.u16),
    vni: codec.ScalarAttr(.u32),
    ifindex: codec.ScalarAttr(.u32),
    master: codec.ScalarAttr(.u32),
    protocol: codec.ScalarAttr(.u8),
    nh_id: codec.ScalarAttr(.u32),
    flags_ext: codec.EnumAttr(ntf_ext_flags),
    fdb_ext_attrs: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get or dump neighbour entries
pub const getneigh_dump_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = neighbour_attrs_fields;

    fixed_header: ndmsg,
    ifindex: codec.ScalarAttr(.u32),
    master: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get or dump neighbour entries
pub const getneigh_dump_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = neighbour_attrs_fields;

    fixed_header: ndmsg,
    dst: codec.ScalarAttr(.binary),
    lladdr: codec.ScalarAttr(.binary),
    probes: codec.ScalarAttr(.u32),
    vlan: codec.ScalarAttr(.u16),
    port: codec.ScalarAttr(.u16),
    vni: codec.ScalarAttr(.u32),
    ifindex: codec.ScalarAttr(.u32),
    master: codec.ScalarAttr(.u32),
    protocol: codec.ScalarAttr(.u8),
    nh_id: codec.ScalarAttr(.u32),
    flags_ext: codec.EnumAttr(ntf_ext_flags),
    fdb_ext_attrs: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get or dump neighbour tables
pub const getneightbl_dump_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = ndt_attrs_fields;

    fixed_header: ndtmsg,

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get or dump neighbour tables
pub const getneightbl_dump_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = ndt_attrs_fields;

    fixed_header: ndtmsg,
    name: codec.ScalarAttr(.string),
    thresh1: codec.ScalarAttr(.u32),
    thresh2: codec.ScalarAttr(.u32),
    thresh3: codec.ScalarAttr(.u32),
    config: codec.ScalarAttr(.binary),
    parms: codec.NestedAttr(ndtpa_attrs),
    stats: codec.ScalarAttr(.binary),
    gc_interval: codec.ScalarAttr(.u64),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Set neighbour tables
pub const setneightbl_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = ndt_attrs_fields;

    fixed_header: ndtmsg,
    name: codec.ScalarAttr(.string),
    thresh1: codec.ScalarAttr(.u32),
    thresh2: codec.ScalarAttr(.u32),
    thresh3: codec.ScalarAttr(.u32),
    parms: codec.NestedAttr(ndtpa_attrs),
    gc_interval: codec.ScalarAttr(.u64),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

