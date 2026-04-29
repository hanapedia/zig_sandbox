//! Protobuf-generated Kubernetes API types.
//! Generated from kubernetes proto files using zig-protobuf.

pub const k8s = struct {
    pub const io = struct {
        pub const api = struct {
            pub const core = struct {
                pub const v1 = @import("k8s/io/api/core/v1.pb.zig");
            };
            pub const apps = struct {
                pub const v1 = @import("k8s/io/api/apps/v1.pb.zig");
            };
            pub const batch = struct {
                pub const v1 = @import("k8s/io/api/batch/v1.pb.zig");
            };
        };
        pub const apimachinery = struct {
            pub const pkg = struct {
                pub const apis = struct {
                    pub const meta = struct {
                        pub const v1 = @import("k8s/io/apimachinery/pkg/apis/meta/v1.pb.zig");
                    };
                };
                pub const api = struct {
                    pub const resource = @import("k8s/io/apimachinery/pkg/api/resource.pb.zig");
                };
                pub const runtime = @import("k8s/io/apimachinery/pkg/runtime.pb.zig");
                pub const util = struct {
                    pub const intstr = @import("k8s/io/apimachinery/pkg/util/intstr.pb.zig");
                };
            };
        };
    };
};

// Convenient aliases for common types
pub const Pod = k8s.io.api.core.v1.Pod;
pub const PodList = k8s.io.api.core.v1.PodList;
pub const PodSpec = k8s.io.api.core.v1.PodSpec;
pub const PodStatus = k8s.io.api.core.v1.PodStatus;
pub const Service = k8s.io.api.core.v1.Service;
pub const ServiceList = k8s.io.api.core.v1.ServiceList;
pub const Namespace = k8s.io.api.core.v1.Namespace;
pub const NamespaceList = k8s.io.api.core.v1.NamespaceList;
pub const ConfigMap = k8s.io.api.core.v1.ConfigMap;
pub const ConfigMapList = k8s.io.api.core.v1.ConfigMapList;
pub const Secret = k8s.io.api.core.v1.Secret;
pub const SecretList = k8s.io.api.core.v1.SecretList;
pub const Node = k8s.io.api.core.v1.Node;
pub const NodeList = k8s.io.api.core.v1.NodeList;

pub const Deployment = k8s.io.api.apps.v1.Deployment;
pub const DeploymentList = k8s.io.api.apps.v1.DeploymentList;

pub const Job = k8s.io.api.batch.v1.Job;
pub const JobList = k8s.io.api.batch.v1.JobList;

pub const ObjectMeta = k8s.io.apimachinery.pkg.apis.meta.v1.ObjectMeta;
pub const ListMeta = k8s.io.apimachinery.pkg.apis.meta.v1.ListMeta;

// Raw WatchEvent from apimachinery (used internally by watch.zig)
pub const RawWatchEvent = k8s.io.apimachinery.pkg.apis.meta.v1.WatchEvent;
