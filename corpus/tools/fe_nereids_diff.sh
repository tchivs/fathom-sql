#!/usr/bin/env bash
# ============================================================================
# FE/Nereids differential runner -- MANUAL ONLY, never CI (D-20, CORP-04)
#
# Runs the Apache Doris FE NereidsParser acceptance check over every corpus
# fixture and records fe_nereids_observation rows in corpus/differential.tsv
# with advisory_only=true.
#
# WHY MANUAL: the check requires a built Apache Doris FE (Java toolchain),
# which is offline-unavailable in this environment, so this script is written
# and documented but deliberately never executed in phase 02-06 and never
# wired into CI (D-20). The released-docs manifest stays the sole acceptance
# authority (D-07): an FE acceptance can never promote an unsupported fixture
# and an FE rejection can never demote a supported one.
#
# PARSER-ONLY (T-02-53): the check uses NereidsParser.parseSQL, a pure
# in-process parse of the official FE parser
# (fe/fe-core/src/main/java/org/apache/doris/nereids/parser/NereidsParser.java
# in the apache/doris repository). This script NEVER connects to a cluster,
# NEVER opens a session, and NEVER executes SQL against a database.
#
# PREREQUISITES (documented, not enforced -- manual step):
#   1. A checkout of https://github.com/apache/doris
#   2. A built FE: `mvn -pl fe/fe-core -am package -DskipTests` (see the
#      apache/doris README; JDK version required by the pinned FE release)
#   3. Either FE_CLASSPATH (preferred) or DORIS_SRC (auto-derived)
#
# USAGE:
#   FE_VERSION=4.1 DORIS_SRC=/path/to/doris bash corpus/tools/fe_nereids_diff.sh
#   FE_VERSION=4.1 FE_CLASSPATH="$(cat /tmp/fe-classpath.txt)" \
#     bash corpus/tools/fe_nereids_diff.sh
#
#   FE_VERSION  Doris release family the fixtures were taken from (default
#               4.1, matching the 4.x fixture set; the manifest profiles are
#               2.1 / 3.x / 4.x -- pin the FE release whose docs match).
#   DORIS_SRC   Path to an apache/doris checkout (built).
#   FE_CLASSPATH Colon-separated Java classpath including fe-core target
#               classes and FE dependency jars; overrides DORIS_SRC.
#   OUTPUT_TSV  Differential file to update (default corpus/differential.tsv).
#
# SAFETY: the script is idempotent -- it updates the fe_nereids_observation
# column of existing rows by fixture_id (appending a row only for a fixture
# id that has no row yet) and never duplicates rows or flips advisory_only.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPUS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$CORPUS_DIR/manifest.tsv"
OUTPUT_TSV="${OUTPUT_TSV:-$CORPUS_DIR/differential.tsv}"

# Doris release family matching the fixture set (2.1 / 3.x / 4.x docs).
FE_VERSION="${FE_VERSION:-4.1}"

# Phase 1 landed the SELECT fixture under its own file name; every later
# category (02-04 naming) uses <category>.sql inside corpus/doris-<profile>/.
fixture_sql_path() {
  local profile="$1" category="$2"
  local name="$category.sql"
  if [[ "$category" == "industrial-select" ]]; then
    name="select-industrial.sql"
  fi
  printf '%s/doris-%s/%s' "$CORPUS_DIR" "$profile" "$name"
}

usage() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

resolve_classpath() {
  if [[ -n "${FE_CLASSPATH:-}" ]]; then
    printf '%s' "$FE_CLASSPATH"
    return 0
  fi
  if [[ -z "${DORIS_SRC:-}" ]]; then
    echo "ERROR: set FE_CLASSPATH or DORIS_SRC (see header)" >&2
    usage
    return 1
  fi
  if [[ ! -d "$DORIS_SRC/fe/fe-core/target/classes" ]]; then
    echo "ERROR: $DORIS_SRC/fe/fe-core/target/classes not found; build FE first:" >&2
    echo "  cd $DORIS_SRC && mvn -pl fe/fe-core -am package -DskipTests" >&2
    return 1
  fi
  # FE target classes plus every FE dependency jar under the checkout.
  printf '%s/fe/fe-core/target/classes:' "$DORIS_SRC"
  find "$DORIS_SRC/fe" -name '*.jar' -type f | tr '\n' ':'
}

