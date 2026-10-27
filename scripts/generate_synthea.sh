#!/usr/bin/env bash
# Generate the Synthea population used by this project, then convert the CSVs
# we use into compressed Parquet under data/raw/.
#
# Everything that affects the output is pinned here: Synthea release, seeds,
# population size, state, reference/end date and exporter settings.
# Runs in GitHub Actions (.github/workflows/fetch-data.yml); needs Java 17+ and Python 3.
set -euo pipefail

SYNTHEA_VERSION="v3.3.0"
SYNTHEA_SHA256="8ba04f7d73abadd5a377e41edf24c5c83935a1cb07c6d982cd5db731ef1cf445"
SEED=42
CLINICIAN_SEED=42
POPULATION=2000          # living patients; Synthea also keeps the deceased
STATE="Massachusetts"
REFERENCE_DATE=20250630  # ages are computed relative to this date
END_DATE=20250630        # simulation stops here (otherwise it runs to "today")

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK_DIR:-$ROOT/.synthea_work}"
mkdir -p "$WORK"
cd "$WORK"

JAR="synthea-${SYNTHEA_VERSION}.jar"
if [ ! -f "$JAR" ]; then
  curl -sSL --retry 4 -o "$JAR" \
    "https://github.com/synthetichealth/synthea/releases/download/${SYNTHEA_VERSION}/synthea-with-dependencies.jar"
fi
echo "${SYNTHEA_SHA256}  ${JAR}" | sha256sum -c -

rm -rf output
CMD=(java -jar "$JAR"
  -s "$SEED" -cs "$CLINICIAN_SEED" -p "$POPULATION"
  -r "$REFERENCE_DATE" -e "$END_DATE"
  --exporter.baseDirectory ./output
  --exporter.csv.export true
  --exporter.csv.included_files patients.csv,encounters.csv,conditions.csv,medications.csv,observations.csv,organizations.csv,payers.csv
  --exporter.fhir.export false
  --exporter.hospital.fhir.export false
  --exporter.practitioner.fhir.export false
  "$STATE")
echo "Running: ${CMD[*]}"
"${CMD[@]}" > synthea.log 2>&1 || { tail -50 synthea.log; exit 1; }
tail -4 synthea.log

python3 "$ROOT/scripts/convert_to_parquet.py" "$WORK/output/csv" "$ROOT/data/raw" \
  --command "${CMD[*]}" --synthea-version "$SYNTHEA_VERSION"
