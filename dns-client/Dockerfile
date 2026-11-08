FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        dnsutils \
        curl \
    && rm -rf /var/lib/apt/lists/*

