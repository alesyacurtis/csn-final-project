# DNS Load Balancing — Implementation and Evaluation

## 1. Objective

The objective was to implement and evaluate DNS-based load
balancing using CoreDNS and three Nginx backend servers.

## 2. Environment

- Ubuntu 24.04.4 LTS
- Docker Engine 29.1.3
- Docker Compose 2.40.3
- CoreDNS 1.12.0
- Internal DNS zone: lab.test
- Test domain: app.lab.test

## 3. Implementation

The CoreDNS file plugin serves the internal DNS zone.
The loadbalance round_robin plugin randomizes the order
of A records returned in DNS responses.

Backend addresses:

- Backend 1: 172.28.0.11
- Backend 2: 172.28.0.12
- Backend 3: 172.28.0.13

The DNS server address is 172.28.0.53.

## 4. Methodology

A Bash script executed 100 DNS A-record queries
from the DNS client container.

Each response was checked for the presence of the
three expected IP addresses. The IP address appearing
first in each valid response was recorded.

## 5. Results

| Backend | First-position count | Percentage |
|---------|---------------------:|-----------:|
| 172.28.0.11 | 32 | 32.00% |
| 172.28.0.12 | 38 | 38.00% |
| 172.28.0.13 | 30 | 30.00% |
| Total | 100 | 100.00% |

Successful queries: 100.
Failed queries: 0.

Expected percentage under uniform randomization:
33.33% per backend.

Pearson's chi-square statistic: 1.04.
Degrees of freedom: 2.
Approximate p-value: 0.595.

## 6. Discussion

All 100 queries returned valid DNS answers containing
the three configured backend IP addresses.

Each backend IP appeared in the first position.
The observed proportions were 32%, 38%, and 30%.

The differences from the expected uniform distribution
were not statistically significant at alpha = 0.05.

The experiment evaluates DNS answer ordering.
It does not measure actual HTTP traffic distribution,
backend health checks, or application response times.

## 7. Conclusion

DNS-based load balancing was successfully configured
and tested using CoreDNS.

The experiment demonstrated correct DNS resolution
and variable ordering of backend IP addresses.

Further HTTP-level testing would be necessary to
evaluate actual request distribution.

## 8. Evidence

Detailed query records:
results/load_balancing/queries_20261109_154057.tsv

Statistical summary:
results/load_balancing/summary_20261109_154057.txt

Test script:
tests/load_balancing/test_load_balancing.sh
