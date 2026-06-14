const std = @import("std");
const nl = @import("netlink");

const linux = std.os.linux;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var s = nl.socket.Socket.init();
    try s.open();
    defer s.close();
    const payload = std.mem.zeroes(linux.ifinfomsg);
    var res = try s.request(
        allocator,
        nl.socket.Request{
            .msg_type = .RTM_GETLINK,
            .flags = linux.NLM_F_REQUEST | linux.NLM_F_DUMP,
            .payload = std.mem.asBytes(&payload),
        },
    );
    defer res.deinit(allocator);
    for (res.msgs.items) |msg| {
        std.debug.print("msg: {}\n", .{msg.data.len});
    }
}
