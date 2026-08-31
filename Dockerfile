# The API, for a host that gives us a container and a port.
#
# Two stages so the shipped image is the binary and its runtime libraries
# rather than a Rust toolchain. sqlx is built on rustls, not OpenSSL, so
# there is no system TLS library to install and no version of it to get
# wrong against the hosted Postgres.
FROM rust:1-slim AS build
WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends pkg-config \
 && rm -rf /var/lib/apt/lists/*
# Copy the manifests first so a change to source does not re-resolve every
# dependency on every build.
COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
COPY migrations ./migrations
RUN cargo build --release -p api

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /src/target/release/api /usr/local/bin/api
# sqlx::migrate! embeds the migrations at compile time, so they travel in the
# binary and the directory is not needed here.
CMD ["api"]
