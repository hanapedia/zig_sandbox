/// Link configuration over rtnetlink.
const codec = @import("../codec.zig");

pub const ifinfo_flags = net_device_flags;
pub const net_device_flags = packed struct {
    up: bool,
    broadcast: bool,
    debug: bool,
    loopback: bool,
    point_to_point: bool,
    no_trailers: bool,
    running: bool,
    no_arp: bool,
    promisc: bool,
    all_multi: bool,
    master: bool,
    slave: bool,
    multicast: bool,
    portsel: bool,
    auto_media: bool,
    dynamic: bool,
    lower_up: bool,
    dormant: bool,
    echo: bool,
    _padding: u13,
};

pub const vlan_protocols = enum(u32) {
    @"8021q" = 33024,
    @"8021ad" = 34984,
};

pub const rtgenmsg = extern struct {
    family: u8,
};

pub const ifinfomsg = extern struct {
    ifi_family: u8,
    pad: [1]u8,
    ifi_type: u16,
    ifi_index: i32,
    ifi_flags: ifinfo_flags,
    ifi_change: u32,
};

pub const ifla_bridge_id = extern struct {
    prio: u16,
    addr: []const u8,
};

pub const ifla_cacheinfo = extern struct {
    max_reasm_len: u32,
    tstamp: u32,
    reachable_time: i32,
    retrans_time: u32,
};

pub const rtnl_link_stats = extern struct {
    rx_packets: u32,
    tx_packets: u32,
    rx_bytes: u32,
    tx_bytes: u32,
    rx_errors: u32,
    tx_errors: u32,
    rx_dropped: u32,
    tx_dropped: u32,
    multicast: u32,
    collisions: u32,
    rx_length_errors: u32,
    rx_over_errors: u32,
    rx_crc_errors: u32,
    rx_frame_errors: u32,
    rx_fifo_errors: u32,
    rx_missed_errors: u32,
    tx_aborted_errors: u32,
    tx_carrier_errors: u32,
    tx_fifo_errors: u32,
    tx_heartbeat_errors: u32,
    tx_window_errors: u32,
    rx_compressed: u32,
    tx_compressed: u32,
    rx_nohandler: u32,
};

pub const rtnl_link_stats64 = extern struct {
    rx_packets: u64,
    tx_packets: u64,
    rx_bytes: u64,
    tx_bytes: u64,
    rx_errors: u64,
    tx_errors: u64,
    rx_dropped: u64,
    tx_dropped: u64,
    multicast: u64,
    collisions: u64,
    rx_length_errors: u64,
    rx_over_errors: u64,
    rx_crc_errors: u64,
    rx_frame_errors: u64,
    rx_fifo_errors: u64,
    rx_missed_errors: u64,
    tx_aborted_errors: u64,
    tx_carrier_errors: u64,
    tx_fifo_errors: u64,
    tx_heartbeat_errors: u64,
    tx_window_errors: u64,
    rx_compressed: u64,
    tx_compressed: u64,
    rx_nohandler: u64,
    rx_otherhost_dropped: u64,
};

pub const rtnl_link_ifmap = extern struct {
    mem_start: u64,
    mem_end: u64,
    base_addr: u64,
    irq: u16,
    dma: u8,
    port: u8,
};

pub const ipv4_devconf = enum(u32) {
    forwarding,
    mc_forwarding,
    proxy_arp,
    accept_redirects,
    secure_redirects,
    send_redirects,
    shared_media,
    rp_filter,
    accept_source_route,
    bootp_relay,
    log_martians,
    tag,
    arpfilter,
    medium_id,
    noxfrm,
    nopolicy,
    force_igmp_version,
    arp_announce,
    arp_ignore,
    promote_secondaries,
    arp_accept,
    arp_notify,
    accept_local,
    src_vmark,
    proxy_arp_pvlan,
    route_localnet,
    igmpv2_unsolicited_report_interval,
    igmpv3_unsolicited_report_interval,
    ignore_routes_with_linkdown,
    drop_unicast_in_l2_multicast,
    drop_gratuitous_arp,
    bc_forwarding,
    arp_evict_nocarrier,
};

pub const ipv6_devconf = enum(u32) {
    forwarding,
    hoplimit,
    mtu6,
    accept_ra,
    accept_redirects,
    autoconf,
    dad_transmits,
    rtr_solicits,
    rtr_solicit_interval,
    rtr_solicit_delay,
    use_tempaddr,
    temp_valid_lft,
    temp_prefered_lft,
    regen_max_retry,
    max_desync_factor,
    max_addresses,
    force_mld_version,
    accept_ra_defrtr,
    accept_ra_pinfo,
    accept_ra_rtr_pref,
    rtr_probe_interval,
    accept_ra_rt_info_max_plen,
    proxy_ndp,
    optimistic_dad,
    accept_source_route,
    mc_forwarding,
    disable_ipv6,
    accept_dad,
    force_tllao,
    ndisc_notify,
    mldv1_unsolicited_report_interval,
    mldv2_unsolicited_report_interval,
    suppress_frag_ndisc,
    accept_ra_from_local,
    use_optimistic,
    accept_ra_mtu,
    stable_secret,
    use_oif_addrs_only,
    accept_ra_min_hop_limit,
    ignore_routes_with_linkdown,
    drop_unicast_in_l2_multicast,
    drop_unsolicited_na,
    keep_addr_on_down,
    rtr_solicit_max_interval,
    seg6_enabled,
    seg6_require_hmac,
    enhanced_dad,
    addr_gen_mode,
    disable_policy,
    accept_ra_rt_info_min_plen,
    ndisc_tclass,
    rpl_seg_enabled,
    ra_defrtr_metric,
    ioam6_enabled,
    ioam6_id,
    ioam6_id_wide,
    ndisc_evict_nocarrier,
    accept_untracked_na,
};

pub const ifla_icmp6_stats = enum(u32) {
    num,
    inmsgs,
    inerrors,
    outmsgs,
    outerrors,
    csumerrors,
    ratelimithost,
};

pub const ifla_inet6_stats = enum(u32) {
    num,
    inpkts,
    inoctets,
    indelivers,
    outforwdatagrams,
    outpkts,
    outoctets,
    inhdrerrors,
    intoobigerrors,
    innoroutes,
    inaddrerrors,
    inunknownprotos,
    intruncatedpkts,
    indiscards,
    outdiscards,
    outnoroutes,
    reasmtimeout,
    reasmreqds,
    reasmoks,
    reasmfails,
    fragoks,
    fragfails,
    fragcreates,
    inmcastpkts,
    outmcastpkts,
    inbcastpkts,
    outbcastpkts,
    inmcastoctets,
    outmcastoctets,
    inbcastoctets,
    outbcastoctets,
    csumerrors,
    noectpkts,
    ect1_pkts,
    ect0_pkts,
    cepkts,
    reasm_overlaps,
};

pub const br_boolopt_multi = extern struct {
    optval: u32,
    optmask: u32,
};

pub const if_stats_msg = extern struct {
    family: u8,
    pad: [3]u8,
    ifindex: u32,
    filter_mask: u32,
};

pub const ifla_vlan_flags = extern struct {
    flags: vlan_flags,
    mask: u32,
};

pub const vlan_flags = packed struct {
    reorder_hdr: bool,
    gvrp: bool,
    loose_binding: bool,
    mvrp: bool,
    bridge_binding: bool,
    _padding: u27,
};

pub const ifla_vlan_qos_mapping = extern struct {
    from: u32,
    to: u32,
};

