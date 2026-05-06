# client-zig

A Kubernetes client library for Zig 0.16, inspired by [client-go](https://github.com/kubernetes/client-go).

## Features

- **Authentication**: Supports both kubeconfig file (`~/.kube/config`) and in-cluster ServiceAccount token
- **TLS**: Uses [tls.zig](https://github.com/ianic/tls.zig) for reliable TLS connections
- **Type-safe API**: Generic typed client for Kubernetes resources
- **Protobuf encoding**: Uses protobuf for efficient wire format (both requests and responses)
- **Full CRUD operations**: Get, List, Create, Update, Delete, and Patch
- **Watch support**: Real-time streaming of resource changes with typed events
- **Multiple patch types**: Strategic merge, JSON patch, merge patch, and server-side apply

## Requirements

- Zig 0.16.0+
- [Task](https://taskfile.dev/) (for development workflows)
- Docker & kind (for in-cluster testing)

## Quick Start

```bash
# Clone and setup
git clone <repo>
cd client-zig

# Generate proto types (first time only)
task proto:all

# Build
zig build

# Run tests
zig build test
```

## Usage

### Basic Setup

```zig
const std = @import("std");
const k8s = @import("client_zig");

pub fn main() !void {
    const init = std.process.Init.init();
    const io = init.io;
    const allocator = std.heap.page_allocator;

    // Load kubeconfig
    var config = try k8s.kubeconfig.load(io, .{ .block = .global }, allocator, null);
    defer config.deinit(allocator);

    // Create client
    var client = try k8s.Client.init(io, allocator, .{
        .host = config.host,
        .token = config.token,
        .ca_cert = config.ca_cert,
    });
    defer client.deinit();
}
```

### List Resources

```zig
// List pods in default namespace
var pods = try k8s.pods(&client, "default").list(.{});
defer pods.deinit();

for (pods.value.items.items) |pod| {
    const name = if (pod.metadata) |m| m.name orelse "unknown" else "unknown";
    std.debug.print("Pod: {s}\n", .{name});
}
```

### Create Resources

```zig
// Create a ConfigMap
var cm = k8s.ConfigMap{
    .metadata = k8s.ObjectMeta{
        .name = "my-config",
        .namespace = "default",
    },
};
try cm.data.append(allocator, .{ .key = "key1", .value = "value1" });
defer cm.data.deinit(allocator);

var result = try k8s.configMaps(&client, "default").create(cm, .{});
defer result.deinit();
```

### Update Resources

```zig
// Update requires resourceVersion for optimistic concurrency
var cm = k8s.ConfigMap{
    .metadata = k8s.ObjectMeta{
        .name = "my-config",
        .namespace = "default",
        .resourceVersion = existing.metadata.?.resourceVersion,
    },
};
try cm.data.append(allocator, .{ .key = "key1", .value = "updated-value" });
defer cm.data.deinit(allocator);

var result = try k8s.configMaps(&client, "default").update("my-config", cm, .{});
defer result.deinit();
```

### Delete Resources

```zig
// Delete returns a Status object
var result = try k8s.configMaps(&client, "default").delete("my-config", .{});
defer result.deinit();
```

### Watch Resources

```zig
// Watch pods with the high-level Watcher API
var watcher = try k8s.Watcher(k8s.Pod).init(
    &client,
    "default",
    k8s.resource_info.pod,
    .{}, // WatchOptions
);
defer watcher.deinit();

while (try watcher.next()) |event_val| {
    var event = event_val;
    defer event.deinit();

    const pod = event.object();
    const name = if (pod.metadata) |m| m.name orelse "?" else "?";

    std.debug.print("[{s}] {s}\n", .{
        @tagName(event.event_type), // ADDED, MODIFIED, DELETED, BOOKMARK
        name,
    });
}
```

### In-cluster Usage

```zig
// Load in-cluster config (uses ServiceAccount token)
var config = try k8s.in_cluster.InClusterConfig.load(io, allocator);
defer config.deinit(allocator);

var client = try k8s.Client.init(io, allocator, .{
    .host = config.host,
    .token = config.token,
    .ca_cert = config.ca_cert,
});
```

## Supported Resources

| Resource | API Group | Operations |
|----------|-----------|------------|
| Pod | core/v1 | get, list, create, update, delete, patch, watch |
| Service | core/v1 | get, list, create, update, delete, patch, watch |
| ConfigMap | core/v1 | get, list, create, update, delete, patch, watch |
| Secret | core/v1 | get, list, create, update, delete, patch, watch |
| Namespace | core/v1 | get, list, create, update, delete, patch, watch |
| Node | core/v1 | get, list, create, update, delete, patch, watch |
| Deployment | apps/v1 | get, list, create, update, delete, patch, watch |
| Job | batch/v1 | get, list, create, update, delete, patch, watch |

## Project Structure

```
client-zig/
├── src/
│   ├── main.zig           # Example CLI application
│   ├── root.zig           # Library entry point
│   ├── auth/
│   │   ├── kubeconfig.zig # Kubeconfig file parser
│   │   └── in_cluster.zig # In-cluster auth (ServiceAccount)
│   ├── client/
│   │   └── Client.zig     # HTTP/TLS client with CRUD operations
│   ├── api/
│   │   ├── typed.zig      # Generic typed client with ResourceInfo
│   │   └── watch.zig      # Watch streaming (WatchStream, Watcher)
│   └── proto/
│       ├── mod.zig        # Module exports for proto types
│       └── k8s/           # Generated protobuf types (gitignored)
├── manifests/             # Kubernetes manifests for in-cluster testing
├── Dockerfile
├── Taskfile.yml
└── build.zig
```

## Development

### Task Commands

| Command | Description |
|---------|-------------|
| `task build` | Build the binary |
| `task test` | Run tests |
| `task clean` | Clean build artifacts |
| `task proto:all` | Download and generate proto types |
| `task proto:clean` | Remove proto files and generated code |
| `task image:load` | Build and load Docker image into kind |
| `task k8s:deploy` | Deploy to Kubernetes |
| `task k8s:redeploy` | Full rebuild and redeploy cycle |

### In-cluster Testing with kind

```bash
# Create kind cluster (if needed)
kind create cluster

# Build, load image, and deploy
task k8s:redeploy

# Check logs
kubectl logs zig-k8s-client
```

### Protobuf Code Generation

Proto types are generated from Kubernetes v1.33 definitions:

```bash
# Download protos, create symlinks, generate Zig code
task proto:all

# Or step by step:
task proto:download   # Download from kubernetes/api and kubernetes/apimachinery
task proto:symlinks   # Create import path symlinks
task proto:generate   # Run protoc and zig fmt
```

## Roadmap

Planned features inspired by client-go:

- [ ] **Informer**: Cached watch with local store for efficient resource tracking
- [ ] **Workqueue**: Rate-limited work queue for controller patterns
- [ ] **SharedInformerFactory**: Shared informers to reduce API server load
- [ ] **Lister**: Read from local cache instead of API server
- [ ] **Retry with backoff**: Automatic retry with exponential backoff
- [ ] **Leader election**: For high-availability controllers

## Dependencies

- [tls.zig](https://github.com/ianic/tls.zig) - TLS implementation
- [zig-protobuf](https://github.com/Arwalk/zig-protobuf) - Protobuf code generation and runtime

## License

MIT
