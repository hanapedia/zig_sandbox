const std = @import("std");
const kubeconfig = @import("kubeconfig.zig");
const in_cluster = @import("in_cluster.zig");

pub fn loadConfig(io: std.Io, environ_map: *std.process.Environ.Map, allocator: std.mem.Allocator) !Config {
    // Try kubeconfig first, fall back to in-cluster config
    if (kubeconfig.load(io, environ_map, allocator, null)) |cfg| {
        return .{
            .allocator = allocator,
            .host = cfg.host,
            .token = cfg.token,
            .ca_cert = cfg.ca_cert,
            .skip_tls_verify = cfg.skip_tls_verify,
            .namespace = cfg.namespace,
            .source = .kubeconfig,
        };
    } else |_| {
        // Fall back to in-cluster config
        const in_cluster_config = try in_cluster.InClusterConfig.load(io, environ_map, allocator);
        return .{
            .allocator = allocator,
            .host = in_cluster_config.host,
            .token = in_cluster_config.token,
            .ca_cert = in_cluster_config.ca_cert,
            .skip_tls_verify = false,
            .namespace = in_cluster_config.namespace,
            .source = .in_cluster,
        };
    }
}

pub const Config = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    token: ?[]const u8,
    ca_cert: ?[]const u8,
    skip_tls_verify: bool,
    namespace: ?[]const u8,
    source: enum { kubeconfig, in_cluster },

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.host);
        if (self.token) |t| self.allocator.free(t);
        if (self.ca_cert) |c| self.allocator.free(c);
        if (self.namespace) |n| self.allocator.free(n);
    }
};
