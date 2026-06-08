# Kubernetes LoadBalancer provider in Zig

## Design for initial implementation
Two components.
1. ziglb-operator: responsible for assigning IP to status.loadBalancer.ingress
    - No IPAM (static lb ip assignment)
    - Watch Service events using ../client-zig/
        - no informer, just lister&watcher API and reconciliation loop.
    - no leader election. single instance.
2. ziglb-agent: responsible for announcing the LoadBalancer Service IP via BGP
    - deployed as DaemonSet
    - BGP speaker using ../zigbgp/
    - Only client BGP session (peer must be passive)
    - No route import
    - Watch Service events to adevertise status.loadBalancer.ingress to peers

## Running connectivity test
connectivity-test:setup task deploys the following in docker environment:
- 2 node kind cluster
- external client container in the same network as the kind cluster
- ziglb-operator
- ziglb-agent
connectivity-test:run task tests the following capabilities of ziglb:
- provide LoadBalancer IP allocation and routing
- regression test for cluster ip

```sh
$ task connectivity-test:setup
$ task connectivity-test:run
```
