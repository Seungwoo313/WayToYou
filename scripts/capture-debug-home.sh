#!/bin/zsh
set -euo pipefail

if (( $# != 4 )); then
    print -u2 "사용법: $0 <simulator-udid> <my-city-json> <partner-city-json> <output.png>"
    exit 64
fi

simulator_id="$1"
my_city_json="$2"
partner_city_json="$3"
output_path="$4"
bundle_id="com.seungwoo.WayToYou"

SIMCTL_CHILD_WTY_DEBUG_MY_CITY_JSON="$my_city_json" \
SIMCTL_CHILD_WTY_DEBUG_PARTNER_CITY_JSON="$partner_city_json" \
    xcrun simctl launch \
        --terminate-running-process \
        "$simulator_id" \
        "$bundle_id" \
        -debugAccount mina

sleep 3
xcrun simctl io "$simulator_id" screenshot "$output_path"
