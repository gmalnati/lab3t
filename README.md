# GitOps Lab — Deploy via Argo CD (Lab 3)

This is a **skeleton** you clone, then use to bootstrap your own **config repo**:
the kind of repository Argo CD watches. A config repo holds *what runs where* —
a Helm chart plus one values file per environment — and nothing else. There is
no application source code here on purpose: the app is built in Lab 2 (the
`workshop-application` repo) and published as an immutable image. This repo only
declares the desired state of your cluster.

> **Block 5 — Delivery & GitOps.** Git becomes the single source of truth for
> what runs where. The cluster *pulls* its desired state and reconciles toward
> it. Nobody runs `kubectl apply` by hand; a reverted commit is a rollback.

## How the two repos relate

```
   workshop-application  (Lab 2)            workshop-git-ops-configuration  (this lab)
   ─────────────────────────────           ───────────────────────────────────────────
   source + Dockerfile + CI                Helm chart + per-env values
   builds & pushes an image  ───tag───►    deploy/envs/values-dev.yaml (image.tag)
   to registry.ff26.it                              │
                                                     │  Argo CD (in your cluster) watches
                                                     ▼
                                            your cluster reconciles toward Git
```

## What's in this skeleton — and why

| Path | What it is | Where it goes |
|------|-----------|---------------|
| `deploy/chart/` | The base manifests as a Helm chart (Deployment, Service, optional Ingress). Environment-agnostic. | **Pushed** into your config repo |
| `deploy/envs/values-{dev,staging,prod}.yaml` | The per-environment differences — image tag, replicas, resources, ingress host. Thin overlays on the chart. | **Pushed** into your config repo |
| `argocd/repo-secret.yaml` | Credentials so Argo CD can pull your *private* config repo (a GitHub PAT). | **Applied** to the cluster (`kubectl`) — stays in your local clone |
| `argocd/app-dev.yaml` | An Argo CD `Application`: "deploy `deploy/chart` with `values-dev.yaml` into namespace `demo-dev`, auto-sync." | **Applied** to the cluster |
| `argocd/app-staging.yaml` | Same, for staging — auto-sync, the place your test gates run. | **Applied** to the cluster |
| `argocd/app-prod.yaml` | Same, for prod — but **manual sync** (no `automated:`). Promotion needs a human. | **Applied** to the cluster |

**Why three `Application`s?** Each one maps one environment to one namespace,
pointing at the same chart but a different values file. That's the
dev → staging → prod promotion model: `app-dev` and `app-staging` auto-sync for
fast feedback; `app-prod` waits for a manual approval so production never
changes by accident.

## Your environment (already provided)

- A **personal cluster** — you have a kubeconfig for it. Point `kubectl` at it:
  `export KUBECONFIG=/path/to/your-kubeconfig`.
- **Argo CD** is already installed in the `argocd` namespace. Its UI is at
  `https://ecXY-argo.ff26.it` (replace `XY` with your participant number).
- **Traefik** is the ingress controller (`ingressClassName: traefik`).
- A shared image **registry** at `registry.ff26.it`.
- **external-dns + a Cloudflare tunnel** are wired up: any Ingress carrying the
  annotation `external-dns.alpha.kubernetes.io/target: 82051912-b874-49e9-955b-7a73552b75bc.cfargotunnel.com`
  gets a public DNS record automatically. The chart already sets this for you.

## Prerequisites on your laptop

