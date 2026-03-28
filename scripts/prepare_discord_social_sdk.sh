#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <discord_social_sdk.zip> <output_dir>"
  exit 1
fi

zip_path="$1"
out_dir="$2"

if [[ ! -f "$zip_path" ]]; then
  echo "Input archive not found: $zip_path"
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

unzip -q "$zip_path" -d "$tmp_dir"

header_path="$(find "$tmp_dir" -type f -path '*/include/discord_partner_sdk/discordpp.h' | head -n 1)"
if [[ -z "${header_path}" ]]; then
  echo "discordpp.h not found in archive."
  exit 1
fi
include_root="$(dirname "$(dirname "$header_path")")"

ios_framework_path="$(find "$tmp_dir" -type d -path '*/discord_partner_sdk.xcframework/*/discord_partner_sdk.framework' | grep '/ios-arm64' | grep -v 'simulator' | head -n 1)"
if [[ -z "${ios_framework_path}" ]]; then
  echo "iOS arm64 discord_partner_sdk.framework not found in archive."
  exit 1
fi

rm -rf "$out_dir"
mkdir -p "$out_dir/include" "$out_dir/ios"

cp -R "$include_root/discord_partner_sdk" "$out_dir/include/"
cp -R "$ios_framework_path" "$out_dir/ios/"

if [[ ! -f "$out_dir/include/discord_partner_sdk/discordpp.h" ]]; then
  echo "Prepared SDK is missing discordpp.h."
  exit 1
fi

if [[ ! -f "$out_dir/ios/discord_partner_sdk.framework/discord_partner_sdk" ]]; then
  echo "Prepared SDK is missing iOS framework binary."
  exit 1
fi

echo "Discord Social SDK prepared at: $out_dir"
