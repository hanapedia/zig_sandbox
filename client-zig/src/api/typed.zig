//! Generic typed client for Kubernetes resources.
//! Uses comptime generics to provide type-safe get/list operations.
const std = @import("std");
const Client = @import("../client/Client.zig").Client;
const meta = @import("../resources/meta.zig");

/// Options for list operations.
pub const ListOptions = struct {
    labelSelector: ?[]const u8 = null,
    fieldSelector: ?[]const u8 = null,
    limit: ?i64 = null,
    continueToken: ?[]const u8 = null,
};

/// TypedClient provides type-safe operations for a specific Kubernetes resource type.
/// The resource type T must have these comptime declarations:
/// - resource_api_version: []const u8 (e.g., "v1")
/// - resource_api_group: []const u8 (e.g., "" for core, "apps" for apps group)
/// - resource_plural: []const u8 (e.g., "pods")
/// - resource_namespaced: bool
pub fn TypedClient(comptime T: type) type {
    // Compile-time validation
    if (!@hasDecl(T, "resource_api_version")) {
        @compileError("Resource type must have 'resource_api_version' declaration");
    }
    if (!@hasDecl(T, "resource_plural")) {
        @compileError("Resource type must have 'resource_plural' declaration");
    }
    if (!@hasDecl(T, "resource_namespaced")) {
        @compileError("Resource type must have 'resource_namespaced' declaration");
    }

    return struct {
        const Self = @This();

        client: *Client,
        namespace: ?[]const u8,

        /// Get a single resource by name.
        pub fn get(self: Self, name: []const u8) !std.json.Parsed(T) {
            const path = try self.buildResourcePath(name);
            defer self.client.allocator.free(path);

            return self.client.get(T, path);
        }

        /// List all resources matching the criteria.
        pub fn list(self: Self, options: ListOptions) !std.json.Parsed(meta.List(T)) {
            const path = try self.buildListPath(options);
            defer self.client.allocator.free(path);

            return self.client.get(meta.List(T), path);
        }

        fn buildResourcePath(self: Self, name: []const u8) ![]const u8 {
            const api_group = if (@hasDecl(T, "resource_api_group")) T.resource_api_group else "";

            if (T.resource_namespaced) {
                const ns = self.namespace orelse "default";

                if (api_group.len == 0) {
                    return try std.fmt.allocPrint(self.client.allocator, "/api/{s}/namespaces/{s}/{s}/{s}", .{
                        T.resource_api_version,
                        ns,
                        T.resource_plural,
                        name,
                    });
                } else {
                    return try std.fmt.allocPrint(self.client.allocator, "/apis/{s}/{s}/namespaces/{s}/{s}/{s}", .{
                        api_group,
                        T.resource_api_version,
                        ns,
                        T.resource_plural,
                        name,
                    });
                }
            } else {
                // Cluster-scoped resource
                if (api_group.len == 0) {
                    return try std.fmt.allocPrint(self.client.allocator, "/api/{s}/{s}/{s}", .{
                        T.resource_api_version,
                        T.resource_plural,
                        name,
                    });
                } else {
                    return try std.fmt.allocPrint(self.client.allocator, "/apis/{s}/{s}/{s}/{s}", .{
                        api_group,
                        T.resource_api_version,
                        T.resource_plural,
                        name,
                    });
                }
            }
        }

        fn buildListPath(self: Self, options: ListOptions) ![]const u8 {
            const api_group = if (@hasDecl(T, "resource_api_group")) T.resource_api_group else "";
            const allocator = self.client.allocator;

            // Build base path
            var base_path: []const u8 = undefined;

            if (T.resource_namespaced) {
                if (self.namespace) |ns| {
                    if (api_group.len == 0) {
                        base_path = try std.fmt.allocPrint(allocator, "/api/{s}/namespaces/{s}/{s}", .{
                            T.resource_api_version,
                            ns,
                            T.resource_plural,
                        });
                    } else {
                        base_path = try std.fmt.allocPrint(allocator, "/apis/{s}/{s}/namespaces/{s}/{s}", .{
                            api_group,
                            T.resource_api_version,
                            ns,
                            T.resource_plural,
                        });
                    }
                } else {
                    // List across all namespaces
                    if (api_group.len == 0) {
                        base_path = try std.fmt.allocPrint(allocator, "/api/{s}/{s}", .{
                            T.resource_api_version,
                            T.resource_plural,
                        });
                    } else {
                        base_path = try std.fmt.allocPrint(allocator, "/apis/{s}/{s}/{s}", .{
                            api_group,
                            T.resource_api_version,
                            T.resource_plural,
                        });
                    }
                }
            } else {
                // Cluster-scoped resource
                if (api_group.len == 0) {
                    base_path = try std.fmt.allocPrint(allocator, "/api/{s}/{s}", .{
                        T.resource_api_version,
                        T.resource_plural,
                    });
                } else {
                    base_path = try std.fmt.allocPrint(allocator, "/apis/{s}/{s}/{s}", .{
                        api_group,
                        T.resource_api_version,
                        T.resource_plural,
                    });
                }
            }

            // Check if we need query parameters
            const has_params = options.labelSelector != null or
                options.fieldSelector != null or
                options.limit != null or
                options.continueToken != null;

            if (!has_params) {
                return base_path;
            }

            // Build query string
            defer allocator.free(base_path);

            var query_parts: [4][]const u8 = undefined;
            var query_count: usize = 0;

            var label_sel: ?[]const u8 = null;
            var field_sel: ?[]const u8 = null;
            var limit_str: ?[]const u8 = null;
            var continue_str: ?[]const u8 = null;

            if (options.labelSelector) |selector| {
                label_sel = try std.fmt.allocPrint(allocator, "labelSelector={s}", .{selector});
                query_parts[query_count] = label_sel.?;
                query_count += 1;
            }
            errdefer if (label_sel) |s| allocator.free(s);

            if (options.fieldSelector) |selector| {
                field_sel = try std.fmt.allocPrint(allocator, "fieldSelector={s}", .{selector});
                query_parts[query_count] = field_sel.?;
                query_count += 1;
            }
            errdefer if (field_sel) |s| allocator.free(s);

            if (options.limit) |limit| {
                limit_str = try std.fmt.allocPrint(allocator, "limit={d}", .{limit});
                query_parts[query_count] = limit_str.?;
                query_count += 1;
            }
            errdefer if (limit_str) |s| allocator.free(s);

            if (options.continueToken) |token| {
                continue_str = try std.fmt.allocPrint(allocator, "continue={s}", .{token});
                query_parts[query_count] = continue_str.?;
                query_count += 1;
            }
            errdefer if (continue_str) |s| allocator.free(s);

            // Join with &
            const query = try std.mem.join(allocator, "&", query_parts[0..query_count]);
            defer allocator.free(query);

            // Free individual parts
            if (label_sel) |s| allocator.free(s);
            if (field_sel) |s| allocator.free(s);
            if (limit_str) |s| allocator.free(s);
            if (continue_str) |s| allocator.free(s);

            return try std.fmt.allocPrint(allocator, "{s}?{s}", .{ base_path, query });
        }
    };
}

test "TypedClient path building" {
    const TestResource = struct {
        pub const resource_api_version = "v1";
        pub const resource_api_group = "";
        pub const resource_plural = "pods";
        pub const resource_namespaced = true;
    };

    const io = std.testing.io;
    const allocator = std.testing.allocator;

    // Create a mock client (we won't make actual requests)
    var client = try Client.init(io, allocator, .{
        .host = "https://localhost:6443",
    });
    defer client.deinit();

    const typed = TypedClient(TestResource){
        .client = &client,
        .namespace = "default",
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
    const ClusterResource = struct {
        pub const resource_api_version = "v1";
        pub const resource_api_group = "";
        pub const resource_plural = "nodes";
        pub const resource_namespaced = false;
    };

    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var client = try Client.init(io, allocator, .{
        .host = "https://localhost:6443",
    });
    defer client.deinit();

    const typed = TypedClient(ClusterResource){
        .client = &client,
        .namespace = null,
    };

    const path = try typed.buildResourcePath("node-1");
    defer allocator.free(path);
    try std.testing.expectEqualStrings("/api/v1/nodes/node-1", path);
}
