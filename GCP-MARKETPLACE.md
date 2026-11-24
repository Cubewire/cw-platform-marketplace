# Google Cloud Marketplace release guide

How this repo maps to a Google Cloud Marketplace Kubernetes app, and what to do for each release so nothing is missed.

Placeholders used below:

| Placeholder | Meaning |
|---|---|
| `<project>` | the Google Cloud project that hosts the Marketplace images |
| `<repo>` | the registry repository name for the app, for example `gcr.io/<project>/<app>` |
| `X.Y` | the release track, for example `1.1` |
| `X.Y.Z` | the full version, for example `1.1.0` |

---

## 1. How the package is laid out

A Marketplace Kubernetes app is a set of images in **one registry repository**, plus a deployer that installs them.

```
<repo>                      main application image
<repo>/deployer             the deployer image (what Marketplace runs in the customer's cluster)
<repo>/<other>              every other application image, one folder each
```

This repo builds the **deployer** (the default target of the `Dockerfile`). The deployer contains:

| In the image | Source in this repo |
|---|---|
| `/data/schema.yaml` | `deployer/schema.yaml` |
| `/data/chart/<chart>.tar.gz` | built at image build time from `deployer/chart/` |
| deploy scripts, `helm`, `kubectl`, entrypoint | Google's deployer base image (`deployer_helm`) |

The application images named in `deployer/schema.yaml` live in the same repository and are built from their own sources.

## 2. Versioning rules

Marketplace ties everything to a release track (`X.Y`) and a full version (`X.Y.Z`). These must agree:

| Where | What to set |
|---|---|
| `deployer/schema.yaml` | `x-google-marketplace.publishedVersion: "X.Y.Z"` |
| `deployer/chart/Chart.yaml` | `version: X.Y.Z` and `appVersion: "X.Y.Z"` |
| `deployer/chart/templates/application.yaml` | `spec.descriptor.version: "X.Y.Z"` |
| Application images | tags `X.Y` **and** `X.Y.Z`, same digest |
| Deployer image | tag `X.Y` (add `X.Y.Z` if the portal asks for it) |
| Portal release | display tag `X.Y`, pointing at the deployer digest |

Why this matters: the portal reads `publishedVersion` from the schema and looks for **every application image at the tag `X.Y.Z`**. If an application image only has `X.Y`, the functionality test fails with `Image not found: <repo>:X.Y.Z`.

Never overwrite or delete tags of an earlier release. Each release gets its own tags.

## 3. Release checklist

Work through this in order for every release.

**Prepare**
- [ ] Decide the new version, `X.Y.Z`, and update the three files in section 2.
- [ ] Update `deployer/schema.yaml` `releaseNote`.
- [ ] If the chart or schema changed, run `helm template` on the chart and the schema validator (section 5).
- [ ] List the existing tags in every repository, and confirm `X.Y` and `X.Y.Z` are not already used by something else.

**Build and publish**
- [ ] Build and push the application images, tagged `X.Y` and `X.Y.Z`.
- [ ] Build and push the deployer, tagged `X.Y` (section 4).
- [ ] Confirm the digests in the registry (section 5).

**Gate: security scan**
- [ ] Scan the deployer and every application image. The gate is **0 critical and 0 high**. Rebuild if not (section 6).

**Marketplace**
- [ ] In the Producer Portal, propose the release with display tag `X.Y` and the deployer image.
- [ ] Check that the digest shown matches the registry digest. The portal records the digest when a release is proposed, so after any rebuild you must retry or re-propose.
- [ ] Wait for schema extraction, the test deployment and the vulnerability scan to pass.
- [ ] Only then set the release as the default and publish.

