# AGENTS.md

This file provides guidance to AI coding agents when working with code in this
repository.

## Scope

Docker packaging for TGraph Bot. **No application source lives here** — the Python app is
`engels74/tgraph-bot-source`, downloaded as a tarball during `docker build`. Changes here affect
image composition and container runtime wiring (s6-overlay) only.

## Branches are release channels

Each branch is an independently maintained image variant. They are never merged into one another,
so an infra fix must be committed to each branch separately.

| Branch    | Publishes                    | `version` resolves to                | Tarball URL in Dockerfile     |
| --------- | ---------------------------- | ------------------------------------ | ----------------------------- |
| `release` | `:release` + `:latest`       | latest GitHub release `tag_name`, `v` stripped | `archive/v${VERSION}.tar.gz` |
| `nightly` | `:nightly`                   | `main` branch commit SHA             | `archive/${VERSION}.tar.gz`   |

Any push to any branch except `workflows` builds **and publishes** to
`ghcr.io/engels74/tgraph-bot`. There is no staging step.

`release` is currently broken and is not a good template: source tags are bare (`0.3.2`), so
`archive/v0.3.2.tar.gz` 404s, and release `0.3.2` predates the `src/` + `pyproject.toml` layout that
its Dockerfile and `service-tgraphbot/run` assume. Use `nightly` as the reference for both.

## Commands

```bash
./build.sh amd64    # builds linux-amd64.Dockerfile, tags it "tgraph-bot-amd64"
./build.sh arm64
jq -r 'to_entries[] | [(.key|ascii_upcase),.value] | join("=")' < meta.json   # preview build args
```

Requires Docker and `jq`. There is no test suite, linter, formatter, or type checker here —
validation is "the image builds and the container starts". `IMAGE_STATS` is injected by CI, so it
is empty in local builds. On `release`, `build.sh` passes `--secret id=GIT_AUTH_TOKEN,env=TOKEN`
while no Dockerfile mounts that secret; export `TOKEN` before building, or drop the flag as
`nightly` already has.

## meta.json is the build contract

Every key is uppercased and passed as a `--build-arg`, except keys ending in `__command` — those
are shell snippets CI evaluates, writing the result into the sibling key (`version__command` →
`version`).

`version`, `upstream_tag_sha`, `packages_hash`, and `packages.txt` are bot-maintained:
`call-update.yml` runs hourly across every branch and commits `Modified: meta.json`. Hand-editing
those values is pointless — to change how one resolves, edit its `__command` string.

## CI lives in another repository

`.github/workflows/call-{build,update}.yml` are thin callers into
`engels74/base-image/.github/workflows/{build-on-call,update-on-call}.yml@workflows`. No build,
publish, or tag logic lives here.

The build job guards each arch with `test -f linux-<arch>.Dockerfile`, so a missing
per-architecture Dockerfile **silently skips** that architecture instead of failing. On `release`
the two Dockerfiles are byte-identical; apply every change to both.

## Container runtime (`root/`)

`root/` is copied over `/`. The base image (`ghcr.io/engels74/base-image:alpinevpn`) provides
`APP_DIR=/app`, `CONFIG_DIR=/config`, `UMASK`, the `hotio` user,
`/etc/s6-overlay/scripts/bash-functions`, and the `init-setup` / `init-wireguard` units. Use those;
do not redefine them here.

- `init-setup-app` (`oneshot`) — installs `${APP_DIR}/config.yml.sample` to
  `${CONFIG_DIR}/config.yml` on first start. Depends on `init-setup`.
- `service-tgraphbot` (`longrun`) — runs the bot as `hotio`. Depends on `init-wireguard`, because
  the upstream tag is `alpinevpn` and the app runs behind that VPN service.

The invocation differs per branch: `nightly` execs `/usr/bin/tgraph-bot --config-file …` (the
console script from the source repo's `[project.scripts]`), `release` execs
`python3 ${APP_DIR}/src/tgraph_bot/main.py <config>`. Confirm against the source layout for that
branch's pinned `version` before changing either.

### Adding or renaming an s6 unit

1. Create `root/etc/s6-overlay/s6-rc.d/<name>/` with a `type` file (`oneshot` or `longrun`) and a
   `run` script.
2. For `oneshot`, add an `up` file containing the absolute in-container path to that `run` script.
3. Add one empty file per dependency under `<name>/dependencies.d/`.
4. Add an empty marker file at `root/etc/s6-overlay/user-bundles.d/user/contents.d/<name>`. Without
   it the unit is never started.

## Gotchas

- **Bundle markers belong in `user-bundles.d/user/contents.d/`, not `s6-rc.d/user/contents.d/`.**
  s6-overlay >= 3.2.3.1 moved them (commit `c50aa0e`); the old location silently disables the
  service instead of erroring.
- **No file in this repo carries an executable bit** (every entry is mode `100644`). The Dockerfile's
  last line runs `find /etc/s6-overlay/s6-rc.d -name "run*" -execdir chmod +x {} +`, so only `run*`
  becomes executable. `service-tgraphbot/finish` currently ships non-executable — any script not
  named `run*` needs its own `chmod` step in **both** Dockerfiles.
- **`README.md` is not evidence about this image.** The `release` copy is unmodified hotio
  boilerplate; the `nightly` copy links to a `master` branch that does not exist. Read `meta.json`
  and the Dockerfiles instead.

## Reference

- `engels74/base-image` @ `workflows` → `.github/workflows/build-on-call.yml` — tag derivation,
  `IMAGE_STATS`, `latest`/`hide`/`version_branch`, and the optional smoke-test keys (`test_amd64`,
  `test_arm64`, `test_url`) this repo does not set. Read before adding or renaming a `meta.json` key,
  or before reasoning about which tags get published.
- `engels74/base-image` @ `workflows` → `.github/workflows/update-on-call.yml` — `__command`
  evaluation and `packages.txt` generation. Read before editing any `__command` field.
- `engels74/tgraph-bot-source` — read when the container fails at startup, to confirm the entrypoint,
  CLI flags, and `config.yml.sample` location still match for the pinned `version`.
