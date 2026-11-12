FROM rust:1.99-bookworm AS build
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY schema.sql ./schema.sql
RUN cargo build --release --locked
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/* && useradd -u 10001 -m app
WORKDIR /app
COPY --from=build /app/target/release/flashroute-api /usr/local/bin/flashroute-api
USER app
EXPOSE 8080
CMD ["flashroute-api"]
