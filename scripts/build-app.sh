#!/usr/bin/env bash
# Builds a release binary and wraps it in build/UsageBar.app (menu bar only, ad-hoc signed).
#
# Optional environment variables (the bundled Info.plist values are kept when unset or empty):
#   VERSION       sets CFBundleShortVersionString, format X.Y.Z (e.g. 1.2.3)
#   BUILD_NUMBER  sets CFBundleVersion, digits only (e.g. 42)
set -euo pipefail

version="${VERSION:-}"
build_number="${BUILD_NUMBER:-}"
if [[ -n "${version}" && ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: VERSION must look like X.Y.Z (digits only, no leading 'v'), got '${version}'" >&2
  exit 1
fi
if [[ -n "${build_number}" && ! "${build_number}" =~ ^[0-9]+$ ]]; then
  echo "error: BUILD_NUMBER must be digits only, got '${build_number}'" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${root}/build/UsageBar.app"

cd "${root}"
swift build -c release --product UsageBar
bin_dir="$(swift build -c release --show-bin-path)"

rm -rf "${app}"
mkdir -p "${app}/Contents/MacOS" "${app}/Contents/Resources"
cp "${bin_dir}/UsageBar" "${app}/Contents/MacOS/UsageBar"
cp "${root}/Resources/Info.plist" "${app}/Contents/Info.plist"

# The swiftbuild backend records the deployment target as the SDK version in
# LC_BUILD_VERSION, which makes macOS 26+ draw the app in its legacy
# (pre-Liquid-Glass) appearance. Stamp the real SDK version onto the bundled copy.
exe="${app}/Contents/MacOS/UsageBar"
real_sdk="$(xcrun --sdk macosx --show-sdk-version)"
build_info="$(vtool -show-build "${exe}")"
minos="$(awk '$1 == "minos" { print $2; exit }' <<<"${build_info}")"
recorded_sdk="$(awk '$1 == "sdk" { print $2; exit }' <<<"${build_info}")"
if [[ -z "${real_sdk}" || -z "${minos}" || -z "${recorded_sdk}" ]]; then
  echo "error: could not read SDK/minos version (sdk='${real_sdk}', binary minos='${minos}' sdk='${recorded_sdk}')" >&2
  exit 1
fi
if [[ "${recorded_sdk}" != "${real_sdk}" ]]; then
  vtool -set-build-version macos "${minos}" "${real_sdk}" -replace -output "${exe}.tmp" "${exe}"
  chmod +x "${exe}.tmp"
  mv -f "${exe}.tmp" "${exe}"
  echo "Stamped SDK ${real_sdk} (was ${recorded_sdk}, minos ${minos})"
else
  echo "SDK version already ${real_sdk} (minos ${minos})"
fi

plist="${app}/Contents/Info.plist"
if [[ -n "${version}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "${plist}"
fi
if [[ -n "${build_number}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build_number}" "${plist}"
fi
echo "Version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${plist}") (build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${plist}"))"

codesign --force --sign - --identifier com.usagebar.app "${app}"

echo "Built ${app}"
echo "Run it:      open \"${app}\""
echo "Install it:  cp -R \"${app}\" /Applications/"
