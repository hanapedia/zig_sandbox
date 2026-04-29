//! Example CLI for the Kubernetes client library.
//! Demonstrates listing pods from a Kubernetes cluster.
const std = @import("std");
const k8s = @import("client_zig");

pub fn main(init: std.process.Init) !void {
    // Use page allocator for simplicity
    const allocator = init.gpa;
    const io = init.io;
    const environ_map = init.environ_map;

    // Try to load kubeconfig, fall back to in-cluster config
    var config = loadConfig(io, environ_map, allocator) catch |err| {
        std.debug.print("Failed to load config: {}\n", .{err});
        return err;
    };
    defer config.deinit();

    std.debug.print("Connected to: {s}\n", .{config.host});
    if (config.namespace) |ns| {
        std.debug.print("Default namespace: {s}\n", .{ns});
    }

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

    const namespace = config.namespace orelse "default";

    // List namespaces using protobuf encoding
    std.debug.print("\n--- Namespaces (protobuf encoding) ---\n", .{});
    listNamespaces(&client) catch |err| {
        std.debug.print("Failed to list namespaces: {}\n", .{err});
    };

    // List pods using protobuf encoding
    std.debug.print("\n--- Pods in '{s}' namespace (protobuf encoding) ---\n", .{namespace});
    listPods(&client, namespace) catch |err| {
        std.debug.print("Failed to list pods: {}\n", .{err});
    };

    // List services using protobuf encoding
    std.debug.print("\n--- Services in '{s}' namespace (protobuf encoding) ---\n", .{namespace});
    listServices(&client, namespace) catch |err| {
        std.debug.print("Failed to list services: {}\n", .{err});
    };

    // Watch pods using protobuf encoding
    std.debug.print("\n--- Watching Pods in '{s}' namespace (protobuf encoding) ---\n", .{namespace});
    watchPods(&client, namespace) catch |err| {
        std.debug.print("Failed to watch pods: {}\n", .{err});
    };
}

fn loadConfig(io: std.Io, environ_map: *std.process.Environ.Map, allocator: std.mem.Allocator) !Config {
    // Try kubeconfig first, fall back to in-cluster config
    if (k8s.kubeconfig.load(io, environ_map, allocator, null)) |cfg| {
        return .{
            .allocator = allocator,
            .host = cfg.host,
            .token = cfg.token,
            .ca_cert = cfg.ca_cert,
            .skip_tls_verify = cfg.skip_tls_verify,
            .namespace = cfg.namespace,
            .source = .kubeconfig,
        };
    } else |_| {
        // Fall back to in-cluster config
        const in_cluster = try k8s.in_cluster.InClusterConfig.load(io, environ_map, allocator);
        return .{
            .allocator = allocator,
            .host = in_cluster.host,
            .token = in_cluster.token,
            .ca_cert = in_cluster.ca_cert,
            .skip_tls_verify = false,
            .namespace = in_cluster.namespace,
            .source = .in_cluster,
        };
    }
}

const Config = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    token: ?[]const u8,
    ca_cert: ?[]const u8,
    skip_tls_verify: bool,
    namespace: ?[]const u8,
    source: enum { kubeconfig, in_cluster },

    fn deinit(self: *Config) void {
        self.allocator.free(self.host);
        if (self.token) |t| self.allocator.free(t);
        if (self.ca_cert) |c| self.allocator.free(c);
        if (self.namespace) |n| self.allocator.free(n);
    }
};

fn listNamespaces(client: *k8s.Client) !void {
    var result = try k8s.namespaces(client).list(.{});
    defer result.deinit();

    if (result.value.items.items.len == 0) {
        std.debug.print("  (no namespaces found)\n", .{});
        return;
    }

    for (result.value.items.items) |ns| {
        const name = if (ns.metadata) |m| m.name orelse "unknown" else "unknown";
        const phase = if (ns.status) |s| s.phase orelse "Unknown" else "Unknown";
        std.debug.print("  {s} ({s})\n", .{ name, phase });
    }
}

