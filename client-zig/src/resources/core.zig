//! Core Kubernetes v1 API resources.
//! These types use minimal typing with std.json.Value for complex nested fields.
const std = @import("std");
const meta = @import("meta.zig");

// ============================================================================
// Pod
// ============================================================================

pub const Pod = struct {
    pub const resource_api_version = "v1";
    pub const resource_api_group = "";
    pub const resource_kind = "Pod";
    pub const resource_plural = "pods";
    pub const resource_namespaced = true;

    apiVersion: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    metadata: meta.ObjectMeta = .{},
    spec: ?std.json.Value = null,
    status: ?PodStatus = null,
};

pub const PodStatus = struct {
    phase: ?[]const u8 = null,
    conditions: ?[]const PodCondition = null,
    hostIP: ?[]const u8 = null,
    podIP: ?[]const u8 = null,
    podIPs: ?[]const PodIP = null,
    startTime: ?[]const u8 = null,
    containerStatuses: ?[]const ContainerStatus = null,
    initContainerStatuses: ?[]const ContainerStatus = null,
    message: ?[]const u8 = null,
    reason: ?[]const u8 = null,
};

pub const PodCondition = struct {
    type: []const u8,
    status: []const u8,
    lastProbeTime: ?[]const u8 = null,
    lastTransitionTime: ?[]const u8 = null,
    reason: ?[]const u8 = null,
    message: ?[]const u8 = null,
};

pub const PodIP = struct {
    ip: ?[]const u8 = null,
};

pub const ContainerStatus = struct {
    name: []const u8,
    state: ?std.json.Value = null,
    lastState: ?std.json.Value = null,
    ready: bool = false,
    restartCount: i32 = 0,
    image: ?[]const u8 = null,
    imageID: ?[]const u8 = null,
    containerID: ?[]const u8 = null,
    started: ?bool = null,
};

pub const PodList = meta.List(Pod);

// ============================================================================
// Service
// ============================================================================

pub const Service = struct {
    pub const resource_api_version = "v1";
    pub const resource_api_group = "";
    pub const resource_kind = "Service";
    pub const resource_plural = "services";
    pub const resource_namespaced = true;

    apiVersion: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    metadata: meta.ObjectMeta = .{},
    spec: ?ServiceSpec = null,
    status: ?std.json.Value = null,
};

pub const ServiceSpec = struct {
    type: ?[]const u8 = null,
    clusterIP: ?[]const u8 = null,
    clusterIPs: ?[]const []const u8 = null,
    externalIPs: ?[]const []const u8 = null,
    ports: ?[]const ServicePort = null,
    selector: ?std.json.Value = null,
    sessionAffinity: ?[]const u8 = null,
    loadBalancerIP: ?[]const u8 = null,
    externalName: ?[]const u8 = null,
};

pub const ServicePort = struct {
    name: ?[]const u8 = null,
    protocol: ?[]const u8 = null,
    port: i32,
    targetPort: ?std.json.Value = null,
    nodePort: ?i32 = null,
};

pub const ServiceList = meta.List(Service);

// ============================================================================
// ConfigMap
// ============================================================================

pub const ConfigMap = struct {
    pub const resource_api_version = "v1";
    pub const resource_api_group = "";
    pub const resource_kind = "ConfigMap";
    pub const resource_plural = "configmaps";
    pub const resource_namespaced = true;

    apiVersion: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    metadata: meta.ObjectMeta = .{},
    data: ?std.json.Value = null,
    binaryData: ?std.json.Value = null,
    immutable: ?bool = null,
};

pub const ConfigMapList = meta.List(ConfigMap);

// ============================================================================
// Secret
// ============================================================================

pub const Secret = struct {
    pub const resource_api_version = "v1";
    pub const resource_api_group = "";
    pub const resource_kind = "Secret";
    pub const resource_plural = "secrets";
    pub const resource_namespaced = true;

    apiVersion: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    metadata: meta.ObjectMeta = .{},
    type: ?[]const u8 = null,
    data: ?std.json.Value = null,
    stringData: ?std.json.Value = null,
    immutable: ?bool = null,
};

pub const SecretList = meta.List(Secret);

