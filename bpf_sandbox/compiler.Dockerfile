FROM alpine:3.23.4

RUN apk add --no-cache \
    curl \
    xz \
    libbpf-dev \
    elfutils-dev \
    musl-dev \
    zlib-dev

RUN curl -fsSL https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz | tar -xJ -C /usr/local && \
    ln -s /usr/local/zig-x86_64-linux-0.16.0/zig /usr/local/bin/zig

WORKDIR /workspace

RUN adduser -D -u 1000 -G users -h /home/dev dev
USER dev

# Run the confirmation binary by default
CMD ["zig", "build"]
