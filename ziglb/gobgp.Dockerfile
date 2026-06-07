FROM golang:1.23-alpine AS builder

RUN go install github.com/osrg/gobgp/v3/cmd/gobgpd@latest

FROM alpine:3.23.4

COPY --from=builder /go/bin/gobgpd /usr/local/bin/gobgpd

# Config is mounted from a ConfigMap at /etc/gobgpd/gobgpd.toml
ENTRYPOINT ["gobgpd", "-f", "/etc/gobgpd/gobgpd.toml", "--log-level", "debug"]