write_java_helper() {
  local dir="$1"
  cat > "$dir/NereidsAcceptanceCheck.java" <<'JAVA'
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import org.apache.doris.nereids.parser.NereidsParser;

/**
 * Parser-only FE acceptance probe (D-20, T-02-53): feeds one fixture SQL
 * file to NereidsParser.parseSQL (pure in-process parse, no cluster, no
 * session) and prints accepted/rejected. Exit code is always 0 so the
 * shell driver classifies from stdout.
 */
public class NereidsAcceptanceCheck {
  public static void main(String[] args) throws Exception {
    if (args.length != 1) {
      System.err.println("usage: NereidsAcceptanceCheck <fixture.sql>");
      System.exit(2);
    }
    String sql = new String(
        Files.readAllBytes(Paths.get(args[0])), StandardCharsets.UTF_8);
    try {
      new NereidsParser().parseSQL(sql);
      System.out.println("accepted");
    } catch (Throwable t) {
      System.out.println("rejected");
    }
  }
}
JAVA
}

# Update (or append) one fixture's fe_nereids_observation row.
record_observation() {
  local fixture_id="$1" observation="$2"
  if ! [[ -f "$OUTPUT_TSV" ]] || ! grep -q "^fixture_id$(printf '\t')" "$OUTPUT_TSV"; then
    printf 'fixture_id\tpublic_contract\tfe_nereids_observation\tsqlglot_observation\tsqlglot_version\tresolution\tadvisory_only\n' > "$OUTPUT_TSV"
  fi
  if grep -q "^$fixture_id$(printf '\t')" "$OUTPUT_TSV"; then
    awk -F '\t' -v OFS='\t' -v id="$fixture_id" -v obs="$observation" '
      NR == 1 { print; next }
      $1 == id { $3 = obs }
      { print }
    ' "$OUTPUT_TSV" > "$OUTPUT_TSV.tmp"
    mv "$OUTPUT_TSV.tmp" "$OUTPUT_TSV"
  else
    printf '%s\treleased-docs\t%s\tnot-run-offline\tnot-run-offline\tFE/Nereids manual observation for %s; advisory only, released-docs manifest wins (D-07)\ttrue\n' \
      "$fixture_id" "$observation" "$fixture_id" >> "$OUTPUT_TSV"
  fi
}

main() {
  local classpath
  if ! classpath="$(resolve_classpath)"; then
    return 1
  fi

  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' EXIT

  write_java_helper "$workdir"
  javac -cp "$classpath" -d "$workdir" "$workdir/NereidsAcceptanceCheck.java"

  echo "FE/Nereids differential (FE_VERSION=$FE_VERSION) -- parser-only, manual, advisory-only"
  local -a fields
  local fixture_id profile category path observation result
  local processed=0 accepted=0 rejected=0 skipped=0
  while IFS=$'\t' read -r -a fields; do
    [[ "${fields[0]}" == "fixture_id" ]] && continue
    fixture_id="${fields[0]}"
    profile="${fields[1]}"
    category="${fields[9]}"
    path="$(fixture_sql_path "$profile" "$category")"
    if [[ ! -f "$path" ]]; then
      observation="not-run-offline"
      skipped=$((skipped + 1))
    else
      result="$(java -cp "$workdir:$classpath" NereidsAcceptanceCheck "$path" || true)"
      case "$result" in
        accepted) observation="accepted"; accepted=$((accepted + 1)) ;;
        rejected) observation="rejected"; rejected=$((rejected + 1)) ;;
        *) echo "WARNING: unexpected FE probe output for $fixture_id: '$result'" >&2
           observation="not-run-offline"; skipped=$((skipped + 1)) ;;
      esac
    fi
    record_observation "$fixture_id" "$observation"
    processed=$((processed + 1))
  done < "$MANIFEST"

  echo "recorded fe_nereids_observation for $processed fixtures"
  echo "  accepted=$accepted rejected=$rejected not-run-offline=$skipped"
  echo "rows updated in $OUTPUT_TSV (advisory_only=true preserved everywhere)"
}

main "$@"