pub const ifla_geneve_port_range = extern struct {
    low: u16,
    high: u16,
};

pub const ifla_vf_mac = extern struct {
    vf: u32,
    mac: []const u8,
};

pub const ifla_vf_vlan = extern struct {
    vf: u32,
    vlan: u32,
    qos: u32,
};

pub const ifla_vf_tx_rate = extern struct {
    vf: u32,
    rate: u32,
};

pub const ifla_vf_spoofchk = extern struct {
    vf: u32,
    setting: u32,
};

pub const ifla_vf_link_state = extern struct {
    vf: u32,
    link_state: ifla_vf_link_state_enum,
};

pub const ifla_vf_link_state_enum = enum(u32) {
    auto,
    enable,
    disable,
};

pub const ifla_vf_rate = extern struct {
    vf: u32,
    min_tx_rate: u32,
    max_tx_rate: u32,
};

pub const ifla_vf_rss_query_en = extern struct {
    vf: u32,
    setting: u32,
};

pub const ifla_vf_trust = extern struct {
    vf: u32,
    setting: u32,
};

pub const ifla_vf_guid = extern struct {
    vf: u32,
    guid: u64,
};

pub const ifla_vf_vlan_info = extern struct {
    vf: u32,
    vlan: u32,
    qos: u32,
    vlan_proto: u32,
};

pub const rtext_filter = packed struct {
    vf: bool,
    brvlan: bool,
    brvlan_compressed: bool,
    skip_stats: bool,
    mrp: bool,
    cfm_config: bool,
    cfm_status: bool,
    mst: bool,
    _padding: u24,
};

pub const netkit_policy = enum(u32) {
    forward = 0,
    blackhole = 2,
};

pub const netkit_mode = enum(u32) {
    l2,
    l3,
};

pub const netkit_scrub = enum(u32) {
    none,
    default,
};

pub const netkit_pairing = enum(u32) {
    pair,
    single,
};

pub const ovpn_mode = enum(u32) {
    p2p,
    mp,
};

pub const br_stp_mode = enum(u32) {
    auto,
    user,
    kernel,
};

pub const bond_ad_info_attrs_fields = enum(u16) {
    aggregator,
    num_ports,
    actor_key,
    partner_key,
    partner_mac,
};

pub const bond_ad_info_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = bond_ad_info_attrs_fields;

    aggregator: codec.ScalarAttr(.u16),
    num_ports: codec.ScalarAttr(.u16),
    actor_key: codec.ScalarAttr(.u16),
    partner_key: codec.ScalarAttr(.u16),
    partner_mac: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_tun_attrs_fields = enum(u16) {
    owner,
    group,
    type,
    pi,
    vnet_hdr,
    persist,
    multi_queue,
    num_queues,
    num_disabled_queues,
};

pub const linkinfo_tun_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_tun_attrs_fields;

    owner: codec.ScalarAttr(.u32),
    group: codec.ScalarAttr(.u32),
    type: codec.ScalarAttr(.u8),
    pi: codec.ScalarAttr(.u8),
    vnet_hdr: codec.ScalarAttr(.u8),
    persist: codec.ScalarAttr(.u8),
    multi_queue: codec.ScalarAttr(.u8),
    num_queues: codec.ScalarAttr(.u32),
    num_disabled_queues: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_gre6_attrs_fields = enum(u16) {
    link,
    iflags,
    oflags,
    ikey,
    okey,
    local,
    remote,
    ttl,
    encap_limit,
    flowinfo,
    flags,
    encap_type,
    encap_flags,
    encap_sport,
    encap_dport,
    collect_metadata,
    fwmark,
    erspan_index,
    erspan_ver,
    erspan_dir,
    erspan_hwid,
};

pub const linkinfo_gre6_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_gre6_attrs_fields;

    link: codec.ScalarAttr(.u32),
    iflags: codec.ScalarAttr(.u16),
    oflags: codec.ScalarAttr(.u16),
    ikey: codec.ScalarAttr(.u32),
    okey: codec.ScalarAttr(.u32),
    local: codec.ScalarAttr(.binary),
    remote: codec.ScalarAttr(.binary),
    ttl: codec.ScalarAttr(.u8),
    encap_limit: codec.ScalarAttr(.u8),
    flowinfo: codec.ScalarAttr(.u32),
    flags: codec.ScalarAttr(.u32),
    encap_type: codec.ScalarAttr(.u16),
    encap_flags: codec.ScalarAttr(.u16),
    encap_sport: codec.ScalarAttr(.u16),
    encap_dport: codec.ScalarAttr(.u16),
    collect_metadata: codec.ScalarAttr(.flag),
    fwmark: codec.ScalarAttr(.u32),
    erspan_index: codec.ScalarAttr(.u32),
    erspan_ver: codec.ScalarAttr(.u8),
    erspan_dir: codec.ScalarAttr(.u8),
    erspan_hwid: codec.ScalarAttr(.u16),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const ifla_vlan_qos_fields = enum(u16) {
    mapping,
};

pub const ifla_vlan_qos = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = ifla_vlan_qos_fields;

    mapping: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_iptun_attrs_fields = enum(u16) {
    link,
    local,
    remote,
    ttl,
    tos,
    encap_limit,
    flowinfo,
    flags,
    proto,
    pmtudisc,
    @"6rd_prefix",
    @"6rd_relay_prefix",
    @"6rd_prefixlen",
    @"6rd_relay_prefixlen",
    encap_type,
    encap_flags,
    encap_sport,
    encap_dport,
    collect_metadata,
    fwmark,
};

pub const linkinfo_iptun_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_iptun_attrs_fields;

    link: codec.ScalarAttr(.u32),
    local: codec.ScalarAttr(.binary),
    remote: codec.ScalarAttr(.binary),
    ttl: codec.ScalarAttr(.u8),
    tos: codec.ScalarAttr(.u8),
    encap_limit: codec.ScalarAttr(.u8),
    flowinfo: codec.ScalarAttr(.u32),
    flags: codec.ScalarAttr(.u16),
    proto: codec.ScalarAttr(.u8),
    pmtudisc: codec.ScalarAttr(.u8),
    @"6rd_prefix": codec.ScalarAttr(.binary),
    @"6rd_relay_prefix": codec.ScalarAttr(.u32),
    @"6rd_prefixlen": codec.ScalarAttr(.u16),
    @"6rd_relay_prefixlen": codec.ScalarAttr(.u16),
    encap_type: codec.ScalarAttr(.u16),
    encap_flags: codec.ScalarAttr(.u16),
    encap_sport: codec.ScalarAttr(.u16),
    encap_dport: codec.ScalarAttr(.u16),
    collect_metadata: codec.ScalarAttr(.flag),
    fwmark: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const vf_ports_attrs_fields = enum(u16) {
};

pub const vf_ports_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = vf_ports_attrs_fields;


    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const bond_slave_attrs_fields = enum(u16) {
    state,
    mii_status,
    link_failure_count,
    perm_hwaddr,
    queue_id,
    ad_aggregator_id,
    ad_actor_oper_port_state,
    ad_partner_oper_port_state,
    prio,
};

