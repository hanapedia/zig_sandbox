const xdp_md = extern struct {
    data: u32,
    data_end: u32,
    data_meta: u32,
    ingress_ifindex: u32,
    rx_queue_index: u32,
    egress_ifindex: u32,
};

const XDP_ACTION = enum(i32) {
    ABORTED = 0,
    DROP = 1,
    PASS = 2,
    TX = 3,
    REDIRECT = 4,
};

export fn xdp_pass(ctx: *xdp_md) linksection("xdp") XDP_ACTION {
    _ = ctx;
    return .PASS;
}