// ============================================================================
// Namespace
// ============================================================================

pub const Namespace = struct {
    pub const resource_api_version = "v1";
    pub const resource_api_group = "";
    pub const resource_kind = "Namespace";
    pub const resource_plural = "namespaces";
    pub const resource_namespaced = false;

    apiVersion: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    metadata: meta.ObjectMeta = .{},
    spec: ?NamespaceSpec = null,
    status: ?NamespaceStatus = null,
};

pub const NamespaceSpec = struct {
    finalizers: ?[]const []const u8 = null,
};

pub const NamespaceStatus = struct {
    phase: ?[]const u8 = null,
    conditions: ?[]const NamespaceCondition = null,
};

pub const NamespaceCondition = struct {
    type: []const u8,
    status: []const u8,
    lastTransitionTime: ?[]const u8 = null,
    reason: ?[]const u8 = null,
    message: ?[]const u8 = null,
};

pub const NamespaceList = meta.List(Namespace);

// ============================================================================
// Node
// ============================================================================

pub const Node = struct {
    pub const resource_api_version = "v1";
    pub const resource_api_group = "";
    pub const resource_kind = "Node";
    pub const resource_plural = "nodes";
    pub const resource_namespaced = false;

    apiVersion: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    metadata: meta.ObjectMeta = .{},
    spec: ?std.json.Value = null,
    status: ?NodeStatus = null,
};

pub const NodeStatus = struct {
    capacity: ?std.json.Value = null,
    allocatable: ?std.json.Value = null,
    conditions: ?[]const NodeCondition = null,
    addresses: ?[]const NodeAddress = null,
    nodeInfo: ?NodeSystemInfo = null,
    images: ?[]const ContainerImage = null,
};

pub const NodeCondition = struct {
    type: []const u8,
    status: []const u8,
    lastHeartbeatTime: ?[]const u8 = null,
    lastTransitionTime: ?[]const u8 = null,
    reason: ?[]const u8 = null,
    message: ?[]const u8 = null,
};

pub const NodeAddress = struct {
    type: []const u8,
    address: []const u8,
};

pub const NodeSystemInfo = struct {
    machineID: ?[]const u8 = null,
    systemUUID: ?[]const u8 = null,
    bootID: ?[]const u8 = null,
    kernelVersion: ?[]const u8 = null,
    osImage: ?[]const u8 = null,
    containerRuntimeVersion: ?[]const u8 = null,
    kubeletVersion: ?[]const u8 = null,
    kubeProxyVersion: ?[]const u8 = null,
    operatingSystem: ?[]const u8 = null,
    architecture: ?[]const u8 = null,
};

pub const ContainerImage = struct {
    names: ?[]const []const u8 = null,
    sizeBytes: ?i64 = null,
};

pub const NodeList = meta.List(Node);

// ============================================================================
// Tests
// ============================================================================

test "Pod parsing" {
    const json_str =
        \\{"apiVersion":"v1","kind":"Pod","metadata":{"name":"test-pod","namespace":"default"},"status":{"phase":"Running","podIP":"10.0.0.1"}}
    ;
    const parsed = try std.json.parseFromSlice(Pod, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("test-pod", parsed.value.metadata.name.?);
    try std.testing.expectEqualStrings("Running", parsed.value.status.?.phase.?);
}

test "Service parsing" {
    const json_str =
        \\{"apiVersion":"v1","kind":"Service","metadata":{"name":"my-svc"},"spec":{"type":"ClusterIP","clusterIP":"10.96.0.1","ports":[{"port":80,"targetPort":8080}]}}
    ;
    const parsed = try std.json.parseFromSlice(Service, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("my-svc", parsed.value.metadata.name.?);
    try std.testing.expectEqualStrings("ClusterIP", parsed.value.spec.?.type.?);
}

test "Namespace parsing" {
    const json_str =
        \\{"apiVersion":"v1","kind":"Namespace","metadata":{"name":"kube-system"},"status":{"phase":"Active"}}
    ;
    const parsed = try std.json.parseFromSlice(Namespace, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("kube-system", parsed.value.metadata.name.?);
    try std.testing.expectEqualStrings("Active", parsed.value.status.?.phase.?);
}
