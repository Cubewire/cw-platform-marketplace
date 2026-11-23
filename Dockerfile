FROM cgr.dev/chainguard/busybox@sha256:9ea14a743061993ca9fbf5f5ad7215ede3646d142754398f456250e51c23175a
LABEL maintainer="Cubewire <support@cubewire.com>"
LABEL description="Cubewire Platform - Redefining the Payment Landscape with Web3"
LABEL vendor="Cubewire"
LABEL url="https://www.cubewire.com"
LABEL goog-partner-solution="SOLUTION_URN"
COPY README.md /opt/cubewire/README.md
USER 65532:65532
ENTRYPOINT ["/bin/cat", "/opt/cubewire/README.md"]
