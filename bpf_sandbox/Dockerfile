FROM alpine:3.23.4

RUN apk add --no-cache \
    xz \
    libbpf-dev \
    elfutils-dev \
    bpftool \
    musl-dev \
    zlib-dev

WORKDIR /workspace

COPY ./zig-out ./zig-out

CMD ["/workspace/zig-out/bin/loader"]
