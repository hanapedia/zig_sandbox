# zig_sandbox

A sandbox for learning Zig alongside systems topics like eBPF, BGP, and Kubernetes.

## Subprojects

### [bpf_sandbox](./bpf_sandbox)
Experiments with eBPF programs written in Zig. Explores how to write and load BPF programs from Zig.

### [zigbgp](./zigbgp)
A BGP speaker implemented in Zig, inspired by [GoBGP](https://github.com/osrg/gobgp). Implements the BGP protocol for route advertisement between peers.

### [client-zig](./client-zig)
A Kubernetes client library for Zig, inspired by [client-go](https://github.com/kubernetes/client-go). Supports kubeconfig and in-cluster auth, TLS, protobuf encoding, full CRUD operations, and Watch streaming.

### [ziglb](./ziglb)
A Kubernetes LoadBalancer provider written in Zig, built on top of `zigbgp` and `client-zig`. Consists of two components:
- **ziglb-operator** — watches Service events and assigns LoadBalancer IPs
- **ziglb-agent** — runs as a DaemonSet and announces LoadBalancer IPs to BGP peers
