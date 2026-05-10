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
