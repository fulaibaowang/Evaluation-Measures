#!/usr/bin/env bash
#
# Run BioASQ EvaluatorTask1b Phase A on explicit (golden, system) file pairs; write one TSV report.
#
# Usage (use one line or put \ at end of each line to continue):
#   ./run_phaseA_batch.sh --pair <golden.json> <system.json> [--pair <g2> <s2> ...] [-o report.tsv]
#   ./run_phaseA_batch.sh --pairs <file.tsv> [-o report.tsv] [-perQuestion]
#
# Example: ./run_phaseA_batch.sh --pair gold/13B1.json sys/out_13B1.json -o report.tsv
# With per-question stats: add -perQuestion; writes also <output_base>_perq.tsv
# Pairs file: TSV, two columns (golden_path, system_path), one pair per line. No header.
#

set -euo pipefail

BASE="$(dirname "$0")"
JAR="${BASE}/flat/BioASQEvaluation/dist/BioASQEvaluation.jar"
LIB="${BASE}/flat/BioASQEvaluation/lib"
if [[ ! -f "$JAR" ]]; then
  echo "JAR not found: $JAR" >&2
  exit 1
fi

# Explicit classpath so the evaluator runs without relying on manifest (avoids Windows paths from build)
CP="${CLASSPATH:-}:${JAR}:${LIB}/commons-cli-1.2.jar:${LIB}/gson-2.2.4.jar:${LIB}/SnowBallStemmer.jar"
VERSION=9
OUTPUT_TSV="phaseA_report.tsv"
PERQUESTION=false

# Parse: --pair G S (repeatable), --pairs FILE, -o FILE, --perQuestion
PAIRS_FILE=""
declare -a PAIRS_GOLDEN PAIRS_SYSTEM

