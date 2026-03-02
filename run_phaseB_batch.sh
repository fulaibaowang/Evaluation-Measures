#!/usr/bin/env bash
#
# Run BioASQ EvaluatorTask1b Phase B on explicit (golden, system) file pairs; write one TSV report.
#
# Usage (use one line or put \ at end of each line to continue):
#   ./run_phaseB_batch.sh --pair <golden.json> <system.json> [--pair <g2> <s2> ...] [-o report.tsv]
#   ./run_phaseB_batch.sh --pairs <file.tsv> [-o report.tsv]
#
# Example: ./run_phaseB_batch.sh --pair gold/13B1.json sys/out_13B1.json -o report.tsv
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
OUTPUT_TSV="phaseB_report.tsv"
PERQUESTION=false

# Parse: --pair G S (repeatable), --pairs FILE, -o FILE, -perQuestion
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

# Phase B output order (14): YN_Acc..YN_F1_no, then R_2_Rec, R_2_F1, R_SU4_Rec, R_SU4_F1
HEADER="split\tYN_Acc\tF_Strict\tF_Lenient\tF_MRR\tL_P\tL_R\tL_F1\tYN_macroF1\tYN_F1_yes\tYN_F1_no\tR_2_Rec\tR_2_F1\tR_SU4_Rec\tR_SU4_F1"
echo -e "$HEADER" > "$OUTPUT_TSV"
PERQ_HEADER="split\tquestion_id\tYN_Acc\tF_Strict\tF_Lenient\tF_MRR\tL_P\tL_R\tL_F1\tYN_macroF1\tYN_F1_yes\tYN_F1_no\tR_2_Rec\tR_2_F1\tR_SU4_Rec\tR_SU4_F1"
if [[ "$PERQUESTION" == true ]]; then
  PERQ_FILE="${OUTPUT_TSV%.tsv}_perq.tsv"
  echo -e "$PERQ_HEADER" > "$PERQ_FILE"
fi

for i in "${!PAIRS_SYSTEM[@]}"; do
  golden_path="${PAIRS_GOLDEN[$i]}"
  system_path="${PAIRS_SYSTEM[$i]}"
  if [[ ! -f "$golden_path" ]]; then
    echo "Skip (golden not found): $golden_path" >&2
    echo -e "$(basename "$system_path" .json)\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA" >> "$OUTPUT_TSV"
    continue
  fi
  if [[ ! -f "$system_path" ]]; then
    echo "Skip (system not found): $system_path" >&2
    echo -e "$(basename "$system_path" .json)\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA" >> "$OUTPUT_TSV"
    continue
  fi
  split_id=$(basename "$system_path" .json)

  java_args=(-phaseB -e "$VERSION")
  [[ "$PERQUESTION" == true ]] && java_args+=(-perQuestion)
  java_args+=("$golden_path" "$system_path")
  out=$(java -Xmx10G -cp "$CP" evaluation.EvaluatorTask1b "${java_args[@]}" 2>&1) || true

  # Metrics line: starts with number, has enough fields (Phase B = 10 or 14 columns; last 4 may be NA)
  line=$(echo "$out" | awk '/^[0-9.]/ { n=NF; if (n>=10) line=$0 } END { if (n>=10) print line }')
  # If we requested -perQuestion but got no metrics, JAR may not support it; retry without -perQuestion
  if [[ -z "$line" && "$PERQUESTION" == true ]]; then
    out=$(java -Xmx10G -cp "$CP" evaluation.EvaluatorTask1b -phaseB -e "$VERSION" "$golden_path" "$system_path" 2>&1) || true
    line=$(echo "$out" | awk '/^[0-9.]/ { n=NF; if (n>=10) line=$0 } END { if (n>=10) print line }')
    [[ -z "$line" ]] || echo "Note: JAR does not support -perQuestion; rebuild from source for per-question stats. Aggregate only for: $split_id" >&2
  fi

  if [[ "$PERQUESTION" == true ]]; then
    echo "$out" | grep $'^PERQ\t' | sed $'s/^PERQ\t//' | while IFS= read -r rest; do
      echo -e "${split_id}\t${rest}" >> "$PERQ_FILE"
    done
  fi

  if [[ -z "$line" ]]; then
    echo "No metrics for: $split_id" >&2
    echo -e "${split_id}\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA" >> "$OUTPUT_TSV"
    continue
  fi

  row=$(echo "$line" | awk -v split_id="$split_id" -v OFS='\t' '{
    printf "%s", split_id;
    for (i=1;i<=NF && i<=14;i++) printf "\t%s", $i;
    for (i=NF+1;i<=14;i++) printf "\tNA";
    printf "\n";
  }')
  echo "$row" >> "$OUTPUT_TSV"
  echo "Done: $split_id" >&2
done

echo "Report written to: $OUTPUT_TSV" >&2
[[ "$PERQUESTION" == true ]] && echo "Per-question report written to: $PERQ_FILE" >&2
wc -l < "$OUTPUT_TSV"
