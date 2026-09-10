# omarchy-plugin-opencode-usage

OpenCode usage widget for the Omarchy shell (Quickshell): token and cost
usage per configured provider (Zen, Go, Bedrock, ...) from the local
opencode.db, daily per-model breakdowns for the last 7 days, and OpenCode
Go limit windows via the go/v1/usage API.

Plugin ID: `io.github.dahep.opencode-usage`

## Install

Clone the repository into your Omarchy plugin directory and enable it:

    omarchy plugin add https://github.com/Dahep/omarchy-plugin-opencode-usage

## Remove

    omarchy plugin remove io.github.dahep.opencode-usage

## Dependencies

- `sqlite3` — reads the local OpenCode usage database (`~/.local/share/opencode/opencode.db`, read-only)
- `jq` — assembles the collector JSON output
- `curl` — queries the OpenCode Go usage API (`https://opencode.ai/zen/go/v1/usage`) when an `opencode-go` key exists in `~/.local/share/opencode/auth.json`

All three are standard on an Omarchy install. The collector never sends
your auth key anywhere except the official OpenCode Go usage endpoint and
never prints its contents.

## Files

- `manifest.json` — Omarchy shell plugin manifest (schemaVersion 1)
- `Panel.qml` — bar widget entry point
- `Service.qml` — refresh service running `collector.sh` on a timer
- `Model.js` — formatting and normalization helpers
- `collector.sh` — collects provider tokens/cost from the local database and Go limit windows

Edits under the installed plugin directory hot-reload; force a rescan with
`omarchy-shell shell rescanPlugins` if needed.

## License

MIT — see `LICENSE`.
