//! Generic typed client for Kubernetes resources.
//! Uses comptime generics to provide type-safe get/list operations.
const std = @import("std");
const watcher = @import("watch.zig");
const Client = @import("../client/Client.zig").Client;
const Status = @import("../proto/mod.zig").Status;

/// ResourceInfo describes the API path information for a Kubernetes resource.
pub const ResourceInfo = struct {
    const Self = @This();

    api_version: []const u8,
    api_group: []const u8,
    plural: []const u8,
    namespaced: bool,

    pub fn buildPath(self: Self, allocator: std.mem.Allocator, namespace: ?[]const u8, name: ?[]const u8, query_params: ?QueryParams) ![]const u8 {
        var path: std.ArrayList(u8) = .empty;
        errdefer path.deinit(allocator);

        if (self.api_group.len == 0) {
            try path.appendSlice(allocator, "/api/");
            try path.appendSlice(allocator, self.api_version);
        } else {
            try path.appendSlice(allocator, "/apis/");
            try path.appendSlice(allocator, self.api_group);
            try path.appendSlice(allocator, "/");
            try path.appendSlice(allocator, self.api_version);
        }

        if (self.namespaced) {
            try path.appendSlice(allocator, "/namespaces/");
            try path.appendSlice(allocator, namespace orelse "default");
        }

        try path.appendSlice(allocator, "/");
        try path.appendSlice(allocator, self.plural);
        if (name) |n| {
            try path.appendSlice(allocator, "/");
            try path.appendSlice(allocator, n);
        }

        if (query_params) |params| {
            if (try params.toString(allocator)) |query_str| {
                defer allocator.free(query_str);
                try path.appendSlice(allocator, query_str);
            }
        }
        return path.toOwnedSlice(allocator);
    }
};

/// Query parameters that can be added to any path
const QueryParams = union(enum) {
    list: ListOptions,
    delete: DeleteOptions,
    deleteCollection: DeleteCollectionOptions,
    watch: watcher.WatchOptions,
    create: CreateOptions,
    update: UpdateOptions,
    patch: PatchOptions,
    none,

    fn toString(self: QueryParams, allocator: std.mem.Allocator) !?[]const u8 {
        return switch (self) {
            .none => null,
            inline else => |opts| serializeQueryParams(allocator, opts),
        };
    }

    fn serializeQueryParams(allocator: std.mem.Allocator, options: anytype) !?[]const u8 {
        const T = @TypeOf(options);
        const fields = @typeInfo(T).@"struct".fields;

        var params: std.ArrayList(u8) = .empty;
        errdefer params.deinit(allocator);

        var first = true;
        inline for (fields) |field| {
            const value = @field(options, field.name);
            try appendParam(allocator, &params, &first, field.name, value);
        }

        if (params.items.len == 0) return null;
        return try params.toOwnedSlice(allocator);
    }

    fn appendParam(allocator: std.mem.Allocator, params: *std.ArrayList(u8), first: *bool, name: []const u8, value: anytype) !void {
        const T = @TypeOf(value);

        // Handle different types
        if (@typeInfo(T) == .optional) {
            if (value) |v| {
                try appendParam(allocator, params, first, name, v);
            }
        } else if (T == bool) {
            if (value) {
                try writeParam(allocator, params, first, name, "true");
            }
        } else if (@typeInfo(T) == .int) {
            var buf: [20]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
            try writeParam(allocator, params, first, name, str);
        } else if (T == []const u8) {
            try writeParam(allocator, params, first, name, value);
        }
    }

    fn writeParam(allocator: std.mem.Allocator, params: *std.ArrayList(u8), first: *bool, key: []const u8, value: []const u8) !void {
        try params.append(allocator, if (first.*) '?' else '&');
        first.* = false;
        try params.appendSlice(allocator, key);
        try params.append(allocator, '=');
        try params.appendSlice(allocator, value);
    }
};

/// Options for list operations.
pub const ListOptions = struct {
    labelSelector: ?[]const u8 = null,
    fieldSelector: ?[]const u8 = null,
    limit: ?i64 = null,
    continueToken: ?[]const u8 = null,
};

/// Options for create operations.
pub const CreateOptions = struct {
    dryRun: ?[]const u8 = null, // "All"
    fieldValidation: ?[]const u8 = null, // "Strict" | "Warn" | "Ignore"
};

/// Options for update operations.
pub const UpdateOptions = struct {
    dryRun: ?[]const u8 = null, // "All"
    fieldValidation: ?[]const u8 = null, // "Strict" | "Warn" | "Ignore"
};

/// Options for patch operations.
pub const PatchOptions = struct {
    dryRun: ?[]const u8 = null, // "All"
    fieldValidation: ?[]const u8 = null, // "Strict" | "Warn" | "Ignore"
    fieldManager: ?[]const u8 = null, // for server-side apply
};

