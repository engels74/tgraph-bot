# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

Docker packaging for TGraph Bot. There is **no application source here** — the Python app lives in
`engels74/tgraph-bot-source` and is downloaded as a tarball during `docker build`. Changes in this repo
affect only image composition and container runtime wiring (s6-overlay services).

## Essential Commands

Local build (requires Docker and `jq`, run from the repo root):

```bash
./build.sh amd64   # builds ./linux-amd64.Dockerfile, tags it "tgraph-bot-amd64"
./build.sh arm64
```

`build.sh` reads every key in `meta.json`, uppercases it, and passes it as `--build-arg`. Preview exactly
what gets passed with:

```bash
jq -r 'to_entries[] | [(.key | ascii_upcase),.value] | join("=")' < meta.json
```

There is no test suite, linter, formatter, or type checker configured here. Validation is "the image builds
and the container starts". `IMAGE_STATS` is injected by CI rather than by `meta.json`, so it is empty in
local builds.

## Architecture

Three moving parts:

1. **`meta.json`** — the source of truth for the build. Every key becomes an uppercased `--build-arg`.
   Keys ending in `__command` are *not* passed as build args; they are shell snippets that CI evaluates
   and writes back into the sibling key (`version__command` → `version`).
2. **`linux-<arch>.Dockerfile`** — starts `FROM ghcr.io/engels74/base-image:${UPSTREAM_TAG_SHA}`, fetches
   the app tarball into `${APP_DIR}`, `pip3 install`s it, then copies `root/` over `/`.
3. **`root/`** — overlaid onto the container filesystem; contains only s6-overlay v3 service definitions.

CI is fully delegated. `.github/workflows/call-build.yml` and `call-update.yml` are thin callers into
`engels74/base-image/.github/workflows/{build-on-call,update-on-call}.yml@workflows`. No build or publish
logic lives in this repo.

### Branch = published tag

Each branch is an independently maintained image variant. They are never merged into one another.

| Branch    | Publishes                              | `version` source                     | Tarball URL in Dockerfile      |
| --------- | -------------------------------------- | ------------------------------------ | ------------------------------ |
| `release` | `:release` and `:latest` (`latest: true`) | latest GitHub release tag, `v` stripped | `archive/v${VERSION}.tar.gz`   |
| `nightly` | `:nightly`                             | `main` branch commit SHA             | `archive/${VERSION}.tar.gz`    |

The `v` prefix differs per branch and must match that branch's `version__command` output. Never copy a
Dockerfile between branches without re-checking it.

Any push to any branch except `workflows` triggers `call-build`, which builds **and publishes** to
`ghcr.io/engels74/tgraph-bot`. There is no staging step.

## Runtime Wiring (`root/`)

Two s6-overlay v3 units:

- `init-setup-app` (`oneshot`) — installs `${APP_DIR}/config.yml.sample` to `${CONFIG_DIR}/config.yml` on
  first start; depends on the base image's `init-setup`.
- `service-tgraphbot` (`longrun`) — runs the bot as user `hotio`; depends on the base image's
  `init-wireguard`, because the upstream tag is `alpinevpn` and the app runs behind that VPN service.

`APP_DIR=/app`, `CONFIG_DIR=/config`, `UMASK`, the `hotio` user, and
`/etc/s6-overlay/scripts/bash-functions` are all provided by the base image. Use them; do not redefine
them here.

### Adding or renaming an s6 unit

1. Create `root/etc/s6-overlay/s6-rc.d/<name>/` with a `type` file (`oneshot` or `longrun`) and a `run` script.
2. For `oneshot`, add an `up` file containing the absolute in-container path to that `run` script.
3. Add one empty file per dependency under `<name>/dependencies.d/`.
4. Add an empty marker file at `root/etc/s6-overlay/user-bundles.d/user/contents.d/<name>`. Without it the
   unit is never started.

## Critical Gotchas

- **Bundle markers belong in `user-bundles.d/user/contents.d/`, not `s6-rc.d/user/contents.d/`.**
  s6-overlay >= 3.2.3.1 moved them (commit `c50aa0e`). Placing them under `s6-rc.d` silently disables the
  service instead of erroring.
- **`version`, `upstream_tag_sha`, and `packages.txt` are bot-maintained.** `call-update.yml` runs hourly,
  re-evaluates every `__command`, and commits `Modified: meta.json`. Hand-editing those values is
  pointless — to change how they resolve, edit the corresponding `__command` string.
- **Executable bits are not tracked in git** (every file is mode `644`). The Dockerfile's final line runs
  `find /etc/s6-overlay/s6-rc.d -name "run*" -execdir chmod +x {} +`, so only files named `run*` become
  executable at build time. Any other script you add needs its own `chmod` step in the Dockerfile.
- **`linux-amd64.Dockerfile` and `linux-arm64.Dockerfile` are byte-identical on `release`.** Apply every
  change to both. A missing per-architecture Dockerfile makes the build matrix skip that architecture
  silently rather than fail.
- **Infra fixes must be applied to each branch separately.** Every non-bot commit exists once per branch
  (for example `c50aa0e` on `release` and `8ff512b` on `nightly` are the same fix).
- **`README.md` is stale boilerplate.** The `release` copy is unmodified hotio text; the `nightly` copy
  links to a `master` branch that does not exist. Do not use it as evidence about this image.

## Additional Documentation

- `engels74/base-image` → `.github/workflows/build-on-call.yml` (branch `workflows`) — read before changing
  `meta.json` keys or reasoning about which tags get published. It defines tag derivation, `IMAGE_STATS`,
  and the optional smoke-test keys (`test_amd64`, `test_arm64`, `test_url`) that this repo does not set.
- `engels74/base-image` → `.github/workflows/update-on-call.yml` (branch `workflows`) — read before editing
  any `__command` field or changing how `packages.txt` is produced.
- `engels74/tgraph-bot-source` — read when the container fails at startup, to confirm the entrypoint path
  and CLI flags used in `root/etc/s6-overlay/s6-rc.d/service-tgraphbot/run` still exist for the pinned
  `version`.
