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
//!     const pods = try k8s.pods(&client).list("default", .{});
//!     defer pods.deinit();
//!
//!     for (pods.value.items.items) |pod| {
//!         const name = if (pod.metadata) |m| m.name orelse "unknown" else "unknown";
//!         std.debug.print("Pod: {s}\n", .{name});
//!     }
//! }
//! ```

const std = @import("std");

// Module exports
pub const auth = @import("auth/mod.zig");
pub const client = @import("client/mod.zig");
pub const api = @import("api/mod.zig");
pub const watch = @import("api/watch.zig");
pub const proto = @import("proto/mod.zig");

// Convenience re-exports
pub const Client = client.Client;
pub const kubeconfig = auth.kubeconfig;
pub const in_cluster = auth.in_cluster;
pub const config = auth.config;
pub const TypedClient = api.TypedClient;
pub const ListOptions = api.ListOptions;
pub const ResourceInfo = api.ResourceInfo;

// Watch API
pub const Watcher = api.Watcher;
pub const WatchStream = api.WatchStream;
pub const WatchOptions = api.WatchOptions;
pub const WatchEvent = api.WatchEvent;
pub const EventType = api.EventType;

// ListerWatcher
pub const ListerWatcher = api.ListerWatcher;
pub const EventQueue = api.EventQueue;

// Proto API group exports
pub const v1 = proto.v1;
pub const appsv1 = proto.appsv1;
pub const batchv1 = proto.batchv1;
pub const metav1 = proto.metav1;

// Resource info definitions for core v1 resources
pub const resource_info = struct {
    pub const pod: ResourceInfo = .{
        .api_version = "v1",
        .api_group = "",
        .plural = "pods",
        .namespaced = true,
    };
    pub const service: ResourceInfo = .{
        .api_version = "v1",
        .api_group = "",
        .plural = "services",
        .namespaced = true,
    };
    pub const configmap: ResourceInfo = .{
        .api_version = "v1",
        .api_group = "",
        .plural = "configmaps",
        .namespaced = true,
    };
    pub const secret: ResourceInfo = .{
        .api_version = "v1",
        .api_group = "",
        .plural = "secrets",
        .namespaced = true,
    };
    pub const namespace: ResourceInfo = .{
        .api_version = "v1",
        .api_group = "",
        .plural = "namespaces",
        .namespaced = false,
    };
    pub const node: ResourceInfo = .{
        .api_version = "v1",
        .api_group = "",
        .plural = "nodes",
        .namespaced = false,
    };
    pub const deployment: ResourceInfo = .{
        .api_version = "v1",
        .api_group = "apps",
        .plural = "deployments",
        .namespaced = true,
    };
    pub const job: ResourceInfo = .{
        .api_version = "v1",
        .api_group = "batch",
        .plural = "jobs",
        .namespaced = true,
    };
};

// Convenience functions for creating typed clients

/// Create a typed client for Pod resources.
pub fn pods(c: *Client) TypedClient(v1.Pod, v1.PodList) {
    return .{ .client = c, .info = resource_info.pod };
}

/// Create a typed client for Service resources.
pub fn services(c: *Client) TypedClient(v1.Service, v1.ServiceList) {
    return .{ .client = c, .info = resource_info.service };
}

/// Create a typed client for ConfigMap resources.
pub fn configMaps(c: *Client) TypedClient(v1.ConfigMap, v1.ConfigMapList) {
    return .{ .client = c, .info = resource_info.configmap };
}

/// Create a typed client for Secret resources.
pub fn secrets(c: *Client) TypedClient(v1.Secret, v1.SecretList) {
    return .{ .client = c, .info = resource_info.secret };
}

/// Create a typed client for Namespace resources (cluster-scoped).
pub fn namespaces(c: *Client) TypedClient(v1.Namespace, v1.NamespaceList) {
    return .{ .client = c, .info = resource_info.namespace };
}

/// Create a typed client for Node resources (cluster-scoped).
pub fn nodes(c: *Client) TypedClient(v1.Node, v1.NodeList) {
    return .{ .client = c, .info = resource_info.node };
}

/// Create a typed client for Deployment resources.
pub fn deployments(c: *Client) TypedClient(appsv1.Deployment, appsv1.DeploymentList) {
    return .{ .client = c, .info = resource_info.deployment };
}

/// Create a typed client for Job resources.
pub fn jobs(c: *Client) TypedClient(batchv1.Job, batchv1.JobList) {
    return .{ .client = c, .info = resource_info.job };
}

test {
    // Run all module tests
    std.testing.refAllDecls(@This());
    _ = @import("api/typed.zig");
    _ = @import("client/Client.zig");
}
