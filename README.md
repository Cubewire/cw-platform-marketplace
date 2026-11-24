# cw-platform-marketplace

Internal repo. It builds and publishes the **Google Cloud Marketplace Kubernetes app** for the Cubewire Platform (listing `cubewire-p8`, GCP project `cubewire`).

It is not the Cubewire product itself. It holds what Marketplace needs to install the product into a customer's GKE cluster: a **deployer image**, the **Helm chart** and **schema** the deployer applies, and **placeholder (stub) app images** until real ones are released for this version.

Contents:
1. [What this repo is for](#1-what-this-repo-is-for)
2. [Repo layout](#2-repo-layout)
3. [How the images are set up](#3-how-the-images-are-set-up)
4. [What Google Cloud Marketplace expects](#4-what-google-cloud-marketplace-expects)
5. [Official docs map](#5-official-docs-map)
6. [Where things are published](#6-where-things-are-published)
7. [Build, scan, push](#7-build-scan-push)
8. [Patches](#8-patches)
9. [Producer portal](#9-producer-portal)
10. [Access and repo settings](#10-access-and-repo-settings)
11. [Open items](#11-open-items)

---

## 1. What this repo is for

A Marketplace Kubernetes app is delivered as a set of container images in one registry repository, plus a configuration (Helm chart or manifests) that deploys them. When a customer clicks Deploy, Marketplace runs our **deployer image** in their cluster. The deployer reads `/data/schema.yaml` (the form shown to the customer), expands the Helm chart in `/data/chart/`, applies it with `kubectl`, and checks the result.

This repo produces:

| Image | Registry path | Purpose |
|---|---|---|
| deployer | `gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.1` | What Marketplace runs. Contains the schema, the chart and Google's deploy tooling. |
| app images (stub) | `gcr.io/cubewire/cubewire-platform-marketplace[/<name>]:1.1` | One image per service named in the schema. Currently a tiny placeholder server (see section 3). |

## 2. Repo layout

```
Dockerfile                 the only Dockerfile: two targets, "deployer" (default) and "stub"
deployer/schema.yaml       Marketplace schema (x-google-marketplace, schemaVersion v2)
deployer/chart/            Helm chart source (Chart.yaml, values.yaml, templates/)
.dockerignore              keeps docs, git data and env files out of the build context
.gitignore
README.md                  this file (internal; not shipped in any image)
```

Everything else the deployer needs (`deploy.sh`, the Python helpers, `helm`, `kubectl`) comes from Google's base image, not from this repo.

## 3. How the images are set up

One `Dockerfile`, three stages.

```
stub-build  (wolfi-base:latest)   compile a ~30 line static Go server
stub        (chainguard/static)   target "stub": distroless, non-root, 3 MB
deployer-build (Google deployer_helm:latest)   patch + add schema and chart
deployer    (scratch)             target "deployer" (default): deployer-build flattened to one layer
```

### Deployer

- **Base:** `gcr.io/cloud-marketplace-tools/k8s/deployer_helm:latest`, Google's own deployer base for Helm charts (Ubuntu 22.04). It already contains `/bin/deploy.sh` (the entrypoint), the Python helpers in `/usr/bin`, `helm`, and `kubectl`. That is why this repo has no vendored tooling.
- **We add:**
  - `/data/schema.yaml` from `deployer/schema.yaml`
  - `/data/chart/cubewire-platform.tar.gz`, built at image build time from `deployer/chart/`
  - `/version` containing the release version
- **We change:** the base is patched to remove vulnerabilities (section 8).
- **Final layer:** the patched filesystem is copied into `scratch` so the image has one layer. Config is restated: `PATH=/opt/kubectl/default:...` and `ENTRYPOINT ["/bin/bash","/bin/deploy.sh"]`.
- **Runs as root.** That matches Google's base. The Marketplace docs do not state a user requirement.

What `deploy.sh` does (from reading the script and the helpers it calls): it expands the configuration (`expand_config.py`), renders the chart (`helm template`), applies it with `kubectl`, sets owner references (`set_ownership.py`), validates the Application resource and sets the assembly phase (`validate_app_resource.py`, `setassemblyphase.py`), and marks the app Failed if anything errors.

### Stub app images

The schema (`deployer/schema.yaml`) names seven app images. The chart deploys one Deployment and Service for each:

| Schema image key | Registry path | Chart port |
|---|---|---|
| `''` (backend) | `gcr.io/cubewire/cubewire-platform-marketplace` | 3000 |
| `webapp` | `.../webapp` | 3000 |
| `kms` | `.../kms` | 3000 |
| `transactions` | `.../transactions` | 3002 |
| `policy-engine` | `.../policy-engine` | 50052 |
| `transaction-orch` | `.../transaction-orch` | 3000 |
| `webhook-dispatcher` | `.../webhook-dispatcher` | 8080 |

The stub is a static Go binary that listens on `$PORT` (the chart sets it) and answers `200` on `/` and `/health`, which are the paths the chart's probes use. The same stub image is pushed to all seven paths as tag `1.1`. It is **a placeholder**, not the product. It exists so a Marketplace test deployment has images to pull and probes to pass.

The real Cubewire images exist in the same repositories under tags `1.0` and `1.0.0` (pushed 2026-04-20). The stub only adds `1.1`; the real tags are untouched.

## 4. What Google Cloud Marketplace expects

Source: Google Cloud docs, [Requirements for packaging your app](https://docs.cloud.google.com/marketplace/docs/partners/kubernetes/create-app-package) (read 2026-11-24). Where the docs point to the `marketplace-k8s-app-tools` GitHub repo for details, we have not read those pages in full yet.

**Package contents**
- A configuration that deploys the app: Kubernetes YAML or a Helm chart. It must create an **Application custom resource** that groups the app's resources (this is what customers see in the Console). Only beta or GA Kubernetes APIs.
- The configuration must be parameterizable: one namespace (not hard-coded), the app/instance name in every resource name, and every image reference substitutable. It must deploy with client-side tools (Helm with `--client-only`).
- The app must run on **x86** nodes.
- A public Git repository with a `LICENSE` file, the configuration, Dockerfiles and build instructions.
- Integration tests and a user guide (CLI deploy, configuration, usage).

**Images and registry**
- All images in Artifact Registry or Container Registry, in **one repository** with this structure: the main image at the root, the deployer in a `deployer` folder, every other image in its own folder under the main image.
- Every image tagged with the **release track and the full version** (the docs' example: releasing 2.0.5 on track 2.0 gives tags `2.0` and `2.0.5`). The version must match the `Version` field of the Application resource declared in the deployer.
- Every image must carry the OCI annotation `com.googleapis.cloudmarketplace.product.service.name=services/SERVICE_NAME`. `SERVICE_NAME` is on the Producer Portal Overview page.
- Prefer Marketplace certified base images for timely security patches.

**Deployer image**
- Packages the configuration and the client tools (`kubectl`, `helm`) that push it to the cluster, using the same commands a user would run.
- Build it from Google's `deployer_envsubst` (kubectl configs) or `deployer_helm` (Helm charts) bases under `gcr.io/cloud-marketplace-tools/k8s/`.
- Must contain `/data/schema.yaml`, a JSON Schema (in YAML) that describes the parameters collected from customers.

**Verification** (required before publishing): installation (all resources applied and healthy), functionality tests (the deployer starts a tester Pod and passes if it exits 0), uninstallation (all resources removed).

**Not stated on that page:** vulnerability scanning, running as non-root, and a consumption-tracking label (the page requires the image annotation above and, for commercial apps, usage reporting with a reporting Secret).

### How this repo compares

| Expectation | Status |
|---|---|
| Application resource in the chart | Done (`deployer/chart/templates/application.yaml`) |
| One repository: main image, `deployer/`, other images in folders | Done (section 6) |
| x86 | Done (`linux/amd64` only) |
| Tags: track and full version | **Partial.** Only `1.1` is pushed. The docs example also pushes `1.1.0`. |
| Application `Version` matches release | Done: Application descriptor, chart and `publishedVersion` are `1.1.0` |
| OCI annotation `...product.service.name` on every image | **Missing.** Needs `SERVICE_NAME` from the Producer Portal. |
| Public repo with `LICENSE` | **Missing.** This repo is internal and has no LICENSE. |
| Integration tests (tester Pod) | **Missing.** `/data-test/chart` is empty. |
| User guide | **Missing.** |
| App images | **Stub only** for 1.1 (section 3) |
| `/data/schema.yaml` in the deployer | Done, and it validates (`validate_schema.py`) |

## 5. Official docs map

Google Cloud docs, Kubernetes app partners section (`docs.cloud.google.com/marketplace/docs/partners/kubernetes/`):
- [Requirements for packaging your app](https://docs.cloud.google.com/marketplace/docs/partners/kubernetes/create-app-package) (`create-app-package`): the page summarised in section 4.
- `set-up-environment`: Google Cloud environment, release tracks, product identifiers.
- `select-pricing`: pricing model.
- [Kubernetes app update docs](https://docs.cloud.google.com/marketplace/docs/kubernetes-apps/update-app).
- Usage reporting (commercial apps): the integrated SaaS backend-integration page, plus `billing-integration.md` in the tools repo.

The detailed deployer, schema and testing documentation lives in the GitHub repo [GoogleCloudPlatform/marketplace-k8s-app-tools](https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools), under `docs/`:
- `building-deployer.md`: how to build the deployer image.
- `schema.md`: the `x-google-marketplace` schema reference.
- `verification-integration.md`: the verification process and tester Pod.
- `billing-integration.md`: usage reporting.

Worked examples: [click-to-deploy `k8s/`](https://github.com/GoogleCloudPlatform/click-to-deploy/tree/master/k8s).

The overview page of the Kubernetes partner section was not read, so this map is built from the links on the packaging page.

## 6. Where things are published

| Item | Value |
|---|---|
| Project | `cubewire` (number `451870470897`) |
| Registry | `gcr.io`, an Artifact Registry repo in location `us` |
| Deployer | `gcr.io/cubewire/cubewire-platform-marketplace/deployer:1.1` → `sha256:c146f20812f706044a2a553e3edd054170368013afe63df2b1ad07c3f4cfb001` |
| Stub app images, all seven paths | `:1.1` → `sha256:83c2878f7618f65705aff7f0c47887b05dd5798d34d491bcd03b6b0b5c506074` |
| Format | single platform `linux/amd64`, Docker v2 manifest, no attestations |

Other tags in the same repositories, for reference:
- `1.0`, `1.0.0` on the root, `webapp`, `kms`, `transactions`, `policy-engine`, `transaction-orch` and `webhook-dispatcher`: the **real app images**, pushed 2026-04-20. Do not overwrite.
- `deployer:1.0` → `sha256:95ebff08…`: the original Ubuntu deployer. The portal lists it as a second release.
- `deployer:1.0.0`, `1.0.1` → `sha256:99a23c…`, and `deployer:1.1.0` → `sha256:304911…`: earlier experiments (the `cat` demo image). They have no schema or chart and must not be used for a release. Delete them when convenient.

## 7. Build, scan, push

`1.1` is the release track. Bump `VERSION` and the tags together for the next release.

```bash
gcloud config set project cubewire
gcloud auth configure-docker gcr.io
docker buildx create --name ghlike --driver docker-container --use   # once, if missing

R=gcr.io/cubewire/cubewire-platform-marketplace

# Deployer (default target)
docker buildx build --builder ghlike --platform linux/amd64 \
  --provenance=false --sbom=false --build-arg VERSION=1.1 \
  --output "type=image,name=$R/deployer:1.1,push=true,oci-mediatypes=false" .

# Stub app images: one build, pushed to all seven paths
NAMES="$R:1.1,$R/webapp:1.1,$R/kms:1.1,$R/transactions:1.1,$R/policy-engine:1.1,$R/transaction-orch:1.1,$R/webhook-dispatcher:1.1"
docker buildx build --builder ghlike --platform linux/amd64 \
  --provenance=false --sbom=false --target stub \
  --output "type=image,\"name=$NAMES\",push=true,oci-mediatypes=false" .
```

Scan after every build (the target is 0 critical and 0 high):

```bash
trivy image --platform linux/amd64 --image-src remote --scanners vuln $R/deployer:1.1
docker pull --platform linux/amd64 $R/deployer:1.1   # Scout reads the local copy
docker scout quickview $R/deployer:1.1
```

Notes:
- **Rebuild to fix new CVEs.** Bases are `:latest` and nothing is pinned by digest, so a plain rebuild picks up Chainguard and Google's newest packages.
- Attestations are off on purpose. The Marketplace schema extractor failed on a multi-arch index with attestation manifests, so the images are single-platform Docker v2 manifests.
- Push each tag with its own build. `docker buildx imagetools create -t` re-wraps a single manifest into a new index with a different digest.
- Check images with `docker run --pull always`. Without it Docker runs a stale local copy, and Scout also analyses the local copy.
- Use `bash` for the commands above. zsh does not word-split unquoted variables.
- Before pushing a new tag to the app repositories, list their existing tags first. Do not overwrite `1.0` and `1.0.0`.

## 8. Patches

What we changed to get the deployer to **0 critical and 0 high** in both Trivy and Docker Scout. Each fix is in the `deployer-build` stage of the `Dockerfile`.

The starting point was Google's `deployer_helm:latest` base: 0 critical, 4 high, 53 medium, 24 low.

| # | Finding | Cause | Fix |
|---|---|---|---|
| 1 | 3 HIGH in `kubectl` (`golang.org/x/net`, `golang.org/x/text`) | Go libraries compiled into Google's kubectl 1.37 | Replaced `/opt/kubectl/v1.37/kubectl` with the binary from `cgr.dev/chainguard/kubectl:latest` (same minor, v1.37.2, scans clean) |
| 2 | 1 HIGH `setuptools` 70.3.0 (CVE-2025-47273) | Python package in the base | Uninstalled `setuptools` (nothing in the deploy tooling imports it) |
| 3 | The same `setuptools` 70.3.0 kept appearing after the upgrade | pip bundles a `bom.cdx.json` listing an old vendored copy, and scanners read it | Uninstalled `pip` (not used at runtime) |
| 4 | 1 HIGH `wheel` 0.37.1 (CVE-2022-40898) | Ubuntu's `python3-wheel`. Ubuntu backports the fix, but Scout matches on the version number | Purged `python3-wheel` and uninstalled the pip `wheel` |
| 5 | Medium and low OS findings | Packages the deployer does not need, and the libraries only they pulled in | Removed the packages below |
| 6 | Packages out of date | Base image lags behind Ubuntu security updates | `apt-get upgrade` on every build |

**Packages removed (23 fewer: 143 → 120)** after checking the deploy scripts do not use them:

| Removed | Why it was there / why it is safe to remove |
|---|---|
| `curl`, `wget` | Used to build the base image. No deploy script calls them. Dropped with them: `libcurl4`, `libssh-4`, `libldap-2.5-0`, `libsasl2-2`, `libsasl2-modules-db`, `librtmp1`, `libnghttp2-14`, `libbrotli1`, `libpsl5` |
| `gpg`, `gpgconf` | Key handling for apt repos. Not used at runtime. (`gpgv` stays: `apt` depends on it.) Dropped with them: `libassuan0` |
| `procps` | `ps`, `top`. Not used by any script |
| `gettext` | Replaced by `gettext-base`, which has `envsubst`, the only part the tooling uses. Dropped with it: `libicu70`, `libxml2`, `libgomp1` |
| `python3-wheel`, Ubuntu `python3-setuptools`, `python3-pkg-resources`, `python3-distutils`, `python3-lib2to3` | Build tooling for Python packages. Not used at runtime |
| pip: `setuptools`, `wheel`, `pip` | See rows 2 to 4 |

**Not removed, and why:**
- `e2fsprogs`: marked Essential on Ubuntu 22.04. Apt refuses to remove it without an override, and we do not force that.
- `jq`: the `kubectl` wrapper uses it to pick a kubectl version. It carries 7 medium findings in Ubuntu's `jq` and `libjq1`, with no fixed version available yet.
- `libgnutls30`, `libexpat1`, `dash`, `login`, `passwd`, `perl-base`, `tar` and similar base libraries: part of the Ubuntu base. Their findings are medium or low.

**Result (registry copy, 2026-11-24):**

| | Critical | High | Medium | Low |
|---|---|---|---|---|
| Google `deployer_helm:latest` | 0 | 4 | 53 | 24 |
| Our deployer `1.1` (Trivy) | 0 | 0 | 39 | 19 |
| Our deployer `1.1` (Docker Scout) | 0 | 0 | 28 | 10 |
| Stub app image (Trivy) | 0 | 0 | 0 | 0 |

Scout policies that still fail on the deployer: runs as root user, copyleft-licensed packages (Ubuntu base), and missing supply chain attestations (off on purpose, see section 7).

**Stub image:** a static Go binary on `cgr.dev/chainguard/static:latest` (distroless, no shell, no package manager), built with the current Go from the Wolfi package index. Runs as `65532:65532`.

**Things that cost time, for next time:**
- An earlier approach (a custom Wolfi deployer with the Google tooling copied into this repo) was dropped. Wolfi's versioned `kubectl-1.35` and `kubectl-1.36` packages carried many high findings, and upstream kubectl 1.30/1.31 binaries embed an old Go standard library. Building on Google's base and taking only kubectl from Chainguard was simpler and cleaner.
- Chainguard's `kubectl` and `helm` images do pull and scan clean. An earlier failure to pull them was a shell quoting mistake, not an access problem.

## 9. Producer portal

- Listing page: `https://console.cloud.google.com/marketplace/product/cubewire/cubewire-p8` (URL segment `cubewire-p8`).
- Status: **already published**. Changing product info needs approval and republishing.
- Product info as shown in the portal:
  - Name `Cubewire`; tagline "Driving Web3 Adoption for the next phase of digital finance".
  - Overview (382 chars) begins "Cubewire is a unified platform driving digital asset adoption with institutional-grade solutions…".
  - More info link `https://www.cubewire.com/`; category Blockchain and Data; industry Financial Services and Insurance.
  - Support: support@cubewire.com and `https://cubewire.atlassian.net/servicedesk/customer/portals`.
  - Keywords: blockchain payments, stablecoin, digital wallet, payment infrastructure, Web3, enterprise payments, wallet as a service, L2 blockchain. Product searchable: on.
- Deployer image field: `gcr.io/cubewire/cubewire-platform-marketplace/deployer`.
- Releases (from the earlier screenshot): `1.1` (default) and `1.0`. The portal records the **digest** when a release is proposed, so after any rebuild of `1.1` you must retry or re-propose the release so it picks up the new digest.
- History: schema extraction and the test deployment failed on an early `1.1` that was a plain `cat` image with no schema. The portal also showed "Image not found". Both were explained by that image's contents.
- Last portal result for the current `1.1`: `TODO` (record it here after retrying).
- Owners, process, last submission date: `TODO`.

## 10. Access and repo settings

- The images are **private**. Public access would be an `allUsers` binding with `roles/artifactregistry.reader` on the `gcr.io` repository in location `us`, and it applies to every image in that repository. Today only `cloud-commerce-partner@system.gserviceaccount.com` has read access (this is the account Marketplace uses).
- `master` on `Cubewire/cw-platform-marketplace` currently has **no branch protection**. A previous rule (1 approving review, enforced for admins, no force pushes or deletions) was removed by hand so direct pushes could go through.
- `.dockerignore` excludes `*.md`, so this README and any other doc never enter a build.

## 11. Open items

- **Retry the producer portal** against `deployer:1.1` and record the result in section 9.
- **Real app images for 1.1.** Today `1.1` of every app image is the stub. Decide before the release is shown to customers: do not make the stub-based `1.1` the default release for live customers.
- **OCI annotation** `com.googleapis.cloudmarketplace.product.service.name` on every image. Needs `SERVICE_NAME` from the Producer Portal Overview page. The Dockerfile still carries `goog-partner-solution="SOLUTION_URN"` as a placeholder label.
- **Tags:** the docs example pushes both the track tag and the full version (`1.1` and `1.1.0`). Only `1.1` is pushed. Decide whether to add `1.1.0`.
- **Tester image and tests** (`/data-test`), a **user guide**, and a **public repo with a LICENSE** are required for verification and publishing and do not exist yet.
- **Consumption tracking label.** `deployer/chart/templates/_helpers.tpl` still carries a comment to replace a placeholder with the value from the Producer Portal. Check what the portal expects.
- **Remaining findings:** 39 medium and 19 low in Ubuntu base packages (mostly `jq`). They clear when Ubuntu ships fixes; rebuild to pick them up.
- **Run as non-root:** the deployer runs as root like Google's base. Check with the Marketplace verification docs whether that is acceptable.
- Clean up the old experiment tags listed in section 6.
