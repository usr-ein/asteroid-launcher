# Sonic Screwdriver: build environment for asteroid-launcher, using the
# AsteroidOS 2.1 SDK. The SDK only exists for x86_64 hosts, so this image is
# linux/amd64 (Rosetta on Apple Silicon). The SDK itself goes into a Docker
# volume, installed by sonic/build.sh on its first run.
FROM --platform=linux/amd64 debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 xz-utils file make ca-certificates \
 && rm -rf /var/lib/apt/lists/*