pub const bond_slave_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = bond_slave_attrs_fields;

    state: codec.ScalarAttr(.u8),
    mii_status: codec.ScalarAttr(.u8),
    link_failure_count: codec.ScalarAttr(.u32),
    perm_hwaddr: codec.ScalarAttr(.binary),
    queue_id: codec.ScalarAttr(.u16),
    ad_aggregator_id: codec.ScalarAttr(.u16),
    ad_actor_oper_port_state: codec.ScalarAttr(.u8),
    ad_partner_oper_port_state: codec.ScalarAttr(.u16),
    prio: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_bond_attrs_fields = enum(u16) {
    mode,
    active_slave,
    miimon,
    updelay,
    downdelay,
    use_carrier,
    arp_interval,
    arp_ip_target,
    arp_validate,
    arp_all_targets,
    primary,
    primary_reselect,
    fail_over_mac,
    xmit_hash_policy,
    resend_igmp,
    num_peer_notif,
    all_slaves_active,
    min_links,
    lp_interval,
    packets_per_slave,
    ad_lacp_rate,
    ad_select,
    ad_info,
    ad_actor_sys_prio,
    ad_user_port_key,
    ad_actor_system,
    tlb_dynamic_lb,
    peer_notif_delay,
    ad_lacp_active,
    missed_max,
    ns_ip6_target,
    coupled_control,
};

pub const linkinfo_bond_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_bond_attrs_fields;

    mode: codec.ScalarAttr(.u8),
    active_slave: codec.ScalarAttr(.u32),
    miimon: codec.ScalarAttr(.u32),
    updelay: codec.ScalarAttr(.u32),
    downdelay: codec.ScalarAttr(.u32),
    use_carrier: codec.ScalarAttr(.u8),
    arp_interval: codec.ScalarAttr(.u32),
    arp_validate: codec.ScalarAttr(.u32),
    arp_all_targets: codec.ScalarAttr(.u32),
    primary: codec.ScalarAttr(.u32),
    primary_reselect: codec.ScalarAttr(.u8),
    fail_over_mac: codec.ScalarAttr(.u8),
    xmit_hash_policy: codec.ScalarAttr(.u8),
    resend_igmp: codec.ScalarAttr(.u32),
    num_peer_notif: codec.ScalarAttr(.u8),
    all_slaves_active: codec.ScalarAttr(.u8),
    min_links: codec.ScalarAttr(.u32),
    lp_interval: codec.ScalarAttr(.u32),
    packets_per_slave: codec.ScalarAttr(.u32),
    ad_lacp_rate: codec.ScalarAttr(.u8),
    ad_select: codec.ScalarAttr(.u8),
    ad_info: codec.NestedAttr(bond_ad_info_attrs),
    ad_actor_sys_prio: codec.ScalarAttr(.u16),
    ad_user_port_key: codec.ScalarAttr(.u16),
    ad_actor_system: codec.ScalarAttr(.binary),
    tlb_dynamic_lb: codec.ScalarAttr(.u8),
    peer_notif_delay: codec.ScalarAttr(.u32),
    ad_lacp_active: codec.ScalarAttr(.u8),
    missed_max: codec.ScalarAttr(.u8),
    coupled_control: codec.ScalarAttr(.u8),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_brport_attrs_fields = enum(u16) {
    state,
    priority,
    cost,
    mode,
    guard,
    protect,
    fast_leave,
    learning,
    unicast_flood,
    proxyarp,
    learning_sync,
    proxyarp_wifi,
    root_id,
    bridge_id,
    designated_port,
    designated_cost,
    id,
    no,
    topology_change_ack,
    config_pending,
    message_age_timer,
    forward_delay_timer,
    hold_timer,
    flush,
    multicast_router,
    pad,
    mcast_flood,
    mcast_to_ucast,
    vlan_tunnel,
    bcast_flood,
    group_fwd_mask,
    neigh_suppress,
    isolated,
    backup_port,
    mrp_ring_open,
    mrp_in_open,
    mcast_eht_hosts_limit,
    mcast_eht_hosts_cnt,
    locked,
    mab,
    mcast_n_groups,
    mcast_max_groups,
    neigh_vlan_suppress,
    backup_nhid,
};

pub const linkinfo_brport_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_brport_attrs_fields;

    state: codec.ScalarAttr(.u8),
    priority: codec.ScalarAttr(.u16),
    cost: codec.ScalarAttr(.u32),
    mode: codec.ScalarAttr(.flag),
    guard: codec.ScalarAttr(.flag),
    protect: codec.ScalarAttr(.flag),
    fast_leave: codec.ScalarAttr(.flag),
    learning: codec.ScalarAttr(.flag),
    unicast_flood: codec.ScalarAttr(.flag),
    proxyarp: codec.ScalarAttr(.flag),
    learning_sync: codec.ScalarAttr(.flag),
    proxyarp_wifi: codec.ScalarAttr(.flag),
    root_id: codec.ScalarAttr(.binary),
    bridge_id: codec.ScalarAttr(.binary),
    designated_port: codec.ScalarAttr(.u16),
    designated_cost: codec.ScalarAttr(.u16),
    id: codec.ScalarAttr(.u16),
    no: codec.ScalarAttr(.u16),
    topology_change_ack: codec.ScalarAttr(.u8),
    config_pending: codec.ScalarAttr(.u8),
    message_age_timer: codec.ScalarAttr(.u64),
    forward_delay_timer: codec.ScalarAttr(.u64),
    hold_timer: codec.ScalarAttr(.u64),
    flush: codec.ScalarAttr(.flag),
    multicast_router: codec.ScalarAttr(.u8),
    mcast_flood: codec.ScalarAttr(.flag),
    mcast_to_ucast: codec.ScalarAttr(.flag),
    vlan_tunnel: codec.ScalarAttr(.flag),
    bcast_flood: codec.ScalarAttr(.flag),
    group_fwd_mask: codec.ScalarAttr(.u16),
    neigh_suppress: codec.ScalarAttr(.flag),
    isolated: codec.ScalarAttr(.flag),
    backup_port: codec.ScalarAttr(.u32),
    mrp_ring_open: codec.ScalarAttr(.flag),
    mrp_in_open: codec.ScalarAttr(.flag),
    mcast_eht_hosts_limit: codec.ScalarAttr(.u32),
    mcast_eht_hosts_cnt: codec.ScalarAttr(.u32),
    locked: codec.ScalarAttr(.flag),
    mab: codec.ScalarAttr(.flag),
    mcast_n_groups: codec.ScalarAttr(.u32),
    mcast_max_groups: codec.ScalarAttr(.u32),
    neigh_vlan_suppress: codec.ScalarAttr(.flag),
    backup_nhid: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const vfinfo_list_attrs_fields = enum(u16) {
    info,
};

pub const vfinfo_list_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = vfinfo_list_attrs_fields;

    info: codec.NestedAttr(vfinfo_attrs),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_vti_attrs_fields = enum(u16) {
    link,
    ikey,
    okey,
    local,
    remote,
    fwmark,
};

pub const linkinfo_vti_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_vti_attrs_fields;

    link: codec.ScalarAttr(.u32),
    ikey: codec.ScalarAttr(.u32),
    okey: codec.ScalarAttr(.u32),
    local: codec.ScalarAttr(.binary),
    remote: codec.ScalarAttr(.binary),
    fwmark: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_geneve_attrs_fields = enum(u16) {
    id,
    remote,
    ttl,
    tos,
    port,
    collect_metadata,
    remote6,
    udp_csum,
    udp_zero_csum6_tx,
    udp_zero_csum6_rx,
    label,
    ttl_inherit,
    df,
    inner_proto_inherit,
    port_range,
    gro_hint,
};

