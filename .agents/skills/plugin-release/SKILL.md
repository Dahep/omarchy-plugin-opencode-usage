---
name: plugin-release
description: >
  REQUIRED for releasing this plugin: version bumps, tagging, GitHub releases,
  and triggering omarchy-plugin-marketplace verification. Use when the user
  asks to release, ship a version, bump manifest.json, tag a release, publish
  an update to the plugin store, revalidate the marketplace issue, or when a
  maintainer reports a stale baseline SHA. Triggers: release, version bump,
  manifest.json version, tag, gh release, marketplace update, [Verify] issue,
  revalidate, stale baseline.
---

# Plugin release workflow

Release this plugin to the omarchy-plugin-marketplace. The marketplace is
exact-commit bound — see the global **omarchy-plugin-marketplace** skill for
the protocol; this skill is the repo-specific runbook. The `./release`
script implements every step below; prefer it over hand-running `gh` commands.

## The flow (ordering matters)

```
feature branch:  bump manifest.json version (BEFORE merge)
      │
      ▼
merge to main (PR)
      │
      ▼
./release tag          # verify origin/main, assert on main, tag, push tag
./release publish      # gh release + open [Verify] issue with full HEAD SHA
      │
      ▼
FREEZE main until maintainer applies approved-and-verified
(if HEAD moves: ./release revalidate or a fresh [Verify] issue for new HEAD)
```

Rules baked into this ordering:

- **Version bump happens on the feature branch before merge**, so
  `manifest.json` version == release tag == verified snapshot commit.
- **Tag the merge commit on `main`, never a feature-branch tip.** Every
  command re-verifies `origin/main` and asserts `git symbolic-ref HEAD` is
  `main` before mutating anything.
- **One release = one verify issue.** The marketplace's update path is a
  `[Verify]:` issue per cycle — never re-edit the submission issue for
  updates (that's only for unblocking a stale baseline mid-review).

## CLI

`./release <command> [args]` — every mutating command supports `--dry-run`
(print the exact diff/commands, change nothing) and is idempotent (re-running
a completed step is a no-op).

```bash
./release status                # show manifest version, HEAD, origin/main, tag/verify-issue state, drift check
./release bump <version>        # patch manifest.json version (use on feature branch, pre-merge)
./release tag [--dry-run]       # on main: tag v<version> at HEAD, push the tag
./release publish [--dry-run]   # gh release create + open [Verify] issue with full 40-char HEAD SHA
./release revalidate <issue> [--dry-run]
                                # real-content edit to an existing issue to retrigger validation
./release wait <issue>          # poll bot comments until validation + baseline pin the expected SHA
```

## Drift protection

The whole session that motivated this workflow was lost to a stale baseline
SHA. `status`, `tag`, and `publish` compare `git rev-parse origin/main`
against the SHA cited in any open `[Verify]` issue and exit non-zero on
mismatch with a loud warning. If drift happens: open a fresh `[Verify]` issue
for the new HEAD (or `revalidate` the open one) — never let a maintainer
approve against a stale SHA.

**The freeze itself cannot be enforced locally** — treat it as a checklist:
after `publish`, no direct pushes to `main` until the issue shows
`approved-and-verified`.

## Verify-issue body format

The router parses these headings exactly (from `verify-plugin.yml`):

```
### Verification action

Verify and publish a newer upstream commit

### Plugin ID

<from manifest.json>

### Repository URL

https://github.com/Dahep/omarchy-plugin-opencode-usage

### Target commit

<full 40-char HEAD SHA>
```

Title must start with `[Verify]:`.

## Testing changes to this repo

When touching `collector.sh`, use the local HTTP harness pattern: python
http.server stubs with `/ok` and oversized `/big` paths, throwaway fixture
`HOME` with a fixture `auth.json`, endpoint swapped via `sed`, background
server killed **by saved PID** (`$!`), never `pkill -f` (it matches its own
wrapper and hangs the shell). Capture `PIPESTATUS` on the line immediately
after the pipeline.
