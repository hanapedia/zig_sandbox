//! Kubernetes resource type definitions.
pub const meta = @import("meta.zig");
pub const core = @import("core.zig");

// Re-export commonly used types at top level for convenience
pub const ObjectMeta = meta.ObjectMeta;
pub const ListMeta = meta.ListMeta;
pub const List = meta.List;
pub const Status = meta.Status;

// Core v1 resources
pub const Pod = core.Pod;
pub const PodList = core.PodList;
pub const PodStatus = core.PodStatus;

pub const Service = core.Service;
pub const ServiceList = core.ServiceList;
pub const ServiceSpec = core.ServiceSpec;

pub const ConfigMap = core.ConfigMap;
pub const ConfigMapList = core.ConfigMapList;

pub const Secret = core.Secret;
pub const SecretList = core.SecretList;

pub const Namespace = core.Namespace;
pub const NamespaceList = core.NamespaceList;

pub const Node = core.Node;
pub const NodeList = core.NodeList;
pub const NodeStatus = core.NodeStatus;