/// Options for delete operations.
pub const DeleteOptions = struct {
    gracePeriodSeconds: ?i64 = null,
    propagationPolicy: ?[]const u8 = null, // "Orphaned" | "Background" | "Foreground"
    dryRun: ?[]const u8 = null, // "All"
};

/// Options for delete collection operations.
pub const DeleteCollectionOptions = struct {
    labelSelector: ?[]const u8 = null,
    fieldSelector: ?[]const u8 = null,
    gracePeriodSeconds: ?i64 = null,
    propagationPolicy: ?[]const u8 = null, // "Orphaned" | "Background" | "Foreground"
};

/// TypedClient provides type-safe operations for a specific Kubernetes resource type.
/// T is the resource type (e.g., Pod), L is the list type (e.g., PodList).
/// Resource metadata is provided via ResourceInfo rather than comptime declarations.
pub fn TypedClient(comptime T: type, comptime L: type) type {
    return struct {
        const Self = @This();

        client: *Client,
        namespace: ?[]const u8,
        info: ResourceInfo,

        /// Get a single resource by name.
        pub fn get(self: Self, name: []const u8) !Client.ProtoResult(T) {
            const path = try self.pathForGet(name);
            defer self.client.allocator.free(path);

            return self.client.get(T, path);
        }

        /// List all resources matching the criteria.
        pub fn list(self: Self, options: ListOptions) !Client.ProtoResult(L) {
            const path = try self.pathForList(options);
            defer self.client.allocator.free(path);

            return self.client.get(L, path);
        }

        /// Start watching resources.
        /// Returns a Watcher that yields typed WatchEvent(T) objects.
        ///
        /// Example:
        ///
        /// var watcher = try k8s.pods(&client, "default").watch(.{});
        /// defer watcher.deinit();
        ///
        /// while (try watcher.next()) |*event| {
        ///     defer event.deinit();
        ///     // handle event
        /// }
        pub fn watch(self: Self, options: watcher.WatchOptions) !watcher.Watcher(T) {
            return watcher.Watcher(T).init(self.client, self.namespace, self.info, options);
        }

        /// Create a new resource.
        pub fn create(self: Self, resource: T, options: CreateOptions) !Client.ProtoResult(T) {
            const path = try self.pathForCreate(options);
            defer self.client.allocator.free(path);

            return self.client.post(T, path, resource);
        }

        /// Update (replace) an existing resource.
        /// The resource must have metadata.resourceVersion set.
        pub fn update(self: Self, name: []const u8, resource: T, options: UpdateOptions) !Client.ProtoResult(T) {
            const path = try self.pathForUpdate(name, options);
            defer self.client.allocator.free(path);

            return self.client.put(T, path, resource);
        }

        /// Delete a resource by name.
        /// Returns Status on success.
        pub fn delete(self: Self, name: []const u8, options: DeleteOptions) !Client.ProtoResult(Status) {
            const path = try self.pathForDelete(name, options);
            defer self.client.allocator.free(path);

            return self.client.deleteResource(Status, path);
        }

        /// Delete multiple resources matching the criteria.
        /// Returns Status on success.
        pub fn deleteCollection(self: Self, options: DeleteCollectionOptions) !Client.ProtoResult(Status) {
            const path = try self.pathForDeleteCollection(options);
            defer self.client.allocator.free(path);

            return self.client.deleteResource(Status, path);
        }

        /// Patch a resource using strategic merge patch (default).
        pub fn patchStrategicMerge(self: Self, name: []const u8, patch_json: []const u8, options: PatchOptions) !Client.ProtoResult(T) {
            const path = try self.pathForPatch(name, options);
            defer self.client.allocator.free(path);

            return self.client.patch(T, path, patch_json, .strategic_merge_patch);
        }

        /// Patch a resource using JSON patch (RFC 6902).
        pub fn patchJson(self: Self, name: []const u8, patch_json: []const u8, options: PatchOptions) !Client.ProtoResult(T) {
            const path = try self.pathForPatch(name, options);
            defer self.client.allocator.free(path);

            return self.client.patch(T, path, patch_json, .json_patch);
        }

        /// Patch a resource using merge patch (RFC 7386).
        pub fn patchMerge(self: Self, name: []const u8, patch_json: []const u8, options: PatchOptions) !Client.ProtoResult(T) {
            const path = try self.pathForPatch(name, options);
            defer self.client.allocator.free(path);

            return self.client.patch(T, path, patch_json, .merge_patch);
        }

        /// Server-side apply a resource.
        pub fn apply(self: Self, name: []const u8, patch_yaml: []const u8, options: PatchOptions) !Client.ProtoResult(T) {
            const path = try self.pathForPatch(name, options);
            defer self.client.allocator.free(path);

            return self.client.patch(T, path, patch_yaml, .apply_patch);
        }

        // ====================================================================
        // Path builders
        // ====================================================================

        /// GET single resource
        pub fn pathForGet(self: Self, name: []const u8) ![]const u8 {
            return self.info.buildPath(self.client.allocator, self.namespace, name, null);
        }

        /// LIST resources
        pub fn pathForList(self: Self, options: ListOptions) ![]const u8 {
            return self.info.buildPath(self.client.allocator, self.namespace, null, .{ .list = options });
        }

        /// WATCH resources
        pub fn pathForWatch(self: Self, options: watcher.WatchOptions) ![]const u8 {
            return self.info.buildPath(self.client.allocator, self.namespace, null, .{ .watch = options });
        }

        /// CREATE resource
        pub fn pathForCreate(self: Self, options: CreateOptions) ![]const u8 {
            return self.info.buildPath(self.client.allocator, self.namespace, null, .{ .create = options });
        }

        /// UPDATE resource
        pub fn pathForUpdate(self: Self, name: []const u8, options: UpdateOptions) ![]const u8 {
            return self.info.buildPath(self.client.allocator, self.namespace, name, .{ .update = options });
        }

        /// DELETE single resource
        pub fn pathForDelete(self: Self, name: []const u8, options: DeleteOptions) ![]const u8 {
            return self.info.buildPath(self.client.allocator, self.namespace, name, .{ .delete = options });
        }

        /// DELETE collection
        pub fn pathForDeleteCollection(self: Self, options: DeleteCollectionOptions) ![]const u8 {
            return self.info.buildPath(self.client.allocator, self.namespace, null, .{ .deleteCollection = options });
        }

        /// PATCH resource
        pub fn pathForPatch(self: Self, name: []const u8, options: PatchOptions) ![]const u8 {
            return self.info.buildPath(self.client.allocator, self.namespace, name, .{ .patch = options });
        }
    };
}

