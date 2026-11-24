# syntax=docker/dockerfile:1.7
#
# Cubewire Google Cloud Marketplace listing: the only Dockerfile in this repo.
#
# Two images come out of it, selected with --target:
#   deployer  (default, last stage)  Marketplace deployer: Google base + our schema and chart
#   stub                             minimal placeholder app, used for every app image
#
# Bases are :latest on purpose. Nothing is pinned by digest, so a rebuild is the
# whole CVE fix: rebuild, scan, push. See README.md for the exact commands.
#
# Build from the repo root (the context must include deployer/).
ARG VERSION=1.1


# ---------------------------------------------------------------------------
# stub-build: compile the placeholder app (static Go binary)
# ---------------------------------------------------------------------------
FROM cgr.dev/chainguard/wolfi-base:latest AS stub-build
RUN apk add --no-cache go
WORKDIR /src
COPY <<"EOF" /src/main.go
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
)

// Placeholder service: answers 200 on / and /health on $PORT.
func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	host, _ := os.Hostname()
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"product": "cubewire-platform",
			"stub":    true,
			"host":    host,
		})
	})
	log.Printf("cubewire stub listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}
EOF
RUN go mod init cubewire/stub \
    && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /stub .


# ---------------------------------------------------------------------------
# stub: the placeholder app image (distroless static, non-root)
# ---------------------------------------------------------------------------
FROM cgr.dev/chainguard/static:latest AS stub
LABEL maintainer="Cubewire <support@cubewire.com>"
LABEL description="Cubewire Platform - placeholder application image"
LABEL vendor="Cubewire"
LABEL url="https://www.cubewire.com"
COPY --from=stub-build /stub /stub
USER 65532:65532
ENTRYPOINT ["/stub"]


# ---------------------------------------------------------------------------
# deployer: Marketplace deployer (default target)
#
# Built on Google's own deployer base, which already carries deploy.sh, the
# Python helpers, helm and kubectl, and the entrypoint. We add only:
#   deployer/schema.yaml  Marketplace schema
#   deployer/chart/       Helm chart source, packaged into the image below
# and patch what scans as vulnerable in the base (full detail: README.md, Patches):
#   - kubectl               replaced with the Chainguard build of the same minor
#   - setuptools, wheel, pip  uninstalled (unused at runtime; flagged HIGH)
#   - curl, wget, gpg, procps, python3-wheel, and the libraries only
#     they needed (Kerberos/LDAP/SASL/ssh/curl) purged
#   - gettext replaced by gettext-base (envsubst is the only part the tooling uses)
# OS packages are upgraded so a rebuild also picks up Ubuntu fixes.
# ---------------------------------------------------------------------------
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm:latest AS deployer-build

ARG VERSION

RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get -y install --no-install-recommends gettext-base \
    && apt-get -y purge --auto-remove \
         curl wget gpg procps gettext python3-wheel \
    && rm -rf /var/lib/apt/lists/* \
    && pip uninstall -y setuptools wheel pip

COPY --from=cgr.dev/chainguard/kubectl:latest /usr/bin/kubectl /opt/kubectl/v1.37/kubectl

COPY deployer/schema.yaml /data/schema.yaml
COPY deployer/chart/ /tmp/chart-src/chart/
RUN mkdir -p /data/chart /data-test/chart \
    && tar -czf /data/chart/cubewire-platform.tar.gz -C /tmp/chart-src chart \
    && rm -rf /tmp/chart-src \
    && echo "$VERSION" > /version


# ---------------------------------------------------------------------------
# deployer (final): the patched filesystem flattened into one layer.
# Flattening drops the base image's old layers, so scanners no longer see the
# superseded setuptools that the upgrade above deleted. Config is restated from
# the Google base: PATH and the entrypoint.
# ---------------------------------------------------------------------------
FROM scratch AS deployer
LABEL maintainer="Cubewire <support@cubewire.com>"
LABEL description="Cubewire Platform - Google Cloud Marketplace deployer"
LABEL vendor="Cubewire"
LABEL url="https://www.cubewire.com"
LABEL goog-partner-solution="SOLUTION_URN"
COPY --from=deployer-build / /
ENV PATH=/opt/kubectl/default:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENTRYPOINT ["/bin/bash", "/bin/deploy.sh"]