pub const linkinfo_geneve_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_geneve_attrs_fields;

    id: codec.ScalarAttr(.u32),
    remote: codec.ScalarAttr(.u32),
    ttl: codec.ScalarAttr(.u8),
    tos: codec.ScalarAttr(.u8),
    port: codec.ScalarAttr(.u16),
    collect_metadata: codec.ScalarAttr(.flag),
    remote6: codec.ScalarAttr(.binary),
    udp_csum: codec.ScalarAttr(.u8),
    udp_zero_csum6_tx: codec.ScalarAttr(.u8),
    udp_zero_csum6_rx: codec.ScalarAttr(.u8),
    label: codec.ScalarAttr(.u32),
    ttl_inherit: codec.ScalarAttr(.u8),
    df: codec.ScalarAttr(.u8),
    inner_proto_inherit: codec.ScalarAttr(.flag),
    port_range: codec.ScalarAttr(.binary),
    gro_hint: codec.ScalarAttr(.flag),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_vlan_attrs_fields = enum(u16) {
    id,
    flags,
    egress_qos,
    ingress_qos,
    protocol,
};

pub const linkinfo_vlan_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_vlan_attrs_fields;

    id: codec.ScalarAttr(.u16),
    flags: codec.ScalarAttr(.binary),
    egress_qos: codec.NestedAttr(ifla_vlan_qos),
    ingress_qos: codec.NestedAttr(ifla_vlan_qos),
    protocol: codec.EnumAttr(vlan_protocols),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const stats_attrs_fields = enum(u16) {
    link_64,
    link_xstats,
    link_xstats_slave,
    link_offload_xstats,
    af_spec,
};

pub const stats_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = stats_attrs_fields;

    link_64: codec.ScalarAttr(.binary),
    link_xstats: codec.ScalarAttr(.binary),
    link_xstats_slave: codec.ScalarAttr(.binary),
    link_offload_xstats: codec.NestedAttr(link_offload_xstats),
    af_spec: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const ifla6_attrs_fields = enum(u16) {
    flags,
    conf,
    stats,
    mcast,
    cacheinfo,
    icmp6stats,
    token,
    addr_gen_mode,
    ra_mtu,
};

pub const ifla6_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = ifla6_attrs_fields;

    flags: codec.ScalarAttr(.u32),
    /// u32 indexed by ipv6-devconf - 1 on output, on input it's a nest
    conf: codec.ScalarAttr(.binary),
    stats: codec.ScalarAttr(.binary),
    mcast: codec.ScalarAttr(.binary),
    cacheinfo: codec.ScalarAttr(.binary),
    icmp6stats: codec.ScalarAttr(.binary),
    token: codec.ScalarAttr(.binary),
    addr_gen_mode: codec.ScalarAttr(.u8),
    ra_mtu: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const hw_s_info_one_fields = enum(u16) {
    request,
    used,
};

pub const hw_s_info_one = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = hw_s_info_one_fields;

    request: codec.ScalarAttr(.u8),
    used: codec.ScalarAttr(.u8),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_gre_attrs_fields = enum(u16) {
    link,
    iflags,
    oflags,
    ikey,
    okey,
    local,
    remote,
    ttl,
    tos,
    pmtudisc,
    encap_limit,
    flowinfo,
    flags,
    encap_type,
    encap_flags,
    encap_sport,
    encap_dport,
    collect_metadata,
    ignore_df,
    fwmark,
    erspan_index,
    erspan_ver,
    erspan_dir,
    erspan_hwid,
};

pub const linkinfo_gre_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_gre_attrs_fields;

    link: codec.ScalarAttr(.u32),
    iflags: codec.ScalarAttr(.u16),
    oflags: codec.ScalarAttr(.u16),
    ikey: codec.ScalarAttr(.u32),
    okey: codec.ScalarAttr(.u32),
    local: codec.ScalarAttr(.binary),
    remote: codec.ScalarAttr(.binary),
    ttl: codec.ScalarAttr(.u8),
    tos: codec.ScalarAttr(.u8),
    pmtudisc: codec.ScalarAttr(.u8),
    encap_limit: codec.ScalarAttr(.u8),
    flowinfo: codec.ScalarAttr(.u32),
    flags: codec.ScalarAttr(.u32),
    encap_type: codec.ScalarAttr(.u16),
    encap_flags: codec.ScalarAttr(.u16),
    encap_sport: codec.ScalarAttr(.u16),
    encap_dport: codec.ScalarAttr(.u16),
    collect_metadata: codec.ScalarAttr(.flag),
    ignore_df: codec.ScalarAttr(.u8),
    fwmark: codec.ScalarAttr(.u32),
    erspan_index: codec.ScalarAttr(.u32),
    erspan_ver: codec.ScalarAttr(.u8),
    erspan_dir: codec.ScalarAttr(.u8),
    erspan_hwid: codec.ScalarAttr(.u16),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_hsr_attrs_fields = enum(u16) {
    slave1,
    slave2,
    multicast_spec,
    supervision_addr,
    seq_nr,
    version,
    protocol,
    interlink,
};

pub const linkinfo_hsr_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_hsr_attrs_fields;

    slave1: codec.ScalarAttr(.u32),
    slave2: codec.ScalarAttr(.u32),
    multicast_spec: codec.ScalarAttr(.u8),
    supervision_addr: codec.ScalarAttr(.binary),
    seq_nr: codec.ScalarAttr(.u16),
    version: codec.ScalarAttr(.u8),
    protocol: codec.ScalarAttr(.u8),
    interlink: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const prop_list_link_attrs_fields = enum(u16) {
    alt_ifname,
};

pub const prop_list_link_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = prop_list_link_attrs_fields;

    alt_ifname: codec.ScalarAttr(.string),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const vfinfo_attrs_fields = enum(u16) {
    mac,
    vlan,
    tx_rate,
    spoofchk,
    link_state,
    rate,
    rss_query_en,
    stats,
    trust,
    ib_node_guid,
    ib_port_guid,
    vlan_list,
    broadcast,
};

pub const vfinfo_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = vfinfo_attrs_fields;

    mac: codec.ScalarAttr(.binary),
    vlan: codec.ScalarAttr(.binary),
    tx_rate: codec.ScalarAttr(.binary),
    spoofchk: codec.ScalarAttr(.binary),
    link_state: codec.ScalarAttr(.binary),
    rate: codec.ScalarAttr(.binary),
    rss_query_en: codec.ScalarAttr(.binary),
    stats: codec.NestedAttr(vf_stats_attrs),
    trust: codec.ScalarAttr(.binary),
    ib_node_guid: codec.ScalarAttr(.binary),
    ib_port_guid: codec.ScalarAttr(.binary),
    vlan_list: codec.NestedAttr(vf_vlan_attrs),
    broadcast: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const vf_stats_attrs_fields = enum(u16) {
    rx_packets,
    tx_packets,
    rx_bytes,
    tx_bytes,
    broadcast,
    multicast,
    pad,
    rx_dropped,
    tx_dropped,
};

pub const vf_stats_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = vf_stats_attrs_fields;

    rx_packets: codec.ScalarAttr(.u64),
    tx_packets: codec.ScalarAttr(.u64),
    rx_bytes: codec.ScalarAttr(.u64),
    tx_bytes: codec.ScalarAttr(.u64),
    broadcast: codec.ScalarAttr(.u64),
    multicast: codec.ScalarAttr(.u64),
    rx_dropped: codec.ScalarAttr(.u64),
    tx_dropped: codec.ScalarAttr(.u64),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const mctp_attrs_fields = enum(u16) {
    net,
    phys_binding,
};

