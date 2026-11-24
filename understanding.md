# Understanding: Cubewire Marketplace Deployer Image

Internal notes for this image. This file is tracked in git but excluded from the Docker build context via `.dockerignore`, so it is never shipped in the image.

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
| Current release tags | `1.1` and `1.1.0` (same digest) |
| Current digest (`1.1`, `1.1.0`) | `sha256:304911474f2fbf65daeb7bd695171e550cad1adbb2327c412002a468d32cfda3` |
| Format | Single platform `linux/amd64`, Docker v2 manifest (`application/vnd.docker.distribution.manifest.v2+json`) |
| Attestations | None (`--provenance=false --sbom=false`) |

Earlier builds, for reference:
- `1.0.0` and `1.0.1` point to `sha256:99a23c1940488518ea0285edf6d140f04dff5c87de52bd5c2bbf016d95562092`. This is a multi-arch OCI index (amd64 + arm64) with SBOM and provenance attestations. The Marketplace producer portal reported "Image not found" for this digest, so `1.1` was moved to the amd64-only image above.
- `1.0` (pushed 2026-04-20) points to `sha256:95ebff08ef67e86cb64ed71cc61fdb1d932a80cfeb292f73f5baa88b2fcf392f`, a single-platform image. This predates our work. Do not overwrite it without checking.

Other repositories in the project, for context:
- `gcr.io` (DOCKER, "GCR-compatible repo for Marketplace")
- `marketplace` (DOCKER, "Cubewire platform images for Google Cloud Marketplace")

## Build and publish

The current release format is amd64-only, Docker v2 manifest, no attestations. This is what the Marketplace producer portal needs.

```sh
gcloud config set project cubewire
gcloud auth configure-docker gcr.io

docker buildx create --name ghlike --driver docker-container --use   # once, if missing

R=gcr.io/cubewire/cubewire-platform-marketplace/deployer
docker buildx build --builder ghlike \
  --platform linux/amd64 \
  --provenance=false --sbom=false \
  --output "type=image,name=$R:1.1.0,push=true,oci-mediatypes=false" .

# Point 1.1 at the same image. Build it directly with the same tag rather than
# using `imagetools create`, which wraps the manifest in a new index with a different digest.
docker buildx build --builder ghlike \
  --platform linux/amd64 \
  --provenance=false --sbom=false \
  --output "type=image,name=$R:1.1,push=true,oci-mediatypes=false" .
```

Notes:
- Attestations (SBOM, provenance) are only visible to Docker Scout when the image is pushed. `--load` drops them. The amd64-only release above omits them on purpose, because the Marketplace extractor failed on the multi-arch index with attestation manifests.
- Pin the base digest in `Dockerfile` and bump it on a schedule. `:latest` moves.
- Do not use `docker buildx imagetools create -t 1.1 1.1.0` for a single-manifest image. It produces a different digest.

## Checks

```sh
docker scout quickview gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.1.0
trivy image --scanners vuln gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.1.0
docker buildx imagetools inspect gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.1.0
```

Last known results (2026-11-24):
- Trivy on `1.1.0`: 0 vulnerabilities.
- Scout on the multi-arch `1.0.0` build (2026-11-23): attestations passed. Expect the attestation check to fail on `1.1.0` since it has none.
- Scout flagged two policies on the multi-arch build:
  - "Unapproved base images": Scout reports `cgr.dev/chainguard/busybox` as "Wolfi rolling", which its policy does not approve. Needs an org decision.
  - "Copyleft licensed packages": 24 packages (busybox and other GPL-family packages). Needs a compliance decision.

## Google Cloud Marketplace producer portal

- Listing details page: `https://console.cloud.google.com/marketplace/product/cubewire/cubewire-p8`
- Product / listing ID: URL segment `cubewire-p8` (project `cubewire`)
- Status: **already published**. The portal warns that changing product info requires approval and republishing. A banner shows a review with update time "Apr 20" (the text is cut off in the screenshot).
- Product info (as shown in the portal):
  - Name: `Cubewire`
  - Tagline: "Driving Web3 Adoption for the next phase of digital finance" (60 chars)
  - Overview: 382 chars, starting "Cubewire is a unified platform driving digital asset adoption with institutional-grade solutions…"
  - Link to more info: `https://www.cubewire.com/`
  - Category: Blockchain and Data
  - Industry: Financial Services and Insurance
  - Support description: "For technical support, deployment assistance, and general enquiries, contact the Cubewire team at support@cubewire.com or visit…"
  - Support URL: `https://cubewire.atlassian.net/servicedesk/customer/portals`
  - Search keywords: blockchain payments, stablecoin, digital wallet, payment infrastructure, Web3, enterprise payments, wallet as a service, L2 blockchain
  - Product searchable: on
- Deployer image reference in the listing: `gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.1` (default release, display tag `1.1`), plus `1.0` as a second release. These are the portal's values from the earlier screenshot, before the `1.1` tag move.
- Last run (2026-11-23, against `1.0.0`'s multi-arch digest): schema extraction and test deployment failed with "Image not found" for `sha256:99a23c…`. The image resolves from our account, and the repo grants `roles/artifactregistry.reader` to `cloud-commerce-partner@system.gserviceaccount.com`. Likely cause: the extractor doesn't handle the OCI index with attestation manifests. Not yet confirmed.
- Retry after the `1.1` move to `sha256:304911…`: `TODO` (record result here)
- Publish process and owners: `TODO`
- Last submission date and status: `TODO`

## Access

- `gcr.io/cubewire/cubewire-platform-marketplace/deployer` is private. Public access would come from an `allUsers` binding with `roles/artifactregistry.reader` on the `gcr.io` repo (location `us`). This applies to every image in that repo.
- Repo IAM in location `us` shows only the `cloud-commerce-partner` binding, so the image is currently private.

## Repo protection

- `master` on `Cubewire/cw-platform-marketplace` has branch protection: 1 approving review, enforced for admins, no force pushes or deletions. Backup of the rule is in `/private/tmp/claude-504/master-protection-backup.json` (session-local, may be gone).
- Direct pushes to `master` required removing and restoring this rule with `gh api`. Restore it after every direct push.

## Open items

- Retry the producer portal and record the result above.
- Decide whether Chainguard/Wolfi is an approved base. If not, pick an approved base.
- Decide on the copyleft finding.
- Decide whether `1.0` should point to an amd64-only build as well.
- Set a schedule to refresh the base digest and rescan.
- Fill in the producer portal fields above.
