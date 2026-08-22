#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
design_file="$repo_root/docs/MVP-IOS-TECHNICAL-DESIGN.md"
schema_file="$repo_root/MomBabyCore/Sources/Persistence/Resources/v1.sql"
verification_dir=$(mktemp -d "${TMPDIR:-/tmp}/mombaby-schema.XXXXXX")

cleanup() {
  rm -rf -- "$verification_dir"
}
trap cleanup EXIT HUP INT TERM

extracted_schema="$verification_dir/v1-from-design.sql"
database_path="$verification_dir/v1.sqlite"

awk '
  /^## 附录 A：P0-L v1 SQLite DDL$/ { in_appendix = 1; next }
  in_appendix && /^```sql$/ { capture = 1; block += 1; next }
  capture && /^```$/ {
    capture = 0
    if (block == 2) exit
    next
  }
  capture { print }
' "$design_file" > "$extracted_schema"

if ! cmp -s "$extracted_schema" "$schema_file"; then
  diff -u "$extracted_schema" "$schema_file" || true
  echo "v1.sql differs from the authoritative Appendix A DDL" >&2
  exit 1
fi

sqlite3 "$database_path" < "$schema_file" >/dev/null

object_counts=$(sqlite3 -separator : "$database_path" \
  "SELECT type, count(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%' GROUP BY type ORDER BY type;")
expected_counts='index:36
table:44
trigger:86'

if [ "$object_counts" != "$expected_counts" ]; then
  echo "Unexpected v1 schema object counts:" >&2
  echo "$object_counts" >&2
  exit 1
fi

application_id_ascii='MBBY'
application_id_hex='4D424259'
application_id_decimal=$(printf '%d' "0x$application_id_hex")

if [ "$application_id_decimal" != "1296187993" ]; then
  echo "application_id hexadecimal/decimal contract drifted: $application_id_decimal" >&2
  exit 1
fi

application_id_hex_from_ascii=$(printf '%s' "$application_id_ascii" \
  | od -An -tx1 \
  | tr -d ' \n' \
  | tr '[:lower:]' '[:upper:]')
if [ "$application_id_hex_from_ascii" != "$application_id_hex" ]; then
  echo "application_id ASCII/hexadecimal contract drifted: $application_id_hex_from_ascii" >&2
  exit 1
fi

application_id=$(sqlite3 "$database_path" "PRAGMA application_id;")
if [ "$application_id" != "$application_id_decimal" ]; then
  echo "Unexpected application_id: $application_id" >&2
  exit 1
fi

integrity_result=$(sqlite3 "$database_path" "PRAGMA integrity_check;")
if [ "$integrity_result" != "ok" ]; then
  echo "integrity_check failed: $integrity_result" >&2
  exit 1
fi

foreign_key_violations=$(sqlite3 "$database_path" "PRAGMA foreign_key_check;")
if [ -n "$foreign_key_violations" ]; then
  echo "foreign_key_check failed:" >&2
  echo "$foreign_key_violations" >&2
  exit 1
fi

echo "v1 schema verified: 44 tables, 36 indexes, 86 triggers"