pub const mctp_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = mctp_attrs_fields;

    net: codec.ScalarAttr(.u32),
    phys_binding: codec.ScalarAttr(.u8),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_vrf_attrs_fields = enum(u16) {
    table,
};

pub const linkinfo_vrf_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_vrf_attrs_fields;

    table: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const link_offload_xstats_fields = enum(u16) {
    cpu_hit,
    hw_s_info,
    l3_stats,
};

pub const link_offload_xstats = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = link_offload_xstats_fields;

    cpu_hit: codec.ScalarAttr(.binary),
    l3_stats: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_ip6tnl_attrs_fields = enum(u16) {
    link,
    local,
    remote,
    ttl,
    encap_limit,
    flowinfo,
    flags,
    proto,
    encap_type,
    encap_flags,
    encap_sport,
    encap_dport,
    collect_metadata,
    fwmark,
};

pub const linkinfo_ip6tnl_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_ip6tnl_attrs_fields;

    link: codec.ScalarAttr(.u32),
    local: codec.ScalarAttr(.binary),
    remote: codec.ScalarAttr(.binary),
    ttl: codec.ScalarAttr(.u8),
    encap_limit: codec.ScalarAttr(.u8),
    flowinfo: codec.ScalarAttr(.u32),
    flags: codec.ScalarAttr(.u16),
    proto: codec.ScalarAttr(.u8),
    encap_type: codec.ScalarAttr(.u16),
    encap_flags: codec.ScalarAttr(.u16),
    encap_sport: codec.ScalarAttr(.u16),
    encap_dport: codec.ScalarAttr(.u16),
    collect_metadata: codec.ScalarAttr(.flag),
    fwmark: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const af_spec_attrs_fields = enum(u16) {
    inet,
    inet6,
    mctp,
};

pub const af_spec_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = af_spec_attrs_fields;

    inet: codec.NestedAttr(ifla_attrs),
    inet6: codec.NestedAttr(ifla6_attrs),
    mctp: codec.NestedAttr(mctp_attrs),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_netkit_attrs_fields = enum(u16) {
    peer_info,
    primary,
    policy,
    peer_policy,
    mode,
    scrub,
    peer_scrub,
    headroom,
    tailroom,
    pairing,
};

pub const linkinfo_netkit_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_netkit_attrs_fields;

    peer_info: codec.ScalarAttr(.binary),
    primary: codec.ScalarAttr(.u8),
    policy: codec.EnumAttr(netkit_policy),
    peer_policy: codec.EnumAttr(netkit_policy),
    mode: codec.EnumAttr(netkit_mode),
    scrub: codec.EnumAttr(netkit_scrub),
    peer_scrub: codec.EnumAttr(netkit_scrub),
    headroom: codec.ScalarAttr(.u16),
    tailroom: codec.ScalarAttr(.u16),
    pairing: codec.EnumAttr(netkit_pairing),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_vti6_attrs_fields = enum(u16) {
    link,
    ikey,
    okey,
    local,
    remote,
    fwmark,
};

pub const linkinfo_vti6_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_vti6_attrs_fields;

    link: codec.ScalarAttr(.u32),
    ikey: codec.ScalarAttr(.u32),
    okey: codec.ScalarAttr(.u32),
    local: codec.ScalarAttr(.binary),
    remote: codec.ScalarAttr(.binary),
    fwmark: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_attrs_fields = enum(u16) {
    kind,
    data,
    xstats,
    slave_kind,
    slave_data,
};

pub const linkinfo_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_attrs_fields;

    kind: codec.ScalarAttr(.string),
    xstats: codec.ScalarAttr(.binary),
    slave_kind: codec.ScalarAttr(.string),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const vf_vlan_attrs_fields = enum(u16) {
    info,
};

pub const vf_vlan_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = vf_vlan_attrs_fields;

    info: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const xdp_attrs_fields = enum(u16) {
    fd,
    attached,
    flags,
    prog_id,
    drv_prog_id,
    skb_prog_id,
    hw_prog_id,
    expected_fd,
};

