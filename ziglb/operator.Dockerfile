FROM debian:bookworm-20250520-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends curl xz-utils ca-certificates && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz | tar -xJ -C /usr/local && \
    ln -s /usr/local/zig-x86_64-linux-0.16.0/zig /usr/local/bin/zig

WORKDIR /build

# Copy local path dependencies and the project
COPY client-zig/ client-zig/
COPY zigbgp/ zigbgp/
COPY ziglb/ ziglb/

WORKDIR /build/ziglb
RUN --mount=type=cache,target=/root/.cache/zig \
    zig build -Doptimize=ReleaseSafe

FROM debian:bookworm-20250520-slim

# Add ca-certificates for HTTPS (in-cluster uses HTTPS)
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

# Copy the built binary
COPY --from=builder /build/ziglb/zig-out/bin/ziglb-operator /usr/local/bin/ziglb-operator

# Run as non-root
RUN useradd -u 1000 -M appuser
USER appuser

ENTRYPOINT ["/usr/local/bin/ziglb-operator"]
