# Cubewire Google Cloud Marketplace deployer.
#
# Base: Chainguard Wolfi, :latest (rebuild to pick up CVE fixes).
#
# Inputs in this repo:
#   deployer/schema.yaml   Marketplace schema
#   deployer/chart/        Helm chart source (packaged into the image at build time)
#   deployer/tooling/      Google marketplace deploy tooling (Apache-2.0), incl. deploy.sh
#
# Helm and kubectl are downloaded from upstream and checked against their
# published SHA-256 sums. Versions: helm 4.x, kubectl 1.30 and 1.31 (the minors
# the deployer's kubectl wrapper selects from). Bump HELM_VERSION and
# KUBECTL_*_VERSION when upstream releases new patches.
#
# Build and push from the repo root (the context must include deployer/):
#   docker buildx build --builder ghlike --platform linux/amd64 \
#     --provenance=false --sbom=false --build-arg VERSION=<version> \
#     -f deployer/Dockerfile -t <image>:<tag> --push .
ARG VERSION=1.1
ARG HELM_VERSION=v4.3.2
ARG KUBECTL_130_VERSION=v1.30.14
ARG KUBECTL_131_VERSION=v1.31.14

FROM cgr.dev/chainguard/wolfi-base:latest

ARG VERSION
ARG HELM_VERSION
ARG KUBECTL_130_VERSION
ARG KUBECTL_131_VERSION

LABEL maintainer="Cubewire <support@cubewire.com>"
LABEL description="Cubewire Platform - Google Cloud Marketplace deployer"
LABEL vendor="Cubewire"
LABEL url="https://www.cubewire.com"
LABEL goog-partner-solution="SOLUTION_URN"

RUN apk add --no-cache \
      bash \
      python-3 \
      py3-pip \
      py3-pyyaml \
      py3-cryptography \
      jq \
      gettext \
      wget \
      ca-certificates \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && pip install --no-cache-dir --break-system-packages "pyOpenSSL>=26.0.0"

# Helm
RUN set -eux; \
    cd /tmp; \
    wget -q -O helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"; \
    wget -q -O helm.tar.gz.sha256sum "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum"; \
    sed -i "s|helm-.*\.tar\.gz|helm.tar.gz|" helm.tar.gz.sha256sum; \
    sha256sum -c helm.tar.gz.sha256sum; \
    tar -xzf helm.tar.gz; \
    mv linux-amd64/helm /usr/bin/helm; \
    chmod +x /usr/bin/helm; \
    rm -rf /tmp/helm.tar.gz /tmp/helm.tar.gz.sha256sum /tmp/linux-amd64

# kubectl 1.30 and 1.31, under /opt/kubectl/<minor>/ as the wrapper expects
RUN set -eux; \
    for pair in "1.30:${KUBECTL_130_VERSION}" "1.31:${KUBECTL_131_VERSION}"; do \
      minor="${pair%%:*}"; full="${pair#*:}"; \
      mkdir -p "/opt/kubectl/${minor}"; \
      wget -q -O "/opt/kubectl/${minor}/kubectl" "https://dl.k8s.io/release/${full}/bin/linux/amd64/kubectl"; \
      echo "$(wget -q -O - "https://dl.k8s.io/release/${full}/bin/linux/amd64/kubectl.sha256")  /opt/kubectl/${minor}/kubectl" | sha256sum -c -; \
      chmod +x "/opt/kubectl/${minor}/kubectl"; \
    done; \
    ln -s /opt/kubectl/1.31 /opt/kubectl/default

COPY deployer/tooling/ /bin/
RUN chmod +x /bin/*.py /bin/*.sh /bin/kubectl /bin/json2yaml /bin/yaml2json

COPY deployer/schema.yaml /data/schema.yaml
COPY deployer/chart/ /tmp/chart-src/chart/
RUN mkdir -p /data/chart /data-test/chart \
    && tar -czf /data/chart/cubewire-platform.tar.gz -C /tmp/chart-src chart \
    && rm -rf /tmp/chart-src \
    && echo "$VERSION" > /version

ENTRYPOINT ["/bin/bash", "/bin/deploy.sh"]
