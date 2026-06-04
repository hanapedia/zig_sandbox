const std = @import("std");
const zio = @import("zio");
const bgp = @import("zigbgp");
const k8s = @import("client_zig");
const reconciler = @import("reconciler/service.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const rt = try zio.Runtime.init(std.heap.smp_allocator, .{});
    defer rt.deinit();
    const io = rt.io();
    const environ_map = init.environ_map;

    // Try to load kubeconfig, fall back to in-cluster config
    var config = k8s.config.loadConfig(io, environ_map, allocator) catch |err| {
        std.debug.print("Failed to load config: {}\n", .{err});
        return err;
    };
    defer config.deinit();

    // Create client
    var client = k8s.Client.init(io, allocator, .{
        .host = config.host,
        .token = config.token,
        .ca_cert = config.ca_cert,
        .skip_tls_verify = config.skip_tls_verify,
    }) catch |err| {
        std.debug.print("Failed to create client: {}\n", .{err});
        return err;
    };
    defer client.deinit();

    const typed_client = k8s.TypedClient(k8s.v1.Service, k8s.v1.ServiceList){
        .client = &client,
        .info = .{
            .api_version = "v1",
            .api_group = "",
            .plural = "services",
            .namespaced = true,
        },
    };

    var event_queue = try k8s.EventQueue(k8s.v1.Service).init(allocator, io);
    defer event_queue.deinit() catch {};
    defer event_queue.close();

    const lw = k8s.ListerWatcher(k8s.v1.Service, k8s.v1.ServiceList).init(
        allocator,
        io,
        null,
        typed_client,
        &event_queue,
    );

    var speaker = try bgp.Speaker.init(allocator, init.io, .{
        .as_number = 65001,
        .router_id = .{ 10, 0, 0, 1 },
        .listen_port = 179,
    });
    defer speaker.deinit();

    try speaker.addPeer(.{
        .address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 1790), // must peer sidecar
        .remote_as = 65002,
    });

    var sr = try reconciler.ServiceReconciler.init(allocator, io, typed_client, &event_queue, &speaker);

    const Winner: type = union(enum) { lw: std.Io.Cancelable!void, reconciler: std.Io.Cancelable!void, speaker: std.Io.Cancelable!void };
    var sel_buf: [3]Winner = undefined;
    var select = std.Io.Select(Winner).init(io, &sel_buf);
    select.async(.lw, k8s.ListerWatcher(k8s.v1.Service, k8s.v1.ServiceList).start, .{lw});
    select.async(.reconciler, reconciler.ServiceReconciler.start, .{&sr});
    select.async(.speaker, bgp.Speaker.start, .{&speaker});
    _ = try select.await();
    select.cancelDiscard();
}
