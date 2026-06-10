FROM alpine:3.23.4

RUN apk add --no-cache \
    xz \
    libbpf-dev \
    elfutils-dev \
    musl-dev \
    linux-headers \
    zlib-dev

WORKDIR /workspace

RUN adduser -D -u 1000 -G users -h /home/dev dev
USER dev

CMD ["sh"]