while [[ $# -gt 0 ]]; do
  arg="$1"
  if [[ -z "${arg// }" ]]; then
    shift
    continue
  fi
  case "$arg" in
    -perQuestion|--perQuestion)
      PERQUESTION=true
      shift
      ;;
    --pair)
      if [[ $# -lt 3 ]]; then
        echo "Usage: --pair <golden.json> <system.json>" >&2
        exit 1
      fi
      PAIRS_GOLDEN+=("$2")
      PAIRS_SYSTEM+=("$3")
      shift 3
      ;;
    --pairs)
      if [[ $# -lt 2 ]]; then
        echo "Usage: --pairs <file.tsv>" >&2
        exit 1
      fi
      PAIRS_FILE="$2"
      shift 2
      ;;
    -o|--output)
      if [[ $# -lt 2 ]]; then
        echo "Usage: -o <output.tsv>" >&2
        exit 1
      fi
      OUTPUT_TSV="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: '${arg}'" >&2
      echo "Usage: $0 --pair <golden.json> <system.json> [--pair <g2> <s2> ...] [-o report.tsv]" >&2
      echo "   Or: $0 --pairs <pairs.tsv> [-o report.tsv]" >&2
      echo "Example (one line): $0 --pair gold/13B1.json sys/13B1.json -o report.tsv" >&2
      exit 1
      ;;
  esac
done

# Load pairs from file if given
if [[ -n "$PAIRS_FILE" ]]; then
  if [[ ! -f "$PAIRS_FILE" ]]; then
    echo "Pairs file not found: $PAIRS_FILE" >&2
    exit 1
  fi
  while IFS=$'\t' read -r g s _; do
    [[ -n "$g" && -n "$s" ]] || continue
    PAIRS_GOLDEN+=("$g")
    PAIRS_SYSTEM+=("$s")
  done < "$PAIRS_FILE"
fi

if [[ ${#PAIRS_GOLDEN[@]} -eq 0 ]]; then
  echo "No pairs given. Use --pair <golden.json> <system.json> (repeat) or --pairs <file.tsv>." >&2
  echo "Pairs file: TSV, two columns (golden_path, system_path), one pair per line." >&2
  exit 1
fi

# Phase A output order (20 numbers): concepts(5) documents(5) snippets(5) triples(5)
# c=concepts, d=documents, s=snippets, t=triples; P=Prec R=Rec F1 MAP GMAP
HEADER="split\tc_P\tc_R\tc_F1\tc_MAP\tc_GMAP\td_P\td_R\td_F1\td_MAP\td_GMAP\ts_P\ts_R\ts_F1\ts_MAP\ts_GMAP\tt_P\tt_R\tt_F1\tt_MAP\tt_GMAP"
echo -e "$HEADER" > "$OUTPUT_TSV"
PERQ_HEADER="split\tquestion_id\tc_P\tc_R\tc_F1\tc_MAP\tc_GMAP\td_P\td_R\td_F1\td_MAP\td_GMAP\ts_P\ts_R\ts_F1\ts_MAP\ts_GMAP\tt_P\tt_R\tt_F1\tt_MAP\tt_GMAP"
if [[ "$PERQUESTION" == true ]]; then
  PERQ_FILE="${OUTPUT_TSV%.tsv}_perq.tsv"
  echo -e "$PERQ_HEADER" > "$PERQ_FILE"
fi

for i in "${!PAIRS_SYSTEM[@]}"; do
  golden_path="${PAIRS_GOLDEN[$i]}"
  system_path="${PAIRS_SYSTEM[$i]}"
  if [[ ! -f "$golden_path" ]]; then
    echo "Skip (golden not found): $golden_path" >&2
    echo -e "$(basename "$system_path" .json)\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA" >> "$OUTPUT_TSV"
    continue
  fi
  if [[ ! -f "$system_path" ]]; then
    echo "Skip (system not found): $system_path" >&2
    echo -e "$(basename "$system_path" .json)\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA" >> "$OUTPUT_TSV"
    continue
  fi
  split_id=$(basename "$system_path" .json)

  java_args=(-phaseA -e "$VERSION")
  [[ "$PERQUESTION" == true ]] && java_args+=(-perQuestion)
  java_args+=("$golden_path" "$system_path")
  out=$(java -Xmx10G -cp "$CP" evaluation.EvaluatorTask1b "${java_args[@]}" 2>&1) || true

  # Metrics line: only a line that starts with a number and has many numeric fields (ignore "Exception..." etc.)
  line=$(echo "$out" | awk '/^[0-9.]/ { n=NF; if (n>=15) line=$0 } END { if (n>=15) print line }')
  # If we requested -perQuestion but got no metrics, JAR may not support it; retry without -perQuestion
  if [[ -z "$line" && "$PERQUESTION" == true ]]; then
    out=$(java -Xmx10G -cp "$CP" evaluation.EvaluatorTask1b -phaseA -e "$VERSION" "$golden_path" "$system_path" 2>&1) || true
    line=$(echo "$out" | awk '/^[0-9.]/ { n=NF; if (n>=15) line=$0 } END { if (n>=15) print line }')
    [[ -z "$line" ]] || echo "Note: JAR does not support -perQuestion; rebuild from source for per-question stats. Aggregate only for: $split_id" >&2
  fi

  # Per-question lines (prefix PERQ<tab>)
  if [[ "$PERQUESTION" == true ]]; then
    echo "$out" | grep $'^PERQ\t' | sed $'s/^PERQ\t//' | while IFS= read -r rest; do
      echo -e "${split_id}\t${rest}" >> "$PERQ_FILE"
    done
  fi

  if [[ -z "$line" ]]; then
    echo "No metrics for: $split_id" >&2
    echo -e "${split_id}\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA" >> "$OUTPUT_TSV"
    continue
  fi

  row=$(echo "$line" | awk -v split_id="$split_id" -v OFS='\t' '{
    printf "%s", split_id;
    for (i=1;i<=NF && i<=20;i++) printf "\t%s", $i;
    for (i=NF+1;i<=20;i++) printf "\tNA";
    printf "\n";
  }')
  echo "$row" >> "$OUTPUT_TSV"
  echo "Done: $split_id" >&2
done

echo "Report written to: $OUTPUT_TSV" >&2
[[ "$PERQUESTION" == true ]] && echo "Per-question report written to: $PERQ_FILE" >&2
wc -l < "$OUTPUT_TSV"
