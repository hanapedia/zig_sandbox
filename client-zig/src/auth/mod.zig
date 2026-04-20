//! Kubernetes authentication providers.
pub const kubeconfig = @import("kubeconfig.zig");
pub const in_cluster = @import("in_cluster.zig");

// Re-export main types
pub const Config = kubeconfig.Config;
pub const InClusterConfig = in_cluster.InClusterConfig;
