#!/usr/bin/env bash
# If Config/devices.allow exists, only the UDIDs listed there are returned.
# Prints "<udid><TAB><name><TAB><paired|unpaired>" for every real iPhone this Mac knows about.
tmp=$(mktemp)
xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1
allow="$(dirname "$0")/../Config/devices.allow"
python3 - "$tmp" "$allow" <<'PY'
import json, os, re, sys
allowed = None
if os.path.exists(sys.argv[2]):
    allowed = {l.split('#')[0].strip() for l in open(sys.argv[2]) if l.split('#')[0].strip()}
for d in json.load(open(sys.argv[1]))['result']['devices']:
    hp, cp, dp = d.get('hardwareProperties', {}), d.get('connectionProperties', {}), d.get('deviceProperties', {})
    udid = hp.get('udid', '')
    if hp.get('platform') == 'iOS' and hp.get('deviceType') == 'iPhone' and re.fullmatch(r'[0-9A-F]{8}-[0-9A-F]{16}', udid) and (allowed is None or udid in allowed):
        print(f"{udid}\t{dp.get('name', 'iPhone')}\t{cp.get('pairingState', 'unpaired')}")
PY
rm -f "$tmp"
