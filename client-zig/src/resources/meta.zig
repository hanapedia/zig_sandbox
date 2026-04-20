//! Common Kubernetes metadata types used across all resources.
const std = @import("std");

/// ObjectMeta is metadata that all persisted Kubernetes resources have.
pub const ObjectMeta = struct {
    name: ?[]const u8 = null,
    namespace: ?[]const u8 = null,
    uid: ?[]const u8 = null,
    resourceVersion: ?[]const u8 = null,
    creationTimestamp: ?[]const u8 = null,
    deletionTimestamp: ?[]const u8 = null,
    labels: ?std.json.Value = null,
    annotations: ?std.json.Value = null,
    ownerReferences: ?[]const OwnerReference = null,
    finalizers: ?[]const []const u8 = null,
    generateName: ?[]const u8 = null,
    generation: ?i64 = null,
};

/// OwnerReference contains enough information to let you identify an owning object.
pub const OwnerReference = struct {
    apiVersion: []const u8,
    kind: []const u8,
    name: []const u8,
    uid: []const u8,
    controller: ?bool = null,
    blockOwnerDeletion: ?bool = null,
};

/// ListMeta describes metadata for list responses.
pub const ListMeta = struct {
    resourceVersion: ?[]const u8 = null,
    @"continue": ?[]const u8 = null,
    remainingItemCount: ?i64 = null,
    selfLink: ?[]const u8 = null,
};

/// Generic List wrapper for Kubernetes list responses.
/// Uses comptime generics to create type-safe list wrappers.
pub fn List(comptime T: type) type {
    return struct {
        apiVersion: ?[]const u8 = null,
        kind: ?[]const u8 = null,
        metadata: ListMeta = .{},
        items: []const T = &.{},
    };
}

/// Status is returned by the API server when an operation fails or when
/// the API server returns metadata about a successful operation.
pub const Status = struct {
    apiVersion: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    status: ?[]const u8 = null,
    message: ?[]const u8 = null,
    reason: ?[]const u8 = null,
    code: ?i32 = null,
    details: ?StatusDetails = null,
};

pub const StatusDetails = struct {
    name: ?[]const u8 = null,
    group: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    uid: ?[]const u8 = null,
    causes: ?[]const StatusCause = null,
    retryAfterSeconds: ?i32 = null,
};

pub const StatusCause = struct {
    reason: ?[]const u8 = null,
    message: ?[]const u8 = null,
    field: ?[]const u8 = null,
};

test "ObjectMeta parsing" {
    const json_str =
        \\{"name":"test-pod","namespace":"default","uid":"abc-123","resourceVersion":"12345"}
    ;
    const parsed = try std.json.parseFromSlice(ObjectMeta, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("test-pod", parsed.value.name.?);
    try std.testing.expectEqualStrings("default", parsed.value.namespace.?);
}

test "List parsing" {
    const TestResource = struct {
        metadata: ObjectMeta = .{},
        data: ?[]const u8 = null,
    };

    const json_str =
        \\{"apiVersion":"v1","kind":"TestList","items":[{"metadata":{"name":"item1"}},{"metadata":{"name":"item2"}}]}
    ;
    const parsed = try std.json.parseFromSlice(List(TestResource), std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.value.items.len);
    try std.testing.expectEqualStrings("item1", parsed.value.items[0].metadata.name.?);
}
