# Understanding: Cubewire Marketplace Deployer Image

Internal notes for this image. This file is git-ignored and docker-ignored, so it is never committed or shipped in the image.

## What this image is

- Repo: `cw-platform-marketplace` (this repo)
- Image: a `cat` wrapper that prints `README.md` from the container, so the image can be checked to run and inspected as a deployer artifact.
- Base: `cgr.dev/chainguard/busybox`, pinned by digest in `Dockerfile`.
- Runs as: `65532:65532` (nonroot). No shell is needed, and no package manager is present.

## Where it is published

| Item | Value |
|---|---|
| Google Cloud project | `cubewire` (project number `451870470897`, display name "CubeWire", ACTIVE) |
| Registry host | `gcr.io` (Container Registry path, served by Artifact Registry) |
| Image path | `gcr.io/cubewire/cubewire-platform-marketplace/deployer` |
| Current release tag | `1.0.0` |
| Release index digest | `sha256:99a23c1940488518ea0285edf6d140f04dff5c87de52bd5c2bbf016d95562092` |
| Platforms | `linux/amd64`, `linux/arm64` |
| Attestations | SBOM and provenance (`mode=max`) |

Other repositories in the project, for context:
- `gcr.io` (DOCKER, "GCR-compatible repo for Marketplace")
- `marketplace` (DOCKER, "Cubewire platform images for Google Cloud Marketplace")

Older tag `1.0` (pushed 2026-04-20) predates this image. Do not overwrite it without checking.

## Build and publish

```sh
gcloud config set project cubewire
gcloud auth configure-docker gcr.io

docker buildx create --name ghlike --driver docker-container --use   # once, if missing
docker buildx build --builder ghlike \
  --platform linux/amd64,linux/arm64 \
  --provenance=mode=max --sbom=true \
  -t gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.0.0 \
  --push .
```

Notes:
- `--push` is required for attestations to be visible to Docker Scout. `--load` drops them.
- Pin the base digest in `Dockerfile` and bump it on a schedule. `:latest` moves.

## Checks

```sh
docker scout quickview gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.0.0
trivy image --scanners vuln gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.0.0
docker buildx imagetools inspect gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.0.0
```

Last known results (2026-11-23):
- Trivy: 0 vulnerabilities.
- Scout: attestations pass. Two policies flagged:
  - "Unapproved base images": Scout reports `cgr.dev/chainguard/busybox` as "Wolfi rolling", which its policy does not approve. Needs an org decision.
  - "Copyleft licensed packages": 24 packages (busybox and other GPL-family packages). Needs a compliance decision.

## Google Cloud Marketplace producer portal

- Portal URL: `TODO`
- Product / listing ID: `TODO`
- Deployer image reference in the listing: `gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.0.0` (confirm the tag the listing points to)
- Publish process and owners: `TODO`
- Last submission date and status: `TODO`

## Open items

- Decide whether Chainguard/Wolfi is an approved base. If not, pick an approved base.
- Decide on the copyleft finding.
- Set a schedule to refresh the base digest and rescan.
- Fill in the producer portal fields above.