test "TypedClient path building" {
    const TestResource = struct {};
    const TestResourceList = struct {};

    const io = std.testing.io;
    const allocator = std.testing.allocator;

    // Create a mock client (we won't make actual requests)
    var client = try Client.init(io, allocator, .{
        .host = "https://localhost:6443",
    });
    defer client.deinit();

    const typed = TypedClient(TestResource, TestResourceList){
        .client = &client,
        .namespace = "default",
        .info = .{
            .api_version = "v1",
            .api_group = "",
            .plural = "pods",
            .namespaced = true,
        },
    };

    // Test resource path
    const resource_path = try typed.buildResourcePath("my-pod");
    defer allocator.free(resource_path);
    try std.testing.expectEqualStrings("/api/v1/namespaces/default/pods/my-pod", resource_path);

    // Test list path
    const list_path = try typed.buildListPath(.{});
    defer allocator.free(list_path);
    try std.testing.expectEqualStrings("/api/v1/namespaces/default/pods", list_path);

    // Test list path with selector
    const list_path_selector = try typed.buildListPath(.{ .labelSelector = "app=nginx" });
    defer allocator.free(list_path_selector);
    try std.testing.expectEqualStrings("/api/v1/namespaces/default/pods?labelSelector=app=nginx", list_path_selector);
}

test "TypedClient cluster-scoped resource" {
    const ClusterResource = struct {};
    const ClusterResourceList = struct {};

    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var client = try Client.init(io, allocator, .{
        .host = "https://localhost:6443",
    });
    defer client.deinit();

    const typed = TypedClient(ClusterResource, ClusterResourceList){
        .client = &client,
        .namespace = null,
        .info = .{
            .api_version = "v1",
            .api_group = "",
            .plural = "nodes",
            .namespaced = false,
        },
    };

    const path = try typed.buildResourcePath("node-1");
    defer allocator.free(path);
    try std.testing.expectEqualStrings("/api/v1/nodes/node-1", path);
}

test "TypedClient apps group resource" {
    const Deployment = struct {};
    const DeploymentList = struct {};

    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var client = try Client.init(io, allocator, .{
        .host = "https://localhost:6443",
    });
    defer client.deinit();

    const typed = TypedClient(Deployment, DeploymentList){
        .client = &client,
        .namespace = "default",
        .info = .{
            .api_version = "v1",
            .api_group = "apps",
            .plural = "deployments",
            .namespaced = true,
        },
    };

    const path = try typed.buildResourcePath("nginx");
    defer allocator.free(path);
    try std.testing.expectEqualStrings("/apis/apps/v1/namespaces/default/deployments/nginx", path);
}
