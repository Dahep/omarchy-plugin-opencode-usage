#!/usr/bin/env bash
set -uo pipefail
AUTH_JSON="${OPENCODE_AUTH_JSON:-$HOME/.local/share/opencode/auth.json}"
GO_URL=https://opencode.ai/zen/go/v1/usage
DB="$HOME/.local/share/opencode/opencode.db"
CUTOFF=$(( $(date +%s)*1000-604800000 ))
MONTH_CUTOFF=$(( $(date +%s)*1000-30*86400000 ))

GO_MAX_BYTES=262144

collect_go() {
  local k out code size
  k=$(jq -r '.["opencode-go"].key // empty' "$AUTH_JSON" 2>/dev/null) || true
  [[ -n $k ]] || { echo '{"status":"No API key"}'; return; }
  tmpf=$(mktemp) || { echo '{"status":"network error"}'; return; }
  hdrf=$(mktemp) || { rm -f "$tmpf"; echo '{"status":"network error"}'; return; }
  chmod 600 "$tmpf" "$hdrf" 2>/dev/null
  trap 'rm -f "$tmpf" "$hdrf"' EXIT
  printf 'Authorization: Bearer %s\n' "$k" >"$hdrf"
  set +o pipefail
  curl -sS -m 10 -w $'\n%{http_code}' --header @"$hdrf" "$GO_URL" 2>/dev/null \
    | head -c $((GO_MAX_BYTES+1)) >"$tmpf"
  curl_stat=${PIPESTATUS[0]}
  set -o pipefail
  size=$(wc -c <"$tmpf")
  if (( size > GO_MAX_BYTES )); then
    echo '{"status":"response too large"}'
    return
  fi
  if [[ $curl_stat != 0 ]]; then
    echo '{"status":"network error"}'
    return
  fi
  out=$(<"$tmpf")
  rm -f "$tmpf"
  code=${out##*$'\n'}; out=${out%$'\n'*}
  [[ $code == 200 ]] || { jq -cn --arg s "HTTP $code" '{status:$s}'; return; }
  jq -e '.usage.rolling and .usage.weekly and .usage.monthly' >/dev/null 2>&1 <<<"$out" || { echo '{"status":"bad response"}'; return; }
  jq -c '{status:"ok",rolling:.usage.rolling,weekly:.usage.weekly,monthly:.usage.monthly}' <<<"$out"
}

provider_rows() {
  [[ -r $DB ]] || return
  sqlite3 -readonly "file:$DB?mode=ro" \
    "SELECT json_extract(data,'\$.providerID'),
            ROUND(SUM(CASE WHEN time_created > $MONTH_CUTOFF THEN COALESCE(json_extract(data,'\$.tokens.total'),0) ELSE 0 END)),
            ROUND(SUM(CASE WHEN time_created > $CUTOFF THEN COALESCE(json_extract(data,'\$.tokens.total'),0) ELSE 0 END)),
            ROUND(SUM(CASE WHEN time_created > $MONTH_CUTOFF THEN COALESCE(json_extract(data,'\$.cost'),0) ELSE 0 END),4),
            ROUND(SUM(CASE WHEN time_created > $CUTOFF THEN COALESCE(json_extract(data,'\$.cost'),0) ELSE 0 END),4)
     FROM message
     WHERE json_extract(data,'\$.providerID') IS NOT NULL
       AND json_extract(data,'\$.providerID') != ''
     GROUP BY 1 ORDER BY 5 DESC;" 2>/dev/null || true
}

model_rows() {
  [[ -r $DB ]] || return
  sqlite3 -readonly "file:$DB?mode=ro" \
    "SELECT json_extract(data,'\$.providerID'),
            COALESCE(json_extract(data,'\$.modelID'),'?'),
            date(time_created/1000,'unixepoch'),
            ROUND(SUM(COALESCE(json_extract(data,'\$.tokens.total'),0))),
            ROUND(SUM(COALESCE(json_extract(data,'\$.cost'),0)),4)
     FROM message
     WHERE time_created > $CUTOFF
       AND json_extract(data,'\$.providerID') IS NOT NULL
       AND json_extract(data,'\$.providerID') != ''
     GROUP BY 1,2,3 ORDER BY 4 DESC;" 2>/dev/null || true
}

providers='[]'
while IFS='|' read -r pid mo wk mc wc; do
  [[ -n $pid ]] || continue
  providers=$(jq -c --arg id "$pid" --argjson mo "${mo:-0}" --argjson wk "${wk:-0}" \
    --argjson mc "${mc:-0}" --argjson wc "${wc:-0}" \
    '. + [{pid:$id,tokensWeek:$wk,tokensMonth:$mo,costWeek:$wc,costMonth:$mc,hasKey:false}]' <<<"$providers")
done < <(provider_rows)

keys_json='[]'
while IFS= read -r k; do
  [[ -n $k ]] || continue
  keys_json=$(jq -c --arg k "$k" '. + [$k]' <<<"$keys_json")
done < <(jq -r 'to_entries[] | select(.value.key) | .key' "$AUTH_JSON" 2>/dev/null)

rows='[]'
while IFS='|' read -r pid mid d t c; do
  [[ -n $pid ]] || continue
  rows=$(jq -c --arg p "$pid" --arg m "$mid" --arg d "$d" \
    --argjson t "${t:-0}" --argjson c "${c:-0}" \
    '. + [{provider:$p,model:$m,date:$d,tokens:$t,cost:$c}]' <<<"$rows")
done < <(model_rows)

models_map=$(jq -c '
  group_by(.provider) | map(
    { key: .[0].provider
    , value: { modelList: (
        group_by(.model) | map(
          { modelName: .[0].model
          , tokensWeek: (map(.tokens) | add // 0)
          , costWeek: (map(.cost) | add // 0)
          , daily: (map({date: .date, tokens: .tokens, cost: .cost}) | sort_by(.date))
          }
        )
      )
    }
    }
  ) | from_entries
' <<<"$rows")

providers=$(jq -c --argjson keys "$keys_json" 'map(.hasKey = (.pid as $id | any($keys[]; . == $id)))' <<<"$providers")
providers=$(jq -c --argjson models "$models_map" \
  'map(.modelList = ($models[.pid].modelList // []))' <<<"$providers")

gojson=$(collect_go)

recent='[]'
if [[ -r $DB ]]; then
  while IFS='|' read -r d t c; do
    [[ -n $d ]] || continue
    recent=$(jq -c --arg d "$d" --argjson t "${t:-0}" --argjson c "${c:-0}" \
      '. + [{date:$d,tokens:$t,cost:$c}]' <<<"$recent")
  done < <(sqlite3 -readonly "file:$DB?mode=ro" \
    "SELECT date(time_created/1000,'unixepoch'),ROUND(SUM(COALESCE(json_extract(data,'\$.tokens.total'),0))),ROUND(SUM(COALESCE(json_extract(data,'\$.cost'),0)),4)
     FROM message WHERE time_created > $CUTOFF GROUP BY 1 ORDER BY 1;" 2>/dev/null || true)
fi

jq -cn --argjson providers "$providers" --argjson go "$gojson" \
  --argjson recentDays "$recent" \
  '{status:"ok",providers:$providers,go:$go,recentDays:$recentDays,updatedAt:(now|todateiso8601)}'
