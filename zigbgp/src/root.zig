/// ZigBGP — embeddable BGP speaker library.
///
/// Typical usage:
///
///   var speaker = try bgp.Speaker.init(allocator, io, .{
///       .as_number = 65001,
///       .router_id = .{ 10, 0, 0, 1 },
///   });
///   defer speaker.deinit();
///
///   // try speaker.addPeer(.{ .address = ..., .remote_as = 65002 });
///
///   try speaker.start();
pub const Speaker = @import("bgp/speaker.zig").Speaker;
pub const LocalConfig = @import("config.zig").LocalConfig;
pub const PeerConfig = @import("config.zig").PeerConfig;
pub const Peer = @import("bgp/peer.zig").Peer;
test {
    _ = @import("bgp/message.zig");
    _ = @import("bgp/open.zig");
    _ = @import("bgp/notification.zig");
    _ = @import("bgp/update.zig");
    _ = @import("bgp/fsm.zig");
    _ = @import("bgp/peer.zig");
}