- [`kubectl`](https://kubernetes.io/docs/tasks/tools/) and
  [Helm 3](https://helm.sh/docs/intro/install/).
- `git`, `docker` (for the image build in Step 7).
- Your kubeconfig exported and working: `kubectl get ns` should list `argocd`.

---

# The lab

## Step 1 — Create your config repo

On GitHub, create a new repository named **`workshop-git-ops-configuration`**
(private is fine — that's why we set up the PAT). Leave it empty.

## Step 2 — Push the `deploy/` folder into it

Clone your new repo and copy the `deploy/` folder from this skeleton into it:

```bash
git clone git@github.com:<you>/workshop-git-ops-configuration.git
cp -r /path/to/lab3t/deploy workshop-git-ops-configuration/
cd workshop-git-ops-configuration
```

> Only `deploy/` goes into the config repo. The `argocd/` manifests stay in your
> local clone of the skeleton — you apply them to the cluster with `kubectl`.

## Step 3 — Make the values yours (the only edits you need)

These are the "trivial" edits that make the skeleton *your* lab:

1. In `deploy/envs/values-dev.yaml` (and staging/prod if you use them), replace
   `ecXY` in the `host:` with your participant number, e.g. `ec07-quote-dev.ff26.it`.
2. Leave `image.tag: "REPLACE_ME"` for now — you'll set it in Step 7 once you've
   built an image. (Until then the pod will be `ImagePullBackOff`; that's
   expected and you'll *see* it in the Argo UI.)

Sanity-check the chart renders before Argo CD ever touches it:

```bash
helm template demo-app deploy/chart -f deploy/envs/values-dev.yaml
```

Commit and push:

```bash
git add deploy
git commit -m "GitOps config: chart + env overlays for ecXY"
git push -u origin main
```

## Step 4 — Create a PAT and give Argo CD read access

Argo CD runs in your cluster and pulls a *private* repo, so it needs a credential.

1. On GitHub: **Settings → Developer settings → Personal access tokens** →
   create a token (fine-grained, **Contents: Read-only** on
   `workshop-git-ops-configuration`, or a classic token with `repo` scope).
2. In your local clone of this skeleton, edit `argocd/repo-secret.yaml`: set
   `url`, `username` (your GitHub username), and `password` (the PAT).
3. Apply it:

```bash
kubectl apply -f argocd/repo-secret.yaml
```

## Step 5 — Apply the dev Application

Edit `argocd/app-dev.yaml` and set `repoURL` to your config repo URL (it must
match the `url` in `repo-secret.yaml`). Then:

```bash
kubectl apply -f argocd/app-dev.yaml
kubectl get applications -n argocd
```

## Step 6 — Open the UI and watch

Open `https://ecXY-argo.ff26.it` and log in (user `admin`; the initial password
is in the `argocd-initial-admin-secret` Secret if it hasn't been changed):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Watch Argo CD clone your repo, render the chart, and create the Deployment +
Service + Ingress in `demo-dev`. The Deployment will be **Progressing /
ImagePullBackOff** because the image tag is still `REPLACE_ME` — that's the
whole point of looking now: you can *see* the desired state and why it isn't
healthy yet.

## Step 7 — Build & push your image, then point the config at it

Now give it a real image. From your **`workshop-application`** clone (Lab 2):

```bash
cd /path/to/workshop-application

# Your images live under your own per-user namespace on the shared registry,
# so you don't collide with other participants:
#   registry.ff26.it/ec-0X/...   (replace ec-0X with your participant number)
export NS=ec-0X                                   # <-- replace ec-0X
export TAG=$(git rev-parse --short HEAD)

# Build the container (a Dockerfile ships in the workshop-application repo):
docker build -t registry.ff26.it/$NS/workshop-application:$TAG .

# Log in to the registry (credentials provided to you), then push:
docker login registry.ff26.it
docker push registry.ff26.it/$NS/workshop-application:$TAG

echo "Pushed image: registry.ff26.it/$NS/workshop-application:$TAG"   # write this down
```

Take note of the tag (and the `sha256:` digest the push prints — that digest is
the truly immutable reference). Now commit it into the config repo:

```bash
cd /path/to/workshop-git-ops-configuration
# set image.tag in deploy/envs/values-dev.yaml to your $TAG, e.g.:
#   image:
#     tag: "a1b2c3d"
git commit -am "dev: deploy image a1b2c3d"
git push
```

Within a minute Argo CD detects the commit, re-renders, and rolls the
Deployment. Watch it go **Synced / Healthy**:

```bash
kubectl rollout status deployment/demo-app-dev -n demo-dev
curl -s -X POST https://ecXY-quote-dev.ff26.it/quote \
  -H 'Content-Type: application/json' -d '{"subtotal": 150.00}'
# {"subtotal":150.00,"total":135.00}
```

That's the full GitOps loop: **you changed Git, the cluster followed. No
`kubectl apply` of the app, no `kubectl set image`.**

## Step 8 — Iterate (and roll back)

From now on the inner loop is: **change code → build → push a new tag → commit
the new tag in the config repo → Argo CD deploys it.**

Rollback is just Git, because the cluster's state *is* Git:

```bash
cd /path/to/workshop-git-ops-configuration
git revert HEAD --no-edit   # or open a PR setting the tag back
git push
```

Argo CD reconciles `demo-dev` back to the previous image — no rollback tooling.

> **Promotion.** To promote to staging/prod, set the same tag in
> `values-staging.yaml` / `values-prod.yaml` and apply `app-staging.yaml` /
> `app-prod.yaml`. Prod will sit **OutOfSync** until you click **Sync** in the
> UI — that's the manual production gate.

---

## Project layout

```
workshop-git-ops-configuration/        # the repo YOU create (Steps 1–2)
└─ deploy/
   ├─ chart/                           # the base manifests (env-agnostic Helm chart)
   │  ├─ Chart.yaml
   │  ├─ values.yaml                   # chart defaults (registry, port 8080, traefik)
   │  └─ templates/
   │     ├─ _helpers.tpl
   │     ├─ deployment.yaml            # + TCP liveness/readiness probes
   │     ├─ service.yaml
   │     └─ ingress.yaml               # traefik + external-dns annotation
   └─ envs/
      ├─ values-dev.yaml               # ← Step 7 sets image.tag here
      ├─ values-staging.yaml
      └─ values-prod.yaml

lab3t/ (this skeleton clone — NOT pushed to the config repo)
└─ argocd/
   ├─ repo-secret.yaml                 # PAT so Argo CD can read the private repo
   ├─ app-dev.yaml                     # automatic sync
   ├─ app-staging.yaml                 # automatic + gates
   └─ app-prod.yaml                    # manual approval (no automated syncPolicy)
```

---

# Appendix — automate the whole loop from CI

Doing it by hand teaches the model. In real life, your **`workshop-application`**
pipeline builds, pushes, *and* bumps the config repo for you — so a `git push`
to the app repo ends with a new version running in dev. Here's how.

### A1 — A PAT that can WRITE to the config repo

The app pipeline needs to commit to `workshop-git-ops-configuration`, so create
a PAT with **Contents: Read and write** on that repo (or classic `repo` scope).
Add it as a secret on the **`workshop-application`** repo:

- GitHub → `workshop-application` → **Settings → Secrets and variables →
  Actions → New repository secret**
  - `CONFIG_REPO_TOKEN` = the write-PAT
  - `REGISTRY_USERNAME` / `REGISTRY_PASSWORD` = your `registry.ff26.it` credentials

### A2 — Build & push, then bump the config repo

Add this workflow to **`workshop-application`** as
`.github/workflows/cd.yml`. It builds the image, pushes it to your per-user
namespace on `registry.ff26.it`, then checks out the config repo and
bumps `values-dev.yaml`:

```yaml
name: build-and-deploy
on:
  push:
    branches: [main]

env:
  # Your own per-user namespace on the shared registry (replace ec-0X).
  IMAGE: registry.ff26.it/ec-0X/workshop-application   # <-- change ec-0X

jobs:
  build-push:
    runs-on: ubuntu-latest
    outputs:
      tag: ${{ steps.meta.outputs.tag }}
    steps:
      - uses: actions/checkout@v4

      - id: meta
        name: Compute the image tag
        run: echo "tag=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"

      - uses: docker/setup-buildx-action@v3

      - name: Log in to registry.ff26.it
        uses: docker/login-action@v3
        with:
          registry: registry.ff26.it
          username: ${{ secrets.REGISTRY_USERNAME }}
          password: ${{ secrets.REGISTRY_PASSWORD }}

      # Option A: build from the Dockerfile shipped in this repo.
      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ env.IMAGE }}:${{ steps.meta.outputs.tag }}

      # Option B (no Dockerfile): use the Spring Boot buildpack task instead —
      #   ./gradlew bootBuildImage --imageName=$IMAGE:${{ steps.meta.outputs.tag }}
      #   docker push $IMAGE:${{ steps.meta.outputs.tag }}

  bump-config:
    needs: build-push
    runs-on: ubuntu-latest
    steps:
      - name: Checkout the config repo
        uses: actions/checkout@v4
        with:
          repository: <you>/workshop-git-ops-configuration   # <-- change me
          token: ${{ secrets.CONFIG_REPO_TOKEN }}
          path: config

      - name: Bump the dev image tag
        working-directory: config
        env:
          NEW_TAG: ${{ needs.build-push.outputs.tag }}
        run: |
          # yq is preinstalled on ubuntu-latest runners.
          yq -i '.image.tag = strenv(NEW_TAG)' deploy/envs/values-dev.yaml
          git config user.name  "ci-bot"
          git config user.email "ci-bot@users.noreply.github.com"
          git commit -am "dev: bump image to ${NEW_TAG}"
          git push
```

Now every push to `workshop-application` → builds + pushes a uniquely tagged
image → commits the new tag to `workshop-git-ops-configuration` → Argo CD
deploys it. That's Continuous Delivery end-to-end.

> Pinning by digest (`@sha256:…`) instead of a tag is the more rigorous
> version — the deck's "deploy by digest, not `latest`." Once comfortable,
> have the workflow capture the pushed digest and write *that* into the values.

## Notes for instructors

- The app repo (`workshop-application`, Lab 2) and this config repo are
  intentionally **separate**. A deploy here is a config change; the app's only
  output is a tagged image.
- `image.tag: REPLACE_ME` deliberately leaves the first sync unhealthy so
  learners *see* the desired-state/observed-state gap in the Argo UI before
  they supply a real image.
- The Ingress annotation is identical for every participant (one shared
  Cloudflare tunnel); only the `host` differs by participant number.
- Prod is manual-sync to demonstrate the promotion gate. Flip `app-prod.yaml`
  to `automated:` to show full Continuous Deployment and discuss the trade-off.
