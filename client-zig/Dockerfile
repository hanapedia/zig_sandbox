FROM alpine:3.19

# Add ca-certificates for HTTPS (in-cluster uses HTTPS)
RUN apk add --no-cache ca-certificates

# Copy the pre-built binary
COPY zig-out/bin/client_zig /usr/local/bin/client_zig

# Run as non-root
RUN adduser -D -u 1000 appuser
USER appuser

ENTRYPOINT ["/usr/local/bin/client_zig"]
