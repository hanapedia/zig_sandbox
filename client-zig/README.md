# client-zig

A Kubernetes client library for Zig 0.16, inspired by [client-go](https://github.com/kubernetes/client-go).

## Features

- **Authentication**: Supports both kubeconfig file (`~/.kube/config`) and in-cluster ServiceAccount token
- **TLS**: Uses [tls.zig](https://github.com/ianic/tls.zig) for reliable TLS connections
- **Type-safe API**: Generic typed client for Kubernetes resources
- **Protobuf types**: Generated from official Kubernetes proto definitions using [zig-protobuf](https://github.com/Arwalk/zig-protobuf)
- **Read operations**: Get and List for core/v1 resources (Pods, Services, ConfigMaps, Secrets, Namespaces, Nodes)

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

### Using kubeconfig (local development)

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

    // List pods in default namespace
    const pods = try k8s.pods(&client, "default").list(.{});
    defer pods.deinit();

    // Note: protobuf types use .items.items to access the slice
    for (pods.value.items.items) |pod| {
        const name = if (pod.metadata) |m| m.name orelse "unknown" else "unknown";
        std.debug.print("Pod: {s}\n", .{name});
    }
}
```

### In-cluster usage

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
│   │   └── Client.zig     # HTTP/TLS client using tls.zig
│   ├── api/
│   │   └── typed.zig      # Generic typed client with ResourceInfo
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

Generated types include `jsonDecode()` for parsing API responses:

```zig
const k8s = @import("client_zig");

// Use generated proto types
const Pod = k8s.proto.Pod;
const pod = try Pod.jsonDecode(json_response, .{ .ignore_unknown_fields = true }, allocator);
```

## Dependencies

- [tls.zig](https://github.com/ianic/tls.zig) - TLS implementation (workaround for std.http.Client TLS issues)
- [zig-protobuf](https://github.com/Arwalk/zig-protobuf) - Protobuf code generation and runtime

## Limitations

- Read-only operations (get, list) - no create/update/delete yet
- Core v1, Apps v1, and Batch v1 resources via generated proto types
- No watch/streaming support yet

## License

MIT
