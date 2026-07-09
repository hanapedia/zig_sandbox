# Zig Netlink Library

## Overview

A high-level Zig library for interacting with Linux Netlink APIs, focused on common networking operations required by routing daemons, BGP speakers, CNIs, load balancers, and network automation tools.

The goal is to provide a small, idiomatic Zig API for the most commonly used networking objects while remaining significantly simpler than full-featured libraries such as vishvananda/netlink.

The initial scope focuses on CRUD operations for:

* Links
* Addresses
* Routes

including support for Geneve tunnel interfaces.

---

# Goals

## Primary Goals

* Provide an ergonomic Zig interface to Netlink.
* Support common networking operations through high-level APIs.
* Hide Netlink message encoding and attribute parsing from users.
* Support both IPv4 and IPv6.
* Serve as a foundation for future networking projects.

## Non-Goals

* Full iproute2 feature parity.
* Traffic control (tc) support.
* Policy routing rule management.
* XFRM/IPsec support.
* Wireless networking support.
* Full coverage of every Linux link type.

---

# Architecture

The library is organized into two layers.

## Transport Layer

Responsible for:

* Opening Netlink sockets
* Sending requests
* Receiving responses
* Multipart dump handling
* Error handling
* Netlink attribute encoding and decoding

Example:

```zig
const nl = try NetlinkSocket.init(allocator);

try nl.send(...);
const msg = try nl.receive();
```

## High-Level APIs

Provides typed abstractions over Linux networking objects.

Example:

```zig
const routes = try nl.route.list();

try nl.route.add(.{
    .dst = destination,
    .gateway = gateway,
});
```

---

# Project Structure

```text
src/
└── netlink/
    ├── socket.zig
    ├── message.zig
    ├── attribute.zig
    ├── constants.zig
    ├── link.zig
    ├── addr.zig
    └── route.zig
```

---

# Initial Scope

## Link Management

Support CRUD operations for network interfaces.

### Features

* List interfaces
* Get interface details
* Create interfaces
* Delete interfaces
* Set interface up/down

### API

```zig
const links = try nl.link.list();

const link = try nl.link.get("eth0");

try nl.link.setUp(link.index);

try nl.link.delete(link.index);
```

### Initial Link Types

* Physical interfaces
* Dummy interfaces
* Veth pairs
* Geneve tunnels

---

## Address Management

Support CRUD operations for interface addresses.

### Features

* List addresses
* Add addresses
* Delete addresses

### API

```zig
try nl.addr.add(.{
    .link_index = idx,
    .prefix = prefix,
});

try nl.addr.delete(...);

const addrs = try nl.addr.list(idx);
```

---

## Route Management

Support CRUD operations for routes.

### Features

* List routes
* Add routes
* Delete routes

### API

```zig
try nl.route.add(.{
    .dst = destination,
    .gateway = gateway,
});

try nl.route.delete(route);

const routes = try nl.route.list();
```

---

# Geneve Support

Geneve support will be implemented as a specialized link type using the generic Netlink link infrastructure.

### Features

* Create Geneve interfaces
* Delete Geneve interfaces
* Query Geneve configuration

### Example

```zig
try nl.link.add(.{
    .name = "geneve0",
    .kind = .geneve,
    .geneve = .{
        .vni = 100,
        .remote = remote_addr,
    },
});
```

### Internal Representation

Geneve interfaces are represented through nested link attributes:

```text
RTM_NEWLINK

IFLA_IFNAME

IFLA_LINKINFO
 ├── IFLA_INFO_KIND = "geneve"
 └── IFLA_INFO_DATA
      ├── IFLA_GENEVE_ID
      └── IFLA_GENEVE_REMOTE
```

The attribute handling infrastructure should be designed generically so that future tunnel types can be added with minimal additional code.

---

# Development Plan

## Phase 1: Core Netlink Infrastructure

Implement:

* Netlink socket management
* Message encoding/decoding
* Multipart response handling
* Error handling
* Generic attribute parsing

Deliverable:

```bash
ip link show
```

equivalent functionality.

---

## Phase 2: Link CRUD

Implement:

* List links
* Get link details
* Create links
* Delete links
* Interface state changes

Initial validation will focus on:

* Physical interfaces
* Dummy interfaces
* Veth pairs

---

## Phase 3: Address CRUD

Implement:

* List addresses
* Add addresses
* Delete addresses

for IPv4 and IPv6.

---

## Phase 4: Route CRUD

Implement:

* List routes
* Add routes
* Delete routes

for IPv4 and IPv6.

---

## Phase 5: Geneve Support

Implement:

* Geneve creation
* Geneve deletion
* Geneve inspection

using the generic link framework developed in earlier phases.

---

# Testing Strategy

## Unit Tests

* Message encoding
* Message decoding
* Attribute parsing
* Nested attribute parsing

## Integration Tests

Run in temporary network namespaces.

Test coverage:

* Link CRUD
* Address CRUD
* Route CRUD
* Geneve creation and deletion

Example workflow:

```text
Create namespace
Create veth pair
Assign addresses
Add routes
Create Geneve tunnel
Verify state
Destroy namespace
```

---

# Future Work

Potential future additions include:

* Network namespace management
* Policy routing rules
* Neighbor table management (ARP/NDP)
* Route and link event subscriptions
* VXLAN support
* Additional virtual interface types
* Traffic control (tc) integration

These features are intentionally excluded from the initial scope to keep the project focused and maintainable.

