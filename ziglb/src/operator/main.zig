const std = @import("std");
const k8s = @import("client_zig");
const reconciler = @import("./reconciler/service.zig");
const zio = @import("zio");

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

    var sr = try reconciler.ServiceReconciler.init(allocator, io, typed_client, &event_queue);
    defer sr.deinit();

    const Winner: type = union(enum) { lw: std.Io.Cancelable!void, reconciler: std.Io.Cancelable!void };
    var sel_buf: [2]Winner = undefined;
    var select = std.Io.Select(Winner).init(io, &sel_buf);
    select.async(.lw, k8s.ListerWatcher(k8s.v1.Service, k8s.v1.ServiceList).start, .{lw});
    select.async(.reconciler, reconciler.ServiceReconciler.start, .{&sr});
    _ = try select.await();
    select.cancelDiscard();
}