**Requirements to confirm each release** (from Google's packaging page, section 7)
- [ ] The chart creates an Application resource, uses only beta or GA APIs, and puts everything in one namespace.
- [ ] Namespace, application name and every image reference are parameters.
- [ ] Images run on x86 (`linux/amd64`).
- [ ] Every image (the deployer and every application image) carries the manifest annotation `com.googleapis.cloudmarketplace.product.service.name=services/<service name>` (section 4). If it is missing, the functionality test fails with `Missing annotation ... in manifest of image: <image>`.
- [ ] Integration tests exist (a tester Pod that exits 0).
- [ ] A user guide exists (deployment, configuration, usage).
- [ ] The public repo has a `LICENSE`.
- [ ] The consumption tracking label in `deployer/chart/templates/_helpers.tpl` matches what the portal expects.

## 4. Build and push

Use `bash`. zsh does not split unquoted variables the way these commands expect.

```bash
gcloud config set project <project>
gcloud auth configure-docker gcr.io
docker buildx create --name ghlike --driver docker-container --use   # once

R=<repo>
V=X.Y.Z
T=X.Y
SVC="services/<service name>"     # see "Service name annotation" below
ANN="manifest:com.googleapis.cloudmarketplace.product.service.name=$SVC"

# Deployer (default target of the Dockerfile). Both tags are pushed by one build,
# so they always share a digest.
docker buildx build --builder ghlike --platform linux/amd64 \
  --provenance=false --sbom=false --build-arg VERSION=$T \
  --annotation "$ANN" \
  --output "type=image,\"name=$R/deployer:$T,$R/deployer:$V\",push=true,oci-mediatypes=true" .
```

Build every application image the same way: same `--annotation "$ANN"`, same `oci-mediatypes=true`, names `$R/<image>:$T,$R/<image>:$V`.

For a clean rebuild that picks up the newest base images, add `--no-cache --pull`.

To add a second tag to an image that is already pushed, tag it in the registry. Do not re-run `imagetools create`, which wraps the manifest in a new index and changes the digest:

```bash
gcloud container images add-tag "$R/<image>:$T" "$R/<image>:$V" --quiet
```

### Service name annotation

Every image must carry the annotation `com.googleapis.cloudmarketplace.product.service.name` with the value `services/<service name>`.

- **Where the annotation goes.** It is a manifest annotation, not a Dockerfile `LABEL`. A Docker v2 manifest has no annotations field, so the image must be pushed with OCI media types (`oci-mediatypes=true`) and `--annotation "manifest:<key>=<value>"`. Single-platform images carry it on the image manifest. A multi-platform image would need it on each manifest as well.
- **Service name.** It is shown in the Producer Portal on the Overview page, in the Service name column. It can also be listed from the command line: `gcloud endpoints services list --project <project>`. Pick the entry that matches the product's URL segment.
- **Every image, every release.** Rebuilding an image or adding a new image resets this: pass `--annotation` each time. Retagging an existing digest with `add-tag` keeps the annotation.
- **Rebuilding changes the digest.** After adding the annotation (or any rebuild) the portal must be pointed at the new deployer digest: retry or re-propose the release.

## 5. Verify

```bash
R=<repo>

# Digests: the two tags of an application image must match
docker buildx imagetools inspect $R/<image>:X.Y   | sed -n 3p
docker buildx imagetools inspect $R/<image>:X.Y.Z | sed -n 3p

# The service name annotation is in the manifest (expect services/<service name>)
docker buildx imagetools inspect $R/<image>:X.Y.Z --raw \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("annotations"))'

# Tag history of a repository
gcloud container images list-tags $R/deployer --filter='tags:*'

# Scans (the gate is 0 critical, 0 high)
trivy image --platform linux/amd64 --image-src remote --scanners vuln $R/deployer:X.Y
docker pull --platform linux/amd64 $R/deployer:X.Y
docker scout quickview $R/deployer:X.Y

# Deployer contents: run from the registry, not from a stale local copy
docker run --rm --pull always --platform linux/amd64 --entrypoint /bin/bash $R/deployer:X.Y -c '
  cat /version
  helm version --short
  bash -n /bin/deploy.sh && echo deploy-syntax-ok
  cd /tmp && tar -xzf /data/chart/*.tar.gz && helm template test /tmp/chart > /dev/null && echo chart-renders
  echo "{\"name\":\"t\",\"namespace\":\"t\"}" | python3 /bin/validate_schema.py --schema_file /data/schema.yaml --values_mode stdin && echo schema-valid'
```

## 6. Image hardening

The goal is **0 critical and 0 high** findings on every image in the release.

- Bases are `:latest` and are not pinned by digest. **Rebuilding is the vulnerability fix**: rebuild, scan, push.
- Application images use minimal Chainguard bases. The deployer is built on Google's own `deployer_helm` base, because the Marketplace tooling comes with it.
- The deployer build patches that base. It upgrades OS packages, takes `kubectl` from the Chainguard image, and removes build-time and download tools and Python packaging tools that the deploy scripts never use. Removing a package is checked against the scripts before it goes into the `Dockerfile`.
- Some packages cannot be removed because the base marks them Essential. Leave those alone.

Practical notes:
- Different scanners can disagree. Trivy and Docker Scout both need to be clean. Docker Scout reads the local copy of the image, so pull the pushed tag first.
- A scanner may report a package that was deleted in a later layer. Check the file system, and if needed flatten the final image.

## 7. Official documentation

Google Cloud docs, Kubernetes apps for partners:

- Requirements for packaging your app: <https://docs.cloud.google.com/marketplace/docs/partners/kubernetes/create-app-package>
- Set up your Google Cloud environment: `set-up-environment` in the same section
- Pricing model: `select-pricing` in the same section
- Updating Kubernetes apps: <https://docs.cloud.google.com/marketplace/docs/kubernetes-apps/update-app>

Detailed deployer, schema and verification docs are in the GitHub repo [marketplace-k8s-app-tools](https://github.com/GoogleCloudPlatform/marketplace-k8s-app-tools), under `docs/`:

- `building-deployer.md`: building the deployer image
- `schema.md`: the `x-google-marketplace` schema reference
- `verification-integration.md`: verification and the tester Pod
- `billing-integration.md`: usage reporting for commercial apps

Worked examples: [click-to-deploy `k8s/`](https://github.com/GoogleCloudPlatform/click-to-deploy/tree/master/k8s)

## 8. Important Checkpoints

- **Tags must exist for every image at `publishedVersion`.** Tagging only the track (`X.Y`) fails the functionality test.
- **The deployer must be a real Marketplace deployer.** An image without `/data/schema.yaml` and the deploy tooling fails schema extraction.
- **The service name annotation is checked on every image.** The portal reads it from the manifest of each image named in the schema and fails the functionality test if it is missing (`Missing annotation ... in manifest of image`). Docker v2 manifests cannot carry it, so push OCI manifests with `--annotation`.
- **Publish single-platform `linux/amd64` images** with `--provenance=false --sbom=false`. Marketplace only requires x86, and this keeps each tag a single manifest with a single digest.
- **The portal pins a digest.** After rebuilding a tag, retry or re-propose the release.
- **Check before pushing a tag.** Look at the existing tags in every repository first, so an earlier release is never overwritten.
- **Verify with `--pull always`.** Docker otherwise runs a stale local copy, and so does Docker Scout.
- **Each path in the registry is its own repository.** The main image, the deployer, and every other image are separate repositories under the app name, and each needs its own tags.
