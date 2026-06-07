FROM alpine:3.23.4 AS builder

RUN apk add --no-cache curl xz ca-certificates

RUN curl -fsSL https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz | tar -xJ -C /usr/local && \
    ln -s /usr/local/zig-x86_64-linux-0.16.0/zig /usr/local/bin/zig

WORKDIR /build/zig_http_server

# Copy local path dependencies and the project
COPY . .

RUN --mount=type=cache,target=/root/.cache/zig \
    zig build -Doptimize=ReleaseSafe

ENTRYPOINT ["/build/zig_http_server/zig-out/bin/zig-http-server"]

# FROM alpine:3.23.4
#
# # Add ca-certificates for HTTPS (in-cluster uses HTTPS)
# RUN apk add --no-cache ca-certificates
#
# # Copy the built binary
# COPY --from=builder /build/zig_http_server/zig-out/bin/zig-http-server /usr/local/bin/zig-http-server
#
# ENTRYPOINT ["/usr/local/bin/zig-http-server"]
