# Cubewire Marketplace deployer.
#
# Layered on the 1.0 deployer image (Ubuntu 22.04 + Google marketplace deploy
# tooling in /usr/bin + helm + kubectl), pinned by digest so the tooling is
# identical to the release already on the registry. This layer replaces the
# schema and chart with the copies in this repo and writes the version marker.
#
# Build from the repo root (the build context must include deployer/):
#   docker buildx build --builder ghlike --platform linux/amd64 \
#     --provenance=false --sbom=false \
#     -f deployer/Dockerfile -t <image>:<tag> --push .
FROM gcr.io/cubewire/cubewire-platform-marketplace/deployer@sha256:95ebff08ef67e86cb64ed71cc61fdb1d932a80cfeb292f73f5baa88b2fcf392f

ARG VERSION=1.1.0

LABEL maintainer="Cubewire <support@cubewire.com>"
LABEL description="Cubewire Platform - Google Cloud Marketplace deployer"
LABEL vendor="Cubewire"
LABEL url="https://www.cubewire.com"
LABEL goog-partner-solution="SOLUTION_URN"

COPY deployer/schema.yaml /data/schema.yaml
COPY deployer/chart/cubewire-platform.tar.gz /data/chart/cubewire-platform.tar.gz
RUN echo "$VERSION" > /version
