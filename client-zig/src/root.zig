//! Kubernetes client library for Zig.
//!
//! This library provides a type-safe interface for interacting with the
//! Kubernetes API server. It supports both kubeconfig file and in-cluster
//! ServiceAccount authentication.
//!
//! ## Example Usage
//!
//! ```zig
//! const std = @import("std");
//! const k8s = @import("client_zig");
//!
//! pub fn main() !void {
//!     const allocator = std.heap.page_allocator;
//!
//!     // Load configuration
//!     var config = try k8s.kubeconfig.load(allocator, null);
//!     defer config.deinit();
//!
//!     // Create client
//!     var client = try k8s.Client.init(allocator, .{
//!         .host = config.host,
//!         .token = config.token,
//!         .skip_tls_verify = config.skip_tls_verify,
//!     });
//!     defer client.deinit();
//!
//!     // List pods
//!     const pods = try k8s.pods(&client, "default").list(.{});
//!     defer pods.deinit();
//!
//!     for (pods.value.items) |pod| {
//!         std.debug.print("Pod: {s}\n", .{pod.metadata.name orelse "unknown"});
//!     }
//! }
//! ```

const std = @import("std");

// Module exports
pub const resources = @import("resources/mod.zig");
pub const auth = @import("auth/mod.zig");
pub const client = @import("client/mod.zig");
pub const api = @import("api/mod.zig");

// Convenience re-exports
pub const Client = client.Client;
pub const kubeconfig = auth.kubeconfig;
pub const in_cluster = auth.in_cluster;
pub const TypedClient = api.TypedClient;
pub const ListOptions = api.ListOptions;

// Resource types
pub const Pod = resources.Pod;
pub const PodList = resources.PodList;
pub const Service = resources.Service;
pub const ServiceList = resources.ServiceList;
pub const ConfigMap = resources.ConfigMap;
pub const ConfigMapList = resources.ConfigMapList;
pub const Secret = resources.Secret;
pub const SecretList = resources.SecretList;
pub const Namespace = resources.Namespace;
pub const NamespaceList = resources.NamespaceList;
pub const Node = resources.Node;
pub const NodeList = resources.NodeList;

// Convenience functions for creating typed clients

/// Create a typed client for Pod resources.
pub fn pods(c: *Client, namespace: ?[]const u8) TypedClient(Pod) {
    return .{ .client = c, .namespace = namespace };
}

/// Create a typed client for Service resources.
pub fn services(c: *Client, namespace: ?[]const u8) TypedClient(Service) {
    return .{ .client = c, .namespace = namespace };
}

/// Create a typed client for ConfigMap resources.
pub fn configMaps(c: *Client, namespace: ?[]const u8) TypedClient(ConfigMap) {
    return .{ .client = c, .namespace = namespace };
}

/// Create a typed client for Secret resources.
pub fn secrets(c: *Client, namespace: ?[]const u8) TypedClient(Secret) {
    return .{ .client = c, .namespace = namespace };
}

/// Create a typed client for Namespace resources (cluster-scoped).
pub fn namespaces(c: *Client) TypedClient(Namespace) {
    return .{ .client = c, .namespace = null };
}

/// Create a typed client for Node resources (cluster-scoped).
pub fn nodes(c: *Client) TypedClient(Node) {
    return .{ .client = c, .namespace = null };
}

test {
    // Run all module tests
    std.testing.refAllDecls(@This());
    _ = @import("resources/meta.zig");
    _ = @import("resources/core.zig");
    _ = @import("api/typed.zig");
    _ = @import("client/Client.zig");
}
