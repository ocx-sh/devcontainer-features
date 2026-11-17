# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# dist-canonical.jq: render a parsed dist.json in the exact layout setup.ocx.sh publishes
# (run with jq -j). update-dist.sh refuses a manifest whose bytes differ from this rendering of its own
# content, so jq (the release guards) and the installer's grep/sed (src/ocx/install.sh) cannot read
# different values out of one file. Fixed on purpose: key order, one flat row per line, two spaces.
# A field upstream adds later fails the guard; that stops the release with an issue (fail closed).
def row: {version, channel, tag, target, filename, sha256, url} | tojson;

"{\n  \"schema\": \(.schema | tojson),\n  \"latest\": \(.latest | {version, channel} | tojson),\n  \"latest_next\": \(.latest_next | tojson),\n  \"releases\": [\n"
+ ([.releases[] | "    " + row] | join(",\n"))
+ "\n  ]\n}\n"
