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
  header_path="$(find "$tmp_dir" -type f -path '*/include/discordpp.h' | head -n 1)"
fi
if [[ -z "${header_path}" ]]; then
  header_path="$(find "$tmp_dir" -type f -path '*/discord_partner_sdk.framework/Headers/discordpp.h' | head -n 1)"
fi
if [[ -z "${header_path}" ]]; then
  echo "discordpp.h not found in archive."
  exit 1
fi
header_dir="$(dirname "$header_path")"

ios_framework_path="$(find "$tmp_dir" -type d -path '*/discord_partner_sdk.xcframework/*/discord_partner_sdk.framework' | grep '/ios-arm64' | grep -v 'simulator' | head -n 1)"
if [[ -z "${ios_framework_path}" ]]; then
  echo "iOS arm64 discord_partner_sdk.framework not found in archive."
  exit 1
fi

rm -rf "$out_dir"
mkdir -p "$out_dir/include/discord_partner_sdk" "$out_dir/ios"

cp -R "$ios_framework_path" "$out_dir/ios/"

if [[ -d "$header_dir/discord_partner_sdk" ]]; then
  cp -R "$header_dir/discord_partner_sdk/"* "$out_dir/include/discord_partner_sdk/"
else
  cp -f "$header_dir/discordpp.h" "$out_dir/include/discord_partner_sdk/discordpp.h"
  if [[ -f "$header_dir/cdiscord.h" ]]; then
    cp -f "$header_dir/cdiscord.h" "$out_dir/include/discord_partner_sdk/cdiscord.h"
  fi
  if [[ -f "$header_dir/discord_partner_sdk.h" ]]; then
    cp -f "$header_dir/discord_partner_sdk.h" "$out_dir/include/discord_partner_sdk/discord_partner_sdk.h"
  fi
fi

if [[ ! -f "$out_dir/include/discord_partner_sdk/discordpp.h" ]]; then
  echo "Prepared SDK is missing discordpp.h."
  exit 1
fi

if [[ ! -f "$out_dir/ios/discord_partner_sdk.framework/discord_partner_sdk" ]]; then
  echo "Prepared SDK is missing iOS framework binary."
  exit 1
fi

echo "Discord Social SDK prepared at: $out_dir"
