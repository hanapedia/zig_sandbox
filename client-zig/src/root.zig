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
pub const TypedClient = api.TypedClient;
pub const ListOptions = api.ListOptions;
pub const ResourceInfo = api.ResourceInfo;

// Re-export proto types for convenience
pub const Pod = proto.Pod;
pub const PodList = proto.PodList;
pub const PodSpec = proto.PodSpec;
pub const PodStatus = proto.PodStatus;
pub const Service = proto.Service;
pub const ServiceList = proto.ServiceList;
pub const ConfigMap = proto.ConfigMap;
pub const ConfigMapList = proto.ConfigMapList;
pub const Secret = proto.Secret;
pub const SecretList = proto.SecretList;
pub const Namespace = proto.Namespace;
pub const NamespaceList = proto.NamespaceList;
pub const Node = proto.Node;
pub const NodeList = proto.NodeList;
pub const Deployment = proto.Deployment;
pub const DeploymentList = proto.DeploymentList;
pub const Job = proto.Job;
pub const JobList = proto.JobList;
pub const ObjectMeta = proto.ObjectMeta;
pub const ListMeta = proto.ListMeta;

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
pub fn pods(c: *Client, namespace: ?[]const u8) TypedClient(Pod, PodList) {
    return .{ .client = c, .namespace = namespace, .info = resource_info.pod };
}

/// Create a typed client for Service resources.
pub fn services(c: *Client, namespace: ?[]const u8) TypedClient(Service, ServiceList) {
    return .{ .client = c, .namespace = namespace, .info = resource_info.service };
}

/// Create a typed client for ConfigMap resources.
pub fn configMaps(c: *Client, namespace: ?[]const u8) TypedClient(ConfigMap, ConfigMapList) {
    return .{ .client = c, .namespace = namespace, .info = resource_info.configmap };
}

/// Create a typed client for Secret resources.
pub fn secrets(c: *Client, namespace: ?[]const u8) TypedClient(Secret, SecretList) {
    return .{ .client = c, .namespace = namespace, .info = resource_info.secret };
}

/// Create a typed client for Namespace resources (cluster-scoped).
pub fn namespaces(c: *Client) TypedClient(Namespace, NamespaceList) {
    return .{ .client = c, .namespace = null, .info = resource_info.namespace };
}

/// Create a typed client for Node resources (cluster-scoped).
pub fn nodes(c: *Client) TypedClient(Node, NodeList) {
    return .{ .client = c, .namespace = null, .info = resource_info.node };
}

/// Create a typed client for Deployment resources.
pub fn deployments(c: *Client, namespace: ?[]const u8) TypedClient(Deployment, DeploymentList) {
    return .{ .client = c, .namespace = namespace, .info = resource_info.deployment };
}

/// Create a typed client for Job resources.
pub fn jobs(c: *Client, namespace: ?[]const u8) TypedClient(Job, JobList) {
    return .{ .client = c, .namespace = namespace, .info = resource_info.job };
}

test {
    // Run all module tests
    std.testing.refAllDecls(@This());
    _ = @import("api/typed.zig");
    _ = @import("client/Client.zig");
}
