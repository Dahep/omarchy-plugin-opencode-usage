# omarchy-plugin-opencode-usage

OpenCode usage widget for the Omarchy shell (Quickshell): token and cost
usage per configured provider (Zen, Go, Bedrock, ...) from the local
opencode.db, daily per-model breakdowns for the last 7 days, and OpenCode
Go limit windows via the go/v1/usage API.

## Install

    git clone <this repo>
    ln -s /path/to/this/checkout/src ~/.config/omarchy/plugins/local.opencode-usage

Edit files under `src/` and the Omarchy shell hot-reloads the plugin.
