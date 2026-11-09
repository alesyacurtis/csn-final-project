#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "$0")/../.."
client=$(timeout -k 2s 10s docker compose ps -q dns-client)
if [[ -z $client ]]; then
  echo 'FAIL: Start the dns-client service first.' >&2
  exit 1
fi

get_counters() {
  local metrics
  if ! metrics=$(timeout -k 2s 10s docker exec "$client" \
    curl -fsS --noproxy '*' --max-time 5 http://172.28.0.53:9153/metrics); then
    echo 'FAIL: Enable prometheus :9153 in the external block of dns/Corefile.' >&2
    return 1
  fi
  awk '
    /^coredns_cache_hits_total[{]/ { hits += $2 }
    /^coredns_proxy_request_duration_seconds_count[{]/ && /proxy_name="forward"/ { forwarded += $2 }
    END { printf "%.0f %.0f\n", hits, forwarded }
  ' <<< "$metrics"
}

check_query() {
  local label=$1 expected_hits=$2 expected_forwarded=$3
  local reply counters hits forwarded

  if ! reply=$(timeout -k 2s 10s docker exec "$client" \
    dig @172.28.0.53 example.com. A +tries=1 +time=4 \
    +noall +comments +answer +stats); then
    printf 'FAIL: %s DNS query failed.\n%s\n' "$label" "$reply" >&2
    return 1
  fi
  if ! grep -q 'status: NOERROR' <<< "$reply" ||
     ! grep -Eq '[[:space:]]IN[[:space:]]+A[[:space:]]+' <<< "$reply"; then
    printf 'FAIL: %s did not return NOERROR with an A record.\n%s\n' "$label" "$reply" >&2
    return 1
  fi

  counters=$(get_counters)
  read -r hits forwarded <<< "$counters"
  local hit_delta=$((hits - previous_hits))
  local forwarded_delta=$((forwarded - previous_forwarded))
  printf '%s | cache_hits=%d | forwarded=%d\n' "$label" "$hits" "$forwarded"

  if (( hit_delta != expected_hits || forwarded_delta != expected_forwarded )); then
    printf 'FAIL: %s expected cache_hits +%d and forwarded +%d.\n' \
      "$label" "$expected_hits" "$expected_forwarded" >&2
    return 1
  fi
  previous_hits=$hits
  previous_forwarded=$forwarded
}

get_counters >/dev/null
echo 'Waiting 31 seconds for any earlier cache entry to expire.'
sleep 31
baseline=$(get_counters)
read -r previous_hits previous_forwarded <<< "$baseline"
printf 'Baseline | cache_hits=%d | forwarded=%d\n' "$previous_hits" "$previous_forwarded"

check_query 'First query' 0 1
sleep 1
check_query 'Warm repeat' 1 0
sleep 31
check_query 'After TTL expiry' 0 1
echo 'PASS: CoreDNS forwarding, cache hit and TTL expiry.'
