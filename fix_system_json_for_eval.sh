#!/usr/bin/env bash
# Convert system JSON to the format expected by BioASQ EvaluatorTask1b.
# - Root must be {"questions": [...]}  (script assumes this is already so)
# - For list/factoid, exact_answer must be array-of-arrays: [ ["a1"], ["a2"] ], not [ "a1", "a2" ]
# - yesno stays as string: "yes" / "no"
#
# Usage: ./fix_system_json_for_eval.sh input.json [output.json]
#        If output.json omitted, writes to stdout.

set -euo pipefail
IN="${1:-}"
OUT="${2:-}"

if [[ -z "$IN" ]] || [[ ! -f "$IN" ]]; then
  echo "Usage: $0 input.json [output.json]" >&2
  exit 1
fi

run_jq() {
  jq '
    .questions |= map(
      if .exact_answer | type == "array" then
        if (.exact_answer | length) > 0 and (.exact_answer[0] | type) == "string" then
          .exact_answer |= map(if type == "string" then [.] else . end)
        else
          .
        end
      else
        .
      end
    )
  ' "$@"
}

if [[ -n "$OUT" ]]; then
  run_jq "$IN" > "$OUT"
  echo "Wrote: $OUT" >&2
else
  run_jq "$IN"
fi
