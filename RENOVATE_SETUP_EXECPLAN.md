# Renovate Setup ExecPlan

## Purpose and Context

Configure the repository for the hosted Mend Renovate GitHub App while preserving its intentional rolling-update policy.
Renovate must manage only four dependency groups: the three Debian base-image references, the pinned Codex CLI, the
pinned Lima release, and the pinned k9s release. All unversioned apt packages, other global npm packages, Go `@latest`
installs, stable/latest download channels, installer scripts, and Neovim default branches must remain unmanaged.

The observable result is a repository-level Renovate configuration that validates strictly and whose local extraction
and lookup output contains only the selected dependencies. Debian image references will retain human-readable dated
tags and gain OCI digests. Codex will retain an exact npm version. Lima will retain a readable release version in both
its installer and `minimumLimaVersion`, gain SHA-256 verification for its macOS arm64 archive, and update those values
together. k9s will retain readable per-architecture versions adjacent to its existing SHA-256 values and update both
architectures together.

Relevant initial state:

- The working branch is `setup-renovate` and was clean before this plan was created.
- `docker/Dockerfile`, `docker/Azure.Dockerfile`, and `docker/Git.Dockerfile` use dated Debian tags without digests.
- `docker/Dockerfile` installs `@openai/codex@0.154.0`.
- `setup-lima.sh` downloads Lima `v2.2.0` without verifying a hash, while `lima/azure.yaml` requires Lima `2.2.0`.
- `docker/Azure.Dockerfile` installs k9s `v0.51.0` and verifies architecture-specific SHA-256 values.
- There is no existing Renovate configuration or CI workflow.
- Docker cannot run in this development environment. Node.js and npm are available, so Renovate's npm CLI can perform
  strict validation, local extraction, and live datasource lookups.

## Plan of Work

### Milestone 1: Establish the repository-level Renovate policy

Create `renovate.json` with the Renovate schema and `config:best-practices`. Restrict `enabledManagers` to the native
Dockerfile manager and explicitly declared regex custom managers. Add narrowly matched custom managers for:

- The Codex version in `docker/Dockerfile`, using the `npm` datasource.
- The Lima installer version and archive digest in `setup-lima.sh`, using `github-release-attachments`.
- The Lima minimum version in `lima/azure.yaml`, using `github-releases` with the leading `v` removed for YAML.
- The two k9s architecture-specific version/digest pairs in `docker/Azure.Dockerfile`, using
  `github-release-attachments`.

Group the multiple Lima records and multiple k9s records by package so each tool changes atomically. Do not declare
custom managers for any rolling dependency. Validation succeeds when strict config validation reports no errors or
migrations and extraction lists the intended managers without capturing unrelated values.

### Milestone 2: Make selected immutable inputs representable and verifiable

Update the three `FROM` instructions to `dated-tag@sha256:digest` using the current Docker Hub manifest-list digests.
Keep `sid-YYYYMMDD` for the main image and `stable-YYYYMMDD-slim` for the Azure and Git images so update pull requests
remain understandable.

Refactor the Lima install block to define a GitHub release tag and SHA-256 beside one another, derive both URL version
segments from that tag, download to a temporary file, verify it with the macOS-provided `shasum`, and extract it only
after successful verification. Keep `minimumLimaVersion` free of the GitHub tag's leading `v`.

Refactor the k9s architecture switch so each architecture contains its own adjacent release tag and digest. Continue
to verify the selected archive before extraction. Do not otherwise change the installed tools or their behavior.

Recovery for this milestone is to revert the task's local implementation commit. Individual edits are also reversible
by restoring the prior `FROM` references and the prior Lima/k9s blocks; no external resources or repository settings
are mutated by these file changes.

### Milestone 3: Verify the complete configuration

Run the following focused checks once after the related edits:

1. `npx --yes --package renovate -- renovate-config-validator --strict`.
2. Renovate local extraction with debug logging and `--platform=local --dry-run=extract`; confirm only Docker images,
   Codex, Lima, and k9s are extracted.
3. Renovate local lookup with `--platform=local`; confirm the npm, Docker, GitHub release, and release-attachment
   datasources resolve successfully, including both architecture-specific k9s hashes and the Lima hash.
4. Shell syntax checks for the changed shell/Dockerfile heredoc scripts and direct SHA-256 verification of the selected
   Lima and k9s release assets when practical.
5. Inspect `git diff --check`, the final diff, and repository status.

The local Renovate platform is experimental and cannot create branches or emulate every GitHub App behavior. A later
hosted-app onboarding run is the final integration check. Docker image builds and the macOS Lima installation cannot be
executed in this container; this limitation must be recorded rather than represented as successful validation.

## Progress

