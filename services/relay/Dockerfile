# Blind relay — build from the monorepo root.
# Dokploy: context `.`, Dockerfile `services/relay/Dockerfile`, port 8787.
FROM rust:1-bookworm AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY crates/core ./crates/core
COPY services/relay ./services/relay
RUN cargo build --release -p encrypchat_relay

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data
COPY --from=build /src/target/release/encrypchat_relay /usr/local/bin/encrypchat_relay
ENV ENCRYPCHAT_RELAY_ADDR=0.0.0.0:8787 \
    ENCRYPCHAT_RELAY_DB=/data/relay.sqlite
EXPOSE 8787
VOLUME /data
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD wget -qO- http://127.0.0.1:8787/healthz >/dev/null || exit 1
CMD ["encrypchat_relay"]
