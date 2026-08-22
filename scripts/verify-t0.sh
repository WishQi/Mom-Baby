#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_destination=${MOMBABY_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6}
derived_data_path=${MOMBABY_DERIVED_DATA_PATH:-$repo_root/.build/T0DerivedData}

"$repo_root/scripts/verify-v1-schema.sh"

if rg -n \
  --glob '*.swift' \
  '\b(print|debugPrint|dump|NSLog)\s*\(' \
  "$repo_root/Mom-Baby" \
  "$repo_root/MomBabyCore/Sources"; then
  echo "Direct potentially sensitive logging is not allowed; use PrivacyLogger." >&2
  exit 1
fi

# The shared scheme pre-action runs the complete MomBabyCore SwiftPM suite.
xcodebuild test \
  -project "$repo_root/Mom-Baby.xcodeproj" \
  -scheme Mom-Baby \
  -testPlan Mom-Baby \
  -configuration Debug \
  -destination "$test_destination" \
  -derivedDataPath "$derived_data_path"

xcodebuild build \
  -project "$repo_root/Mom-Baby.xcodeproj" \
  -scheme Mom-Baby \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED=NO
