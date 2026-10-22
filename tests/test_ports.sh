#!/usr/bin/env bash
# DS09 - La liste des ports publies par la stack vaut exactement {25565}.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ID="ports"
REQ="DS09"
start=$(date +%s)
result="OK"
proof_lines=()

published_ports="$(docker compose ps --format json | python3 -c '
import json, sys
ports = set()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    obj = json.loads(line)
    for p in obj.get("Publishers") or []:
        ports.add(p["PublishedPort"])
print(",".join(str(p) for p in sorted(ports)))
')"

proof_lines+=("Ports publies (docker compose ps): {${published_ports}}")
echo "Ports publies : {${published_ports}}"

if [ "$published_ports" != "25565" ]; then
  result="FAIL"
fi

nmap_output="$(nmap -p 25565,25575 127.0.0.1)"
proof_lines+=("$nmap_output")
echo "$nmap_output"

if ! echo "$nmap_output" | grep -q "25565/tcp open"; then
  result="FAIL"
fi
if echo "$nmap_output" | grep -q "25575/tcp open"; then
  result="FAIL"
fi

end=$(date +%s)
duration=$((end - start))
proof="$(printf '%s\n' "${proof_lines[@]}")"

write_report "$ID" "$REQ" "$result" "$duration" "$proof"

if [ "$result" != "OK" ]; then
  echo "TEST $ID FAILED" >&2
  exit 1
fi
echo "TEST $ID OK"
