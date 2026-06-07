FROM alpine:3.23.4 AS builder

RUN apk add --no-cache curl xz ca-certificates

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

FROM alpine:3.23.4

# Add ca-certificates for HTTPS (in-cluster uses HTTPS)
RUN apk add --no-cache ca-certificates

# Copy the built binary
COPY --from=builder /build/ziglb/zig-out/bin/ziglb-agent /usr/local/bin/ziglb-agent

# Run as non-root
RUN adduser -D -u 1000 appuser
USER appuser

ENTRYPOINT ["/usr/local/bin/ziglb-agent"]