fn listPods(client: *k8s.Client, namespace: []const u8) !void {
    var result = try k8s.pods(client, namespace).list(.{});
    defer result.deinit();

    if (result.value.items.items.len == 0) {
        std.debug.print("  (no pods found)\n", .{});
        return;
    }

    for (result.value.items.items) |pod| {
        const name = if (pod.metadata) |m| m.name orelse "unknown" else "unknown";
        const phase = if (pod.status) |s| s.phase orelse "Unknown" else "Unknown";
        const pod_ip = if (pod.status) |s| s.podIP orelse "N/A" else "N/A";
        std.debug.print("  {s} ({s}) - IP: {s}\n", .{ name, phase, pod_ip });
    }
}

fn listServices(client: *k8s.Client, namespace: []const u8) !void {
    var result = try k8s.services(client, namespace).list(.{});
    defer result.deinit();

    if (result.value.items.items.len == 0) {
        std.debug.print("  (no services found)\n", .{});
        return;
    }

    for (result.value.items.items) |svc| {
        const name = if (svc.metadata) |m| m.name orelse "unknown" else "unknown";
        const svc_type = if (svc.spec) |s| s.type orelse "ClusterIP" else "ClusterIP";
        const cluster_ip = if (svc.spec) |s| s.clusterIP orelse "None" else "None";
        std.debug.print("  {s} ({s}) - ClusterIP: {s}\n", .{ name, svc_type, cluster_ip });
    }
}

/// Watch pods using the high-level Watcher API.
/// This demonstrates the iterator-style usage pattern.
fn watchPods(client: *k8s.Client, namespace: []const u8) !void {
    // Create a typed watcher for Pods
    var watcher = try k8s.Watcher(k8s.Pod).init(
        client,
        namespace,
        k8s.resource_info.pod,
        .{}, // Default watch options
    );
    defer watcher.deinit();

    std.debug.print("  Watching for pod events...\n", .{});

    // Iterate over watch events
    var event_count: usize = 0;
    while (try watcher.next()) |event_val| {
        var event = event_val;
        defer event.deinit();

        const pod = event.object();
        const name = if (pod.metadata) |m| m.name orelse "unknown" else "unknown";
        const phase = if (pod.status) |s| s.phase orelse "Unknown" else "Unknown";

        std.debug.print("  [{s}] {s} - {s}\n", .{
            @tagName(event.event_type),
            name,
            phase,
        });

        event_count += 1;

        // For demo purposes, stop after 3 events
        if (event_count >= 3) {
            std.debug.print("  (stopping after 3 events)\n", .{});
            break;
        }
    }
}

/// Watch pods using the low-level WatchStream API.
/// This demonstrates direct access to raw JSON lines.
fn watchPodsLowLevel(client: *k8s.Client, namespace: []const u8) !void {
    var stream = try k8s.WatchStream.init(
        client,
        namespace,
        k8s.resource_info.pod,
        .{},
    );
    defer stream.deinit();

    std.debug.print("  Watching for raw events...\n", .{});

    var event_count: usize = 0;
    while (try stream.readLine()) |line| {
        defer stream.allocator.free(line);

        // Parse just the event type using std.json.Value for demonstration
        const parsed = std.json.parseFromSlice(std.json.Value, stream.allocator, line, .{
            .ignore_unknown_fields = true,
        }) catch {
            std.debug.print("  Failed to parse event JSON\n", .{});
            continue;
        };
        defer parsed.deinit();

        const event_type = if (parsed.value.object.get("type")) |t| t.string else "?";
        const obj = parsed.value.object.get("object") orelse continue;
        const metadata = obj.object.get("metadata") orelse continue;
        const name = if (metadata.object.get("name")) |n| n.string else "(no name)";
        const rv = if (metadata.object.get("resourceVersion")) |r| r.string else "?";

        std.debug.print("  [{s}] {s} (rv={s}, {d} bytes)\n", .{ event_type, name, rv, line.len });

        event_count += 1;
        if (event_count >= 5) {
            std.debug.print("  (stopping after 5 events)\n", .{});
            break;
        }
    }
}
