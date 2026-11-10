#!/usr/bin/env bash
set -euo pipefail

COUNT="${1:-100}"

if [[ ! "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage: $0 [positive_query_count]" >&2
    exit 1
fi

cd "$(dirname "$0")/../.."

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATA="results/load_balancing/queries_${TIMESTAMP}.tsv"
SUMMARY="results/load_balancing/summary_${TIMESTAMP}.txt"

mkdir -p results/load_balancing

echo "Running $COUNT DNS queries..."

docker compose exec -T dns-client sh -s -- "$COUNT" <<'CLIENT' | tee "$DATA"
count="$1"

printf 'query\tstatus\tfirst_ip\tanswer_order\n'

i=1
while [ "$i" -le "$count" ]; do
    addresses=$(dig @172.28.0.53 app.lab.test. A \
        +noall +answer +tries=1 +time=2 2>/dev/null |
        awk '$1=="app.lab.test." && $4=="A" {print $5}')

    set -- $addresses
    valid=1

    [ "$#" -eq 3 ] || valid=0

    if [ "$valid" -eq 1 ]; then
        for expected in \
            172.28.0.11 172.28.0.12 172.28.0.13
        do
            case " $* " in
                *" $expected "*) ;;
                *) valid=0 ;;
            esac
        done
    fi

    if [ "$valid" -eq 1 ]; then
        printf '%s\tOK\t%s\t%s,%s,%s\n' \
            "$i" "$1" "$1" "$2" "$3"
    else
        printf '%s\tERROR\t-\t-\n' "$i"
    fi

    i=$((i + 1))
done
CLIENT

awk -F '\t' '
NR > 1 {
    total++
    if ($2 == "OK") {
        successful++
        count[$3]++
    } else {
        failed++
    }
}
END {
    printf "DNS LOAD BALANCING RESULTS\n"
    printf "Total requests: %d\n", total
    printf "Successful requests: %d\n", successful
    printf "Failed requests: %d\n\n", failed

    printf "%-16s %12s %12s\n", "Backend IP", "First place", "Percentage"

    for (i = 11; i <= 13; i++) {
        ip = "172.28.0." i
        pct = successful ? 100 * count[ip] / successful : 0

        printf "%-16s %12d %11.2f%%\n", \
            ip, count[ip], pct
    }
}
' "$DATA" | tee "$SUMMARY"

echo
echo "Detailed results: $DATA"
echo "Summary: $SUMMARY"
