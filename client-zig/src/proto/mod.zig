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

// API group aliases
pub const v1 = k8s.io.api.core.v1;
pub const appsv1 = k8s.io.api.apps.v1;
pub const batchv1 = k8s.io.api.batch.v1;
pub const metav1 = k8s.io.apimachinery.pkg.apis.meta.v1;
