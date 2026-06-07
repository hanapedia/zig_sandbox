const skb = @import("./skb.zig");

const TC_ACTION = enum(i32) {
    UNSPEC = -1, // defer to default
    OK = 0, // pass
    SHOT = 2, //drop
    REDIRECT = 7,
};

export fn tc_ingress_ok(ctx: *skb.Skb) linksection("tc/ingress") TC_ACTION {
    _ = ctx;
    return .OK;
}
