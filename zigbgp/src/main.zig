const std = @import("std");
const bgp = @import("zigbgp");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var speaker = try bgp.Speaker.init(allocator, init.io, .{
        .as_number = 65001,
        .router_id = .{ 10, 0, 0, 1 },
        .listen_port = 179,
    });
    defer speaker.deinit();

    // TODO: speaker.addPeer(.{
    //     .address   = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 179),
    //     .remote_as = 65002,
    // });

    try speaker.start();
    defer speaker.stop();

    std.log.info("ZigBGP running — AS {d}, router-id {d}.{d}.{d}.{d}", .{
        speaker.cfg.as_number,
        speaker.cfg.router_id[0],
        speaker.cfg.router_id[1],
        speaker.cfg.router_id[2],
        speaker.cfg.router_id[3],
    });

    // Block until interrupted (Ctrl-C / SIGTERM).
    try std.Io.sleep(init.io, std.Io.Duration.fromSeconds(3), .awake);
}
