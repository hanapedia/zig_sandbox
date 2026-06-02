const std = @import("std");
const k8s = @import("client_zig");
const ipam = @import("../ipam/static.zig");

const SVC_TYPE_LB = "LoadBalancer";

const StatusPatch = struct {
    status: struct {
        loadBalancer: struct {
            ingress: []const Ingress,
        },
    },
};
const Ingress = struct { ip: []const u8, ipMode: []const u8 };

pub const ServiceReconciler = struct {
    /// must share the allocator with the producing-end of the event_queue.
    allocator: std.mem.Allocator,
    io: std.Io,

    typed_client: k8s.TypedClient(k8s.v1.Service, k8s.v1.ServiceList),
    event_queue: *k8s.EventQueue(k8s.v1.Service),
    ip_allocator: *ipam.StaticIPAllocator,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, tc: k8s.TypedClient(k8s.v1.Service, k8s.v1.ServiceList), eq: *k8s.EventQueue(k8s.v1.Service)) !ServiceReconciler {
        const ip_allocator = try allocator.create(ipam.StaticIPAllocator);
        errdefer allocator.destroy(ip_allocator);
        ip_allocator.* = try ipam.StaticIPAllocator.init(allocator);
        return .{
            .allocator = allocator,
            .io = io,
            .typed_client = tc,
            .event_queue = eq,
            .ip_allocator = ip_allocator,
        };
    }

    pub fn deinit(self: *ServiceReconciler) void {
        self.ip_allocator.deinit();
        self.allocator.destroy(self.ip_allocator);
    }

    pub fn start(self: *ServiceReconciler) std.Io.Cancelable!void {
        std.debug.print("Reconciler started.\n", .{});
        self.run() catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            else => std.debug.print("ServiceReconciler error: {}\n", .{err}),
        };
    }

    fn run(self: *ServiceReconciler) !void {
        while (true) {
            const obj = try self.event_queue.dequeue();
            errdefer obj.deinit(self.allocator);

            // just for logging
            const metadata = obj.metadata orelse return error.NoMetadata;
            const _name = metadata.name orelse return error.NoName;
            const _namespace = metadata.namespace orelse return error.NoNamespace;
            std.debug.print("Dequeued Service. {s}/{s}\n", .{ _namespace, _name });

            const spec = obj.spec orelse return error.NoSpec;
            const svc_type = spec.type orelse return error.NoServiceType;
            // check svc type
            if (!std.mem.eql(u8, svc_type, SVC_TYPE_LB)) {
                obj.deinit(self.allocator);
                continue;
            }

            // take copy and deinit
            // const metadata = obj.metadata orelse return error.NoMetadata;
            // const _name = metadata.name orelse return error.NoName;
            // const _namespace = metadata.namespace orelse return error.NoNamespace;
            const name = try self.allocator.dupe(u8, _name);
            errdefer self.allocator.free(name);
            const namespace = try self.allocator.dupe(u8, _namespace);
            errdefer self.allocator.free(namespace);
            obj.deinit(self.allocator);

            self.reconcile(namespace, name) catch |err| {
                std.debug.print("ServiceReconciler reconcile error: {}\n", .{err});
            };
            self.allocator.free(name);
            self.allocator.free(namespace);
        }
    }

    fn reconcile(self: *ServiceReconciler, namespace: []const u8, name: []const u8) !void {
        // get again
        std.debug.print("Reconciling Service. {s}/{s}\n", .{ namespace, name });
        var svc = try self.typed_client.get(namespace, name);
        defer svc.deinit();

        // TODO: handle deletion and dealloc
        const status = svc.value.status orelse return;
        if (status.loadBalancer) |lb| {
            if (lb.ingress.items.len == 0) {
                try self.allocIPAndPatch(namespace, name);
            }
        } else {
            try self.allocIPAndPatch(namespace, name);
        }
    }

    fn allocIPAndPatch(self: *ServiceReconciler, namespace: []const u8, name: []const u8) !void {
        const ip = try self.ip_allocator.alloc();

        const ip_str = try std.fmt.allocPrint(self.allocator, "{}.{}.{}.{}", .{ ip[0], ip[1], ip[2], ip[3] });
        defer self.allocator.free(ip_str);

        const ingress = [_]Ingress{
            .{ .ip = ip_str, .ipMode = "VIP" },
        };
        const patch: StatusPatch = .{ .status = .{ .loadBalancer = .{ .ingress = &ingress } } };

        const patch_json = try std.json.Stringify.valueAlloc(self.allocator, patch, .{ .emit_null_optional_fields = false });
        defer self.allocator.free(patch_json);
        std.debug.print("patch json. {s}/{s}: patch={s}\n", .{ namespace, name, patch_json });

        var res = try self.typed_client.patchMergeSubresource(namespace, name, "status", patch_json, .{});
        res.deinit();
    }
};
