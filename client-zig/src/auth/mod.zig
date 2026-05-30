//! Kubernetes authentication providers.
pub const config = @import("config.zig");
pub const kubeconfig = @import("kubeconfig.zig");
pub const in_cluster = @import("in_cluster.zig");

// Re-export main types
pub const Config = config.Config;
pub const KubeConfig = kubeconfig.KubeConfig;
pub const InClusterConfig = in_cluster.InClusterConfig;
