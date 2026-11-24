# Understanding: Cubewire Marketplace Deployer

Internal notes. This file is tracked in git but excluded from the Docker build context via `.dockerignore`, so it is never shipped in the image.

## What is in this repo

- `deployer/Dockerfile`: the one Dockerfile for the Marketplace deployer.
  - Base: `cgr.dev/chainguard/wolfi-base:latest` (not pinned by digest on purpose, so each rebuild picks up current fixes).
  - Installs bash, python, pyyaml, cryptography, pyOpenSSL, jq, gettext, wget.
  - Downloads Helm `v4.3.2` and kubectl `v1.30.14` and `v1.31.14` from upstream, verified against their published SHA-256 sums.
  - Copies `deployer/tooling/` to `/bin/`, `deployer/schema.yaml` to `/data/schema.yaml`, and packages `deployer/chart/` into `/data/chart/cubewire-platform.tar.gz` at build time.
  - Writes the version to `/version`. Entrypoint: `/bin/bash /bin/deploy.sh`.
- `deployer/schema.yaml`: Marketplace schema (`x-google-marketplace`, schemaVersion v2). Describes a multi-service Kubernetes app: backend, webapp, kms, transactions, policy-engine, transaction-orch, webhook-dispatcher, plus Cloud SQL connection name and webapp domain. `publishedVersion: "1.0.0"`, unchanged from the 1.0 release.
- `deployer/chart/`: Helm chart source `cubewire-platform`, version `1.0.0`. Unpacked from the 1.0 image's `cubewire-platform.tar.gz`. The tarball itself is a build artifact and is not committed.
- `deployer/tooling/`: Google marketplace deploy tooling, Apache-2.0. Taken from the 1.0 image (the files dated 2026-03-13, tests excluded). Includes `deploy.sh`, `expand_config.py`, `print_config.py`, `validate_schema.py`, `kubectl` wrapper, `yaml2json`, `json2yaml`, and related helpers.
- `Dockerfile` (repo root): an older `cat` demo image on Chainguard busybox. Not the deployer and not part of the listing. Remove it if it is no longer needed.

## Where it is published

| Item | Value |
|---|---|
| Google Cloud project | `cubewire` (project number `451870470897`, display name "CubeWire", ACTIVE) |
| Image | `gcr.io/cubewire/cubewire-platform-marketplace/deployer` |
| Release tag in use | `1.1` (only). `1.1.0` was not pushed for this build. |
| Current digest (`1.1`) | `sha256:a8c5fd50d73f66aba564c7eb27828dcb215687ccc40b99f030276c06b5ec7974` |
| Format | Single platform `linux/amd64`, Docker v2 manifest, no attestations |

Other tags, for reference:
- `1.0` → `sha256:95ebff08ef67e86cb64ed71cc61fdb1d932a80cfeb292f73f5baa88b2fcf392f`. The Ubuntu 22.04 deployer released before this work. The portal lists it as a second release. Do not overwrite without checking.
- `1.0.0` and `1.0.1` → `sha256:99a23c…`. The root `cat` image, as a multi-arch index. It has no `deploy.sh`, no schema, and no chart.
- `1.1.0` → `sha256:304911…` (the earlier `cat` image). Superseded by `1.1` above, but still on the registry under that digest.

## Build and publish

From the repo root (the build context must include `deployer/`):

```sh
gcloud config set project cubewire
gcloud auth configure-docker gcr.io

docker buildx create --name ghlike --driver docker-container --use   # once, if missing

R=gcr.io/cubewire/cubewire-platform-marketplace/deployer
docker buildx build --builder ghlike \
  --platform linux/amd64 \
  --provenance=false --sbom=false \
  --build-arg VERSION=1.1 \
  --output "type=image,name=$R:1.1,push=true,oci-mediatypes=false" \
  -f deployer/Dockerfile .
```

Notes:
- Each tag is built directly. `docker buildx imagetools create -t` gives a different digest for a single manifest.
- Attestations are omitted on purpose. The Marketplace extractor failed on the multi-arch index with attestation manifests.
- To pick up CVE fixes, rebuild. Chainguard and the Helm and kubectl versions are the only things that change between builds. Bump `HELM_VERSION` and `KUBECTL_*_VERSION` in the Dockerfile when upstream releases patches.
- Use `docker run --pull always` when you check a tag. Otherwise Docker runs the local cache, which can be an older image.

## Checks

Validated on `1.1` (`sha256:a8c5fd50…`):
- `/version` is `1.1`.
- `helm version` → `v4.3.2`. `kubectl` 1.30.14 and 1.31.14 are present under `/opt/kubectl/`.
- `python3` imports `yaml`, `OpenSSL`, and `cryptography`.
- `deploy.sh` passes `bash -n`.
- `helm template` renders the packaged chart.
- `/data/schema.yaml` is present and `validate_schema.py` runs against it.
- The image contents match the repo.

Trivy on `1.1`: 2 critical, 74 high, 83 medium, 5 low.
- All critical and high findings are in the `kubectl` binaries (38 + 38 high, plus both criticals). They come from the Go standard library embedded by upstream: CVE-2025-68121, fixed in Go 1.24.13 and later. The latest 1.30 and 1.31 patches still ship older Go builds.
- Helm (`v4.3.2`) and the OS packages contribute no critical or high findings.
- Fixing the `kubectl` findings means building kubectl from source with a newer Go, rather than downloading upstream binaries.

Docker Scout, the attestation check, and the copyleft check have not been re-run on `1.1`.

## Google Cloud Marketplace producer portal

- Listing details page: `https://console.cloud.google.com/marketplace/product/cubewire/cubewire-p8`
- Product / listing ID: URL segment `cubewire-p8` (project `cubewire`)
- Status: **already published**. The portal warns that changing product info requires approval and republishing.
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
- Deployer image reference in the listing: `gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.1` (default release), plus `1.0` as a second release.
- Earlier failure (2026-11-23, against the `cat` image): schema extraction and test deployment failed with "Image not found". That image had no `deploy.sh` or `schema.yaml`, so the image contents explain the failure.
- Retry against `1.1` (`sha256:a8c5fd50…`): `TODO` (record result here)
- Publish process and owners: `TODO`
- Last submission date and status: `TODO`

## Access

- The deployer repo in `gcr.io` is private. Public access would come from an `allUsers` binding with `roles/artifactregistry.reader` on the `gcr.io` repo (location `us`). This applies to every image in that repo.
- Repo IAM in location `us` shows only the `cloud-commerce-partner` binding, so the image is currently private.

## Repo protection

- `master` on `Cubewire/cw-platform-marketplace` is currently **not protected**. It was removed by hand for direct pushes on 2026-11-24. Restore protection if you want it back.
- A backup of the old rule (1 approving review, enforced for admins, no force pushes or deletions) is at `/private/tmp/claude-504/master-protection-backup.json`. This is session-local and may be gone.

## Open items

- Retry the producer portal against `1.1` and record the result above.
- Confirm the product type is Kubernetes app. The schema describes one, but the portal flow has not been checked directly.
- Decide whether `schema.yaml` `publishedVersion` should change from `1.0.0` to match the `1.1` release.
- Clear the `kubectl` critical and high findings by building kubectl from source with a current Go.
- Decide whether the root `Dockerfile` (`cat` demo image) should be removed, since the deployer is the only image needed.
- Decide whether the deployer should run as non-root. The current `deploy.sh` runs as root, as it did in 1.0.
- Re-run Docker Scout on `1.1`, and decide on the copyleft findings.
