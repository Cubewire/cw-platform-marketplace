# Understanding: Cubewire Marketplace Deployer Image

Internal notes for this image. This file is tracked in git but excluded from the Docker build context via `.dockerignore`, so it is never shipped in the image.

## What is in this repo

- `Dockerfile` (root): a `cat` wrapper that prints `README.md`, on `cgr.dev/chainguard/busybox` pinned by digest, running as `65532:65532`. It is **not** the Marketplace deployer and was never accepted by the portal.
- `deployer/`: the Marketplace deployer for the Kubernetes app.
  - `deployer/Dockerfile`: layers on the `1.0` deployer image, pinned by digest, and replaces the schema and chart with the copies below.
  - `deployer/schema.yaml`: the Marketplace schema (`x-google-marketplace`, schemaVersion v2). Describes a multi-service Kubernetes app: backend, webapp, kms, transactions, policy-engine, transaction-orch, webhook-dispatcher, plus Cloud SQL connection name and webapp domain. `publishedVersion: "1.0.0"` (unchanged from `1.0`).
  - `deployer/chart/cubewire-platform.tar.gz`: Helm chart `cubewire-platform` version `1.0.0`, extracted from `1.0`.
  - `deployer/deploy.sh`: copy of `/bin/deploy.sh` from `1.0` (which resolves to `/usr/bin/deploy.sh`). Google marketplace tooling, Apache-2.0.

The helper scripts `deploy.sh` calls (`expand_config.py`, `print_config.py`, `create_manifests.sh`, and others) are **not** vendored here. They come from the `1.0` base image through the pinned digest.

## Where it is published

| Item | Value |
|---|---|
| Google Cloud project | `cubewire` (project number `451870470897`, display name "CubeWire", ACTIVE) |
| Registry host | `gcr.io` (Container Registry path, served by Artifact Registry) |
| Image path | `gcr.io/cubewire/cubewire-platform-marketplace/deployer` |
| Current release tags | `1.1` and `1.1.0` (same digest) |
| Current digest (`1.1`, `1.1.0`) | `sha256:dcc428af42ff4f1e5ae212fd263b4040c7858ccf231aa4e1ca7289d0848629a4` |
| Built from | `deployer/Dockerfile`, `VERSION=1.1.0` |
| Format | Single platform `linux/amd64`, Docker v2 manifest |
| Attestations | None (`--provenance=false --sbom=false`) |

Other tags, for reference:
- `1.0` → `sha256:95ebff08ef67e86cb64ed71cc61fdb1d932a80cfeb292f73f5baa88b2fcf392f`. Ubuntu 22.04 deployer, pushed 2026-04-20, before this repo's work. It is the base of the current `1.1.0`. Do not overwrite it without checking.
- `1.0.0` and `1.0.1` → `sha256:99a23c1940488518ea0285edf6d140f04dff5c87de52bd5c2bbf016d95562092`. The `cat` image from the root `Dockerfile`, as a multi-arch index with attestations. It has no `deploy.sh`, no `schema.yaml`, and no chart.

Other repositories in the project, for context:
- `gcr.io` (DOCKER, "GCR-compatible repo for Marketplace")
- `marketplace` (DOCKER, "Cubewire platform images for Google Cloud Marketplace")

## Build and publish

Build the deployer from the repo root (the context must include `deployer/`):

```sh
gcloud config set project cubewire
gcloud auth configure-docker gcr.io

docker buildx create --name ghlike --driver docker-container --use   # once, if missing

R=gcr.io/cubewire/cubewire-platform-marketplace/deployer
for t in 1.1.0 1.1; do
  docker buildx build --builder ghlike \
    --platform linux/amd64 \
    --provenance=false --sbom=false \
    --build-arg VERSION=1.1.0 \
    --output "type=image,name=$R:$t,push=true,oci-mediatypes=false" \
    -f deployer/Dockerfile .
done
```

Notes:
- Build each tag directly. `docker buildx imagetools create -t` wraps a single manifest in a new index with a different digest.
- Attestations are only visible to Docker Scout when the image is pushed. `--load` drops them. They are omitted on purpose: the Marketplace extractor failed on the multi-arch index with attestation manifests.
- Bump `--build-arg VERSION` and the tags together for each release.

## Checks

```sh
R=gcr.io/cubewire/cubewire-platform-marketplace/deployer
docker buildx imagetools inspect $R:1.1.0
trivy image --scanners vuln $R:1.1.0
docker scout quickview $R:1.1.0
docker run --rm --platform linux/amd64 --entrypoint /bin/cat $R:1.1.0 /data/schema.yaml | diff - deployer/schema.yaml
```

Last known results (2026-11-24):
- `1.1.0` (deployer): Trivy shows 2 critical, 124 high, 433 medium, 87 low, 580 fixable. All of this is inherited from the `1.0` Ubuntu base.
- `1.1.0` (deployer): Scout flags root user, 334 copyleft-licensed packages, 40 critical and 186 high fixable vulnerabilities, and missing attestations.
- Root `Dockerfile` `cat` image (not published as a release): Trivy 0 vulnerabilities; Scout flagged an unapproved base (`cgr.dev/chainguard/busybox`, Wolfi rolling) and 24 copyleft packages.

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
- Deployer image reference in the listing: `gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.1` (default release, display tag `1.1`), plus `1.0` as a second release. These are the portal's values from the earlier screenshot.
- Failure before the deployer fix (2026-11-23, digest `sha256:99a23c…`, the `cat` image): schema extraction and test deployment failed with "Image not found". That image had no `deploy.sh` or `schema.yaml`, so this failure is explained by the image contents, not by the digest format.
- Retry against `1.1.0` (`sha256:dcc428af…`): `TODO` (record result here)
- Publish process and owners: `TODO`
- Last submission date and status: `TODO`

## Access

- `gcr.io/cubewire/cubewire-platform-marketplace/deployer` is private. Public access would come from an `allUsers` binding with `roles/artifactregistry.reader` on the `gcr.io` repo (location `us`). This applies to every image in that repo.
- Repo IAM in location `us` shows only the `cloud-commerce-partner` binding, so the image is currently private.

## Repo protection

- `master` on `Cubewire/cw-platform-marketplace` had branch protection: 1 approving review, enforced for admins, no force pushes or deletions. A backup of the rule is in `/private/tmp/claude-504/master-protection-backup.json` (session-local, may be gone).
- The rule was removed by hand for the 2026-11-24 push. Restore it after direct pushes if you want it back.

## Open items

- Retry the producer portal against `1.1.0` and record the result above.
- Confirm the product type is Kubernetes app. The schema describes one, but the portal flow has not been checked directly.
- Decide whether `schema.yaml` `publishedVersion` should change from `1.0.0` to `1.1.0` to match the tag.
- Rebuild the deployer from upstream Google marketplace tooling on a hardened base, to clear the inherited 2 critical / 124 high findings and the root user.
- Decide on the copyleft findings and whether Chainguard/Wolfi is an approved base (applies to the root `cat` image).
- Set a schedule to refresh base digests and rescan.
- Fill in the producer portal fields above.