- [x] Repository state and selected dependency scope inspected.
- [x] Implementation and validation approach resolved.
- [x] Initial ExecPlan committed as `a8a0094`.
- [x] Current Debian, Lima, and k9s digests retrieved and verified.
- [x] `renovate.json` added and selected dependency representations updated.
- [x] Strict configuration validation and local extraction/lookup checks completed.
- [x] Validation evidence, final outcome, and the remaining hosted-app check recorded.
- [ ] **External follow-up:** Install the Mend Renovate GitHub App and confirm its first authenticated run resolves the
  grouped Lima and k9s release-attachment dependencies.

Exact next action: install the hosted App after publishing this branch, then inspect its first Dependency
Dashboard/update run for authenticated Lima and k9s resolution.

## Findings and Decisions

- Intentional `latest`, stable-channel, unversioned, and default-branch selectors are features of this repository and
  are excluded from Renovate ownership unless the user later opts one in.
- Dated Debian tags plus digests were chosen over channel-only tags because they combine an understandable image date
  with immutable OCI identity. Apt packages remain rolling and therefore the whole built image is not fully
  reproducible solely from the base-image digest.
- The hosted Mend Renovate GitHub App was selected over a self-hosted GitHub Action because all chosen updates can use
  built-in datasources and no executable post-upgrade task is required.
- `github-release-attachments` was selected for Lima and k9s because it can map a known release asset digest to the
  corresponding asset in a later GitHub release.
- Lima's GitHub tag includes `v`, while `minimumLimaVersion` currently does not. Separate grouped extraction rules will
  preserve the appropriate representation in each file.
- k9s needs one version/digest record per architecture because one Renovate dependency record supports one
  `currentDigest`; grouping the records preserves atomic updates.
- Docker Hub reported the current OCI index digests as
  `sha256:c1acdb109bacb5adf0f2078892ac177ee2e2ce6f88e96c5b743998b5489d36a9` for `sid-20260824` and
  `sha256:04634311a8d5fc442b6eb06d792293c4f3e2268652ca7634e00ce8ef5cc0a28a` for
  `stable-20260824-slim`. Renovate independently resolved both digests during lookup.
- Default Docker versioning considered the dated Debian tags unsupported. Narrow regex-versioning rules were added for
  `sid-YYYYMMDD` and `stable-YYYYMMDD-slim`; a subsequent live lookup successfully proposed `sid-20260918` and
  `stable-20260918-slim` together with their new digests.
- Strict validation succeeded with Renovate `44.99.0`. The local npm installation could not load its optional native
  RE2 binary and transparently validated with JavaScript `RegExp`; all configured expressions avoid RE2-incompatible
  features.
- Local extraction found exactly eight dependency records: three Debian image occurrences, Codex, two grouped Lima
  records, and two grouped k9s architecture records. No rolling dependency was extracted.
- Live unauthenticated lookup resolved Docker and npm successfully and found update proposals for the dated Debian
  images and Codex. It could not execute GitHub-backed release lookups because Renovate requires a GitHub token; none is
  present in this environment. The hosted App supplies that token. Direct upstream checksum manifests independently
  confirmed the committed Lima hash and both existing k9s hashes.
- `bash -n` succeeded for `setup-lima.sh` and the extracted k9s Dockerfile heredoc. The Lima installer's checksum command
  was exercised successfully. Both staged and unstaged diff checks passed.
- Docker builds and the macOS Lima installation were not run because this container cannot run Docker and is not a
  macOS arm64 host.

## Audit Log

- 2026-09-21: Created this ExecPlan after repository inspection. It records the user-approved narrow scope, resolves
  the manager/datasource design, defines implementation and recovery steps, and establishes validation criteria before
  any implementation changes are made.
- 2026-09-21: Implemented the scoped Renovate policy in `renovate.json`; pinned the three Debian base-image references
  to verified OCI digests; added verified Lima archive hashing; exposed grouped Lima and k9s version/digest records; and
  added narrow Debian dated-tag versioning after live lookup revealed the default Docker scheme could not advance those
  tags. Recorded successful strict validation, exact extraction counts, successful Docker/npm lookups, upstream hash
  checks, shell syntax checks, and the GitHub-token/Docker/macOS validation boundaries so the commit accurately reflects
  what was and was not proven locally.
- 2026-09-21: Recorded implementation commit `1944ae7` and advanced the exact next action to the external hosted-App
  run. This closes local execution while keeping the remaining authenticated integration check explicit.
- 2026-09-21: Renamed `renovate.json5` to `renovate.json` because the configuration uses strict JSON and contains no
  comments or JSON5-only syntax. Updated all ExecPlan references and revalidated discovery under the canonical name.
