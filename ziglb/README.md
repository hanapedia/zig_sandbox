# Kubernetes LoadBalancer provider in Zig

## Design for initial implementation
Two components.
1. ziglb-operator: responsible for assigning IP to status.loadBalancer.ingress
    - No IPAM (static lb ip assignment)
    - Watch Service events using ../client-zig/
        - no informer, just watch API and reconciliation loop.
    - no leader election. single instance.
2. ziglb-agent: responsible for announcing the LoadBalancer Service IP via BGP
    - intended to be deployed as DaemonSet
    - BGP speaker using ../client-zig/
    - Only client BGP session (peer must be passive)
    - No route import
    - Watch Service events to adevertise status.loadBalancer.ingress to peers