pub const xdp_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = xdp_attrs_fields;

    fd: codec.ScalarAttr(.s32),
    attached: codec.ScalarAttr(.u8),
    flags: codec.ScalarAttr(.u32),
    prog_id: codec.ScalarAttr(.u32),
    drv_prog_id: codec.ScalarAttr(.u32),
    skb_prog_id: codec.ScalarAttr(.u32),
    hw_prog_id: codec.ScalarAttr(.u32),
    expected_fd: codec.ScalarAttr(.s32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const link_dpll_pin_attrs_fields = enum(u16) {
    id,
};

pub const link_dpll_pin_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = link_dpll_pin_attrs_fields;

    id: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_ovpn_attrs_fields = enum(u16) {
    mode,
};

pub const linkinfo_ovpn_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_ovpn_attrs_fields;

    mode: codec.EnumAttr(ovpn_mode),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const port_self_attrs_fields = enum(u16) {
};

pub const port_self_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = port_self_attrs_fields;


    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const link_attrs_fields = enum(u16) {
    address,
    broadcast,
    ifname,
    mtu,
    link,
    qdisc,
    stats,
    cost,
    priority,
    master,
    wireless,
    protinfo,
    txqlen,
    map,
    weight,
    operstate,
    linkmode,
    linkinfo,
    net_ns_pid,
    ifalias,
    num_vf,
    vfinfo_list,
    stats64,
    vf_ports,
    port_self,
    af_spec,
    group,
    net_ns_fd,
    ext_mask,
    promiscuity,
    num_tx_queues,
    num_rx_queues,
    carrier,
    phys_port_id,
    carrier_changes,
    phys_switch_id,
    link_netnsid,
    phys_port_name,
    proto_down,
    gso_max_segs,
    gso_max_size,
    pad,
    xdp,
    event,
    new_netnsid,
    target_netnsid,
    carrier_up_count,
    carrier_down_count,
    new_ifindex,
    min_mtu,
    max_mtu,
    prop_list,
    alt_ifname,
    perm_address,
    proto_down_reason,
    parent_dev_name,
    parent_dev_bus_name,
    gro_max_size,
    tso_max_size,
    tso_max_segs,
    allmulti,
    devlink_port,
    gso_ipv4_max_size,
    gro_ipv4_max_size,
    dpll_pin,
    max_pacing_offload_horizon,
    netns_immutable,
    headroom,
    tailroom,
};

pub const link_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = link_attrs_fields;

    address: codec.ScalarAttr(.binary),
    broadcast: codec.ScalarAttr(.binary),
    ifname: codec.ScalarAttr(.string),
    mtu: codec.ScalarAttr(.u32),
    link: codec.ScalarAttr(.u32),
    qdisc: codec.ScalarAttr(.string),
    stats: codec.ScalarAttr(.binary),
    cost: codec.ScalarAttr(.string),
    priority: codec.ScalarAttr(.string),
    master: codec.ScalarAttr(.u32),
    wireless: codec.ScalarAttr(.string),
    protinfo: codec.ScalarAttr(.string),
    txqlen: codec.ScalarAttr(.u32),
    map: codec.ScalarAttr(.binary),
    weight: codec.ScalarAttr(.u32),
    operstate: codec.ScalarAttr(.u8),
    linkmode: codec.ScalarAttr(.u8),
    linkinfo: codec.NestedAttr(linkinfo_attrs),
    net_ns_pid: codec.ScalarAttr(.u32),
    ifalias: codec.ScalarAttr(.string),
    num_vf: codec.ScalarAttr(.u32),
    vfinfo_list: codec.NestedAttr(vfinfo_list_attrs),
    stats64: codec.ScalarAttr(.binary),
    vf_ports: codec.NestedAttr(vf_ports_attrs),
    port_self: codec.NestedAttr(port_self_attrs),
    af_spec: codec.NestedAttr(af_spec_attrs),
    group: codec.ScalarAttr(.u32),
    net_ns_fd: codec.ScalarAttr(.u32),
    ext_mask: codec.EnumAttr(rtext_filter),
    promiscuity: codec.ScalarAttr(.u32),
    num_tx_queues: codec.ScalarAttr(.u32),
    num_rx_queues: codec.ScalarAttr(.u32),
    carrier: codec.ScalarAttr(.u8),
    phys_port_id: codec.ScalarAttr(.binary),
    carrier_changes: codec.ScalarAttr(.u32),
    phys_switch_id: codec.ScalarAttr(.binary),
    link_netnsid: codec.ScalarAttr(.s32),
    phys_port_name: codec.ScalarAttr(.string),
    proto_down: codec.ScalarAttr(.u8),
    gso_max_segs: codec.ScalarAttr(.u32),
    gso_max_size: codec.ScalarAttr(.u32),
    xdp: codec.NestedAttr(xdp_attrs),
    event: codec.ScalarAttr(.u32),
    new_netnsid: codec.ScalarAttr(.s32),
    target_netnsid: codec.ScalarAttr(.s32),
    carrier_up_count: codec.ScalarAttr(.u32),
    carrier_down_count: codec.ScalarAttr(.u32),
    new_ifindex: codec.ScalarAttr(.s32),
    min_mtu: codec.ScalarAttr(.u32),
    max_mtu: codec.ScalarAttr(.u32),
    prop_list: codec.NestedAttr(prop_list_link_attrs),
    alt_ifname: codec.ScalarAttr(.string),
    perm_address: codec.ScalarAttr(.binary),
    proto_down_reason: codec.ScalarAttr(.string),
    parent_dev_name: codec.ScalarAttr(.string),
    parent_dev_bus_name: codec.ScalarAttr(.string),
    gro_max_size: codec.ScalarAttr(.u32),
    tso_max_size: codec.ScalarAttr(.u32),
    tso_max_segs: codec.ScalarAttr(.u32),
    allmulti: codec.ScalarAttr(.u32),
    devlink_port: codec.ScalarAttr(.binary),
    gso_ipv4_max_size: codec.ScalarAttr(.u32),
    gro_ipv4_max_size: codec.ScalarAttr(.u32),
    dpll_pin: codec.NestedAttr(link_dpll_pin_attrs),
    /// EDT offload horizon supported by the device (in nsec).
    max_pacing_offload_horizon: codec.ScalarAttr(.uint),
    netns_immutable: codec.ScalarAttr(.u8),
    headroom: codec.ScalarAttr(.u16),
    tailroom: codec.ScalarAttr(.u16),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const linkinfo_bridge_attrs_fields = enum(u16) {
    forward_delay,
    hello_time,
    max_age,
    ageing_time,
    stp_state,
    priority,
    vlan_filtering,
    vlan_protocol,
    group_fwd_mask,
    root_id,
    bridge_id,
    root_port,
    root_path_cost,
    topology_change,
    topology_change_detected,
    hello_timer,
    tcn_timer,
    topology_change_timer,
    gc_timer,
    group_addr,
    fdb_flush,
    mcast_router,
    mcast_snooping,
    mcast_query_use_ifaddr,
    mcast_querier,
    mcast_hash_elasticity,
    mcast_hash_max,
    mcast_last_member_cnt,
    mcast_startup_query_cnt,
    mcast_last_member_intvl,
    mcast_membership_intvl,
    mcast_querier_intvl,
    mcast_query_intvl,
    mcast_query_response_intvl,
    mcast_startup_query_intvl,
    nf_call_iptables,
    nf_call_ip6tables,
    nf_call_arptables,
    vlan_default_pvid,
    pad,
    vlan_stats_enabled,
    mcast_stats_enabled,
    mcast_igmp_version,
    mcast_mld_version,
    vlan_stats_per_port,
    multi_boolopt,
    mcast_querier_state,
    fdb_n_learned,
    fdb_max_learned,
    stp_mode,
};

pub const linkinfo_bridge_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = linkinfo_bridge_attrs_fields;

    forward_delay: codec.ScalarAttr(.u32),
    hello_time: codec.ScalarAttr(.u32),
    max_age: codec.ScalarAttr(.u32),
    ageing_time: codec.ScalarAttr(.u32),
    stp_state: codec.ScalarAttr(.u32),
    priority: codec.ScalarAttr(.u16),
    vlan_filtering: codec.ScalarAttr(.u8),
    vlan_protocol: codec.ScalarAttr(.u16),
    group_fwd_mask: codec.ScalarAttr(.u16),
    root_id: codec.ScalarAttr(.binary),
    bridge_id: codec.ScalarAttr(.binary),
    root_port: codec.ScalarAttr(.u16),
    root_path_cost: codec.ScalarAttr(.u32),
    topology_change: codec.ScalarAttr(.u8),
    topology_change_detected: codec.ScalarAttr(.u8),
    hello_timer: codec.ScalarAttr(.u64),
    tcn_timer: codec.ScalarAttr(.u64),
    topology_change_timer: codec.ScalarAttr(.u64),
    gc_timer: codec.ScalarAttr(.u64),
    group_addr: codec.ScalarAttr(.binary),
    fdb_flush: codec.ScalarAttr(.binary),
    mcast_router: codec.ScalarAttr(.u8),
    mcast_snooping: codec.ScalarAttr(.u8),
    mcast_query_use_ifaddr: codec.ScalarAttr(.u8),
    mcast_querier: codec.ScalarAttr(.u8),
    mcast_hash_elasticity: codec.ScalarAttr(.u32),
    mcast_hash_max: codec.ScalarAttr(.u32),
    mcast_last_member_cnt: codec.ScalarAttr(.u32),
    mcast_startup_query_cnt: codec.ScalarAttr(.u32),
    mcast_last_member_intvl: codec.ScalarAttr(.u64),
    mcast_membership_intvl: codec.ScalarAttr(.u64),
    mcast_querier_intvl: codec.ScalarAttr(.u64),
    mcast_query_intvl: codec.ScalarAttr(.u64),
    mcast_query_response_intvl: codec.ScalarAttr(.u64),
    mcast_startup_query_intvl: codec.ScalarAttr(.u64),
    nf_call_iptables: codec.ScalarAttr(.u8),
    nf_call_ip6tables: codec.ScalarAttr(.u8),
    nf_call_arptables: codec.ScalarAttr(.u8),
    vlan_default_pvid: codec.ScalarAttr(.u16),
    vlan_stats_enabled: codec.ScalarAttr(.u8),
    mcast_stats_enabled: codec.ScalarAttr(.u8),
    mcast_igmp_version: codec.ScalarAttr(.u8),
    mcast_mld_version: codec.ScalarAttr(.u8),
    vlan_stats_per_port: codec.ScalarAttr(.u8),
    multi_boolopt: codec.ScalarAttr(.binary),
    mcast_querier_state: codec.ScalarAttr(.binary),
    fdb_n_learned: codec.ScalarAttr(.u32),
    fdb_max_learned: codec.ScalarAttr(.u32),
    stp_mode: codec.EnumAttr(br_stp_mode),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

pub const ifla_attrs_fields = enum(u16) {
    conf,
};

pub const ifla_attrs = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = ifla_attrs_fields;

    /// u32 indexed by ipv4-devconf - 1 on output, on input it's a nest
    conf: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Create a new link.
pub const newlink_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = link_attrs_fields;

    fixed_header: ifinfomsg,
    ifname: codec.ScalarAttr(.string),
    net_ns_pid: codec.ScalarAttr(.u32),
    net_ns_fd: codec.ScalarAttr(.u32),
    target_netnsid: codec.ScalarAttr(.s32),
    link_netnsid: codec.ScalarAttr(.s32),
    linkinfo: codec.NestedAttr(linkinfo_attrs),
    group: codec.ScalarAttr(.u32),
    num_tx_queues: codec.ScalarAttr(.u32),
    num_rx_queues: codec.ScalarAttr(.u32),
    address: codec.ScalarAttr(.binary),
    broadcast: codec.ScalarAttr(.binary),
    mtu: codec.ScalarAttr(.u32),
    txqlen: codec.ScalarAttr(.u32),
    operstate: codec.ScalarAttr(.u8),
    linkmode: codec.ScalarAttr(.u8),
    gso_max_size: codec.ScalarAttr(.u32),
    gso_max_segs: codec.ScalarAttr(.u32),
    gro_max_size: codec.ScalarAttr(.u32),
    gso_ipv4_max_size: codec.ScalarAttr(.u32),
    gro_ipv4_max_size: codec.ScalarAttr(.u32),
    af_spec: codec.NestedAttr(af_spec_attrs),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Delete an existing link.
pub const dellink_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = link_attrs_fields;

    fixed_header: ifinfomsg,
    ifname: codec.ScalarAttr(.string),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump information about a link.
pub const getlink_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = link_attrs_fields;

    fixed_header: ifinfomsg,
    ifname: codec.ScalarAttr(.string),
    alt_ifname: codec.ScalarAttr(.string),
    ext_mask: codec.EnumAttr(rtext_filter),
    target_netnsid: codec.ScalarAttr(.s32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump information about a link.
pub const getlink_do_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = link_attrs_fields;

    fixed_header: ifinfomsg,
    address: codec.ScalarAttr(.binary),
    broadcast: codec.ScalarAttr(.binary),
    ifname: codec.ScalarAttr(.string),
    mtu: codec.ScalarAttr(.u32),
    link: codec.ScalarAttr(.u32),
    qdisc: codec.ScalarAttr(.string),
    stats: codec.ScalarAttr(.binary),
    cost: codec.ScalarAttr(.string),
    priority: codec.ScalarAttr(.string),
    master: codec.ScalarAttr(.u32),
    wireless: codec.ScalarAttr(.string),
    protinfo: codec.ScalarAttr(.string),
    txqlen: codec.ScalarAttr(.u32),
    map: codec.ScalarAttr(.binary),
    weight: codec.ScalarAttr(.u32),
    operstate: codec.ScalarAttr(.u8),
    linkmode: codec.ScalarAttr(.u8),
    linkinfo: codec.NestedAttr(linkinfo_attrs),
    net_ns_pid: codec.ScalarAttr(.u32),
    ifalias: codec.ScalarAttr(.string),
    num_vf: codec.ScalarAttr(.u32),
    vfinfo_list: codec.NestedAttr(vfinfo_list_attrs),
    stats64: codec.ScalarAttr(.binary),
    vf_ports: codec.NestedAttr(vf_ports_attrs),
    port_self: codec.NestedAttr(port_self_attrs),
    af_spec: codec.NestedAttr(af_spec_attrs),
    group: codec.ScalarAttr(.u32),
    net_ns_fd: codec.ScalarAttr(.u32),
    ext_mask: codec.EnumAttr(rtext_filter),
    promiscuity: codec.ScalarAttr(.u32),
    num_tx_queues: codec.ScalarAttr(.u32),
    num_rx_queues: codec.ScalarAttr(.u32),
    carrier: codec.ScalarAttr(.u8),
    phys_port_id: codec.ScalarAttr(.binary),
    carrier_changes: codec.ScalarAttr(.u32),
    phys_switch_id: codec.ScalarAttr(.binary),
    link_netnsid: codec.ScalarAttr(.s32),
    phys_port_name: codec.ScalarAttr(.string),
    proto_down: codec.ScalarAttr(.u8),
    gso_max_segs: codec.ScalarAttr(.u32),
    gso_max_size: codec.ScalarAttr(.u32),
    xdp: codec.NestedAttr(xdp_attrs),
    event: codec.ScalarAttr(.u32),
    new_netnsid: codec.ScalarAttr(.s32),
    target_netnsid: codec.ScalarAttr(.s32),
    carrier_up_count: codec.ScalarAttr(.u32),
    carrier_down_count: codec.ScalarAttr(.u32),
    new_ifindex: codec.ScalarAttr(.s32),
    min_mtu: codec.ScalarAttr(.u32),
    max_mtu: codec.ScalarAttr(.u32),
    prop_list: codec.NestedAttr(prop_list_link_attrs),
    perm_address: codec.ScalarAttr(.binary),
    proto_down_reason: codec.ScalarAttr(.string),
    parent_dev_name: codec.ScalarAttr(.string),
    parent_dev_bus_name: codec.ScalarAttr(.string),
    gro_max_size: codec.ScalarAttr(.u32),
    tso_max_size: codec.ScalarAttr(.u32),
    tso_max_segs: codec.ScalarAttr(.u32),
    allmulti: codec.ScalarAttr(.u32),
    devlink_port: codec.ScalarAttr(.binary),
    gso_ipv4_max_size: codec.ScalarAttr(.u32),
    gro_ipv4_max_size: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump information about a link.
pub const getlink_dump_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = link_attrs_fields;

    fixed_header: ifinfomsg,
    target_netnsid: codec.ScalarAttr(.s32),
    ext_mask: codec.EnumAttr(rtext_filter),
    master: codec.ScalarAttr(.u32),
    linkinfo: codec.NestedAttr(linkinfo_attrs),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump information about a link.
pub const getlink_dump_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = link_attrs_fields;

    fixed_header: ifinfomsg,
    address: codec.ScalarAttr(.binary),
    broadcast: codec.ScalarAttr(.binary),
    ifname: codec.ScalarAttr(.string),
    mtu: codec.ScalarAttr(.u32),
    link: codec.ScalarAttr(.u32),
    qdisc: codec.ScalarAttr(.string),
    stats: codec.ScalarAttr(.binary),
    cost: codec.ScalarAttr(.string),
    priority: codec.ScalarAttr(.string),
    master: codec.ScalarAttr(.u32),
    wireless: codec.ScalarAttr(.string),
    protinfo: codec.ScalarAttr(.string),
    txqlen: codec.ScalarAttr(.u32),
    map: codec.ScalarAttr(.binary),
    weight: codec.ScalarAttr(.u32),
    operstate: codec.ScalarAttr(.u8),
    linkmode: codec.ScalarAttr(.u8),
    linkinfo: codec.NestedAttr(linkinfo_attrs),
    net_ns_pid: codec.ScalarAttr(.u32),
    ifalias: codec.ScalarAttr(.string),
    num_vf: codec.ScalarAttr(.u32),
    vfinfo_list: codec.NestedAttr(vfinfo_list_attrs),
    stats64: codec.ScalarAttr(.binary),
    vf_ports: codec.NestedAttr(vf_ports_attrs),
    port_self: codec.NestedAttr(port_self_attrs),
    af_spec: codec.NestedAttr(af_spec_attrs),
    group: codec.ScalarAttr(.u32),
    net_ns_fd: codec.ScalarAttr(.u32),
    ext_mask: codec.EnumAttr(rtext_filter),
    promiscuity: codec.ScalarAttr(.u32),
    num_tx_queues: codec.ScalarAttr(.u32),
    num_rx_queues: codec.ScalarAttr(.u32),
    carrier: codec.ScalarAttr(.u8),
    phys_port_id: codec.ScalarAttr(.binary),
    carrier_changes: codec.ScalarAttr(.u32),
    phys_switch_id: codec.ScalarAttr(.binary),
    link_netnsid: codec.ScalarAttr(.s32),
    phys_port_name: codec.ScalarAttr(.string),
    proto_down: codec.ScalarAttr(.u8),
    gso_max_segs: codec.ScalarAttr(.u32),
    gso_max_size: codec.ScalarAttr(.u32),
    xdp: codec.NestedAttr(xdp_attrs),
    event: codec.ScalarAttr(.u32),
    new_netnsid: codec.ScalarAttr(.s32),
    target_netnsid: codec.ScalarAttr(.s32),
    carrier_up_count: codec.ScalarAttr(.u32),
    carrier_down_count: codec.ScalarAttr(.u32),
    new_ifindex: codec.ScalarAttr(.s32),
    min_mtu: codec.ScalarAttr(.u32),
    max_mtu: codec.ScalarAttr(.u32),
    prop_list: codec.NestedAttr(prop_list_link_attrs),
    perm_address: codec.ScalarAttr(.binary),
    proto_down_reason: codec.ScalarAttr(.string),
    parent_dev_name: codec.ScalarAttr(.string),
    parent_dev_bus_name: codec.ScalarAttr(.string),
    gro_max_size: codec.ScalarAttr(.u32),
    tso_max_size: codec.ScalarAttr(.u32),
    tso_max_segs: codec.ScalarAttr(.u32),
    allmulti: codec.ScalarAttr(.u32),
    devlink_port: codec.ScalarAttr(.binary),
    gso_ipv4_max_size: codec.ScalarAttr(.u32),
    gro_ipv4_max_size: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Set information about a link.
pub const setlink_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = link_attrs_fields;

    fixed_header: ifinfomsg,
    address: codec.ScalarAttr(.binary),
    broadcast: codec.ScalarAttr(.binary),
    ifname: codec.ScalarAttr(.string),
    mtu: codec.ScalarAttr(.u32),
    link: codec.ScalarAttr(.u32),
    qdisc: codec.ScalarAttr(.string),
    stats: codec.ScalarAttr(.binary),
    cost: codec.ScalarAttr(.string),
    priority: codec.ScalarAttr(.string),
    master: codec.ScalarAttr(.u32),
    wireless: codec.ScalarAttr(.string),
    protinfo: codec.ScalarAttr(.string),
    txqlen: codec.ScalarAttr(.u32),
    map: codec.ScalarAttr(.binary),
    weight: codec.ScalarAttr(.u32),
    operstate: codec.ScalarAttr(.u8),
    linkmode: codec.ScalarAttr(.u8),
    linkinfo: codec.NestedAttr(linkinfo_attrs),
    net_ns_pid: codec.ScalarAttr(.u32),
    ifalias: codec.ScalarAttr(.string),
    num_vf: codec.ScalarAttr(.u32),
    vfinfo_list: codec.NestedAttr(vfinfo_list_attrs),
    stats64: codec.ScalarAttr(.binary),
    vf_ports: codec.NestedAttr(vf_ports_attrs),
    port_self: codec.NestedAttr(port_self_attrs),
    af_spec: codec.NestedAttr(af_spec_attrs),
    group: codec.ScalarAttr(.u32),
    net_ns_fd: codec.ScalarAttr(.u32),
    ext_mask: codec.EnumAttr(rtext_filter),
    promiscuity: codec.ScalarAttr(.u32),
    num_tx_queues: codec.ScalarAttr(.u32),
    num_rx_queues: codec.ScalarAttr(.u32),
    carrier: codec.ScalarAttr(.u8),
    phys_port_id: codec.ScalarAttr(.binary),
    carrier_changes: codec.ScalarAttr(.u32),
    phys_switch_id: codec.ScalarAttr(.binary),
    link_netnsid: codec.ScalarAttr(.s32),
    phys_port_name: codec.ScalarAttr(.string),
    proto_down: codec.ScalarAttr(.u8),
    gso_max_segs: codec.ScalarAttr(.u32),
    gso_max_size: codec.ScalarAttr(.u32),
    xdp: codec.NestedAttr(xdp_attrs),
    event: codec.ScalarAttr(.u32),
    new_netnsid: codec.ScalarAttr(.s32),
    target_netnsid: codec.ScalarAttr(.s32),
    carrier_up_count: codec.ScalarAttr(.u32),
    carrier_down_count: codec.ScalarAttr(.u32),
    new_ifindex: codec.ScalarAttr(.s32),
    min_mtu: codec.ScalarAttr(.u32),
    max_mtu: codec.ScalarAttr(.u32),
    prop_list: codec.NestedAttr(prop_list_link_attrs),
    perm_address: codec.ScalarAttr(.binary),
    proto_down_reason: codec.ScalarAttr(.string),
    parent_dev_name: codec.ScalarAttr(.string),
    parent_dev_bus_name: codec.ScalarAttr(.string),
    gro_max_size: codec.ScalarAttr(.u32),
    tso_max_size: codec.ScalarAttr(.u32),
    tso_max_segs: codec.ScalarAttr(.u32),
    allmulti: codec.ScalarAttr(.u32),
    devlink_port: codec.ScalarAttr(.binary),
    gso_ipv4_max_size: codec.ScalarAttr(.u32),
    gro_ipv4_max_size: codec.ScalarAttr(.u32),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump link stats.
pub const getstats_do_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = stats_attrs_fields;

    fixed_header: if_stats_msg,

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump link stats.
pub const getstats_do_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = stats_attrs_fields;

    fixed_header: if_stats_msg,
    link_64: codec.ScalarAttr(.binary),
    link_xstats: codec.ScalarAttr(.binary),
    link_xstats_slave: codec.ScalarAttr(.binary),
    link_offload_xstats: codec.NestedAttr(link_offload_xstats),
    af_spec: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump link stats.
pub const getstats_dump_request = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = stats_attrs_fields;

    fixed_header: if_stats_msg,

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

/// Get / dump link stats.
pub const getstats_dump_reply = struct {
    /// enum for mapping attr name to nla_type value
    pub const Enum = stats_attrs_fields;

    fixed_header: if_stats_msg,
    link_64: codec.ScalarAttr(.binary),
    link_xstats: codec.ScalarAttr(.binary),
    link_xstats_slave: codec.ScalarAttr(.binary),
    link_offload_xstats: codec.NestedAttr(link_offload_xstats),
    af_spec: codec.ScalarAttr(.binary),

    pub fn decode(buf: []const u8) !@This() {
        return codec.genericDecode(@This(), buf);
    }

    pub fn encode(self: @This(), buf: []const u8) !usize {
        return codec.genericEncode(@This(), self, buf);
    }
};

