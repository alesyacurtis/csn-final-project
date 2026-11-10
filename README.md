# DNS Server with Caching and Load Balancing

A containerized DNS lab built with **Docker Compose**, **CoreDNS**, and **Nginx**. It demonstrates local DNS zone resolution, DNS-based load balancing through multiple A records, external DNS forwarding, and response caching.

## Overview

The project runs five containers on a dedicated Docker bridge network:

- **CoreDNS** — serves the internal `lab.test` zone, changes the order of DNS records for `app.lab.test`, and forwards external DNS queries to upstream resolvers.
- **DNS client** — a Debian-based container with `dig`, `nslookup`, and `curl` for interacting with the DNS server and backend services.
- **Three Nginx backends** — separate HTTP containers, each serving its own page so that the responding backend can be identified.

All services communicate over the `dns-lab` network (`172.28.0.0/24`). The DNS client is configured to use CoreDNS (`172.28.0.53`) as its resolver.

## Architecture

| Service | Role | IP address |
|---|---|---:|
| `dns-server` | CoreDNS DNS server | `172.28.0.53` |
| `dns-client` | DNS and HTTP client | `172.28.0.20` |
| `backend1` | Nginx backend 1 | `172.28.0.11` |
| `backend2` | Nginx backend 2 | `172.28.0.12` |
| `backend3` | Nginx backend 3 | `172.28.0.13` |

### DNS functionality

- **Internal DNS zone:** CoreDNS serves records for `lab.test` from `dns/zones/db.lab.test`.
- **Multiple A records:** `app.lab.test` resolves to the three backend addresses: `172.28.0.11`, `172.28.0.12`, and `172.28.0.13`.
- **DNS-based load balancing:** the CoreDNS `loadbalance` plugin changes the order of A records in DNS responses. This gives clients different backend addresses as the first result across queries.
- **External DNS forwarding:** queries outside `lab.test` are forwarded to Cloudflare DNS (`1.1.1.1`) and Google Public DNS (`8.8.8.8`).
- **DNS caching:** the CoreDNS `cache` plugin temporarily stores responses in the external DNS server block, with a configured maximum TTL of 30 seconds.

> **Important:** this project demonstrates DNS answer ordering, not HTTP load balancing by a reverse proxy. CoreDNS returns possible backend addresses; the client decides which address to contact. The experiment measures the order of DNS answers, not the distribution of HTTP requests. Backend health checks and automatic failover are not implemented.

## Technology Stack

- Docker Engine and Docker Compose
- CoreDNS `1.12.0`
- Nginx (`nginx:stable-alpine`)
- Debian Bookworm Slim (DNS client image)
- `dnsutils` (`dig`, `nslookup`) and `curl`
- Bash scripts for automated tests

## Repository Structure

```text
.
├── backends/
│   ├── backend1/
│   │   └── index.html
│   ├── backend2/
│   │   └── index.html
│   └── backend3/
│       └── index.html
├── compose.yml
├── dns/
│   ├── Corefile
│   └── zones/
│       └── db.lab.test
├── dns-client/
│   └── Dockerfile
├── docs/
│   └── load_balancing.md
├── results/
│   └── load_balancing/
│       ├── queries_20261109_154057.tsv
│       └── summary_20261109_154057.txt
├── tests/
│   ├── caching/
│   │   └── test_caching.sh
│   └── load_balancing/
│       └── test_load_balancing.sh
└── README.md
```

### Main files and directories

| Path | Description |
|---|---|
| `compose.yml` | Defines the five services, the Docker bridge network, static IP addresses, and configuration/page mounts. |
| `dns/Corefile` | Main CoreDNS configuration: internal zone handling, DNS record ordering, external forwarding, and caching. |
| `dns/zones/db.lab.test` | DNS zone file with SOA and NS records and the A records for `ns.lab.test` and `app.lab.test`. |
| `dns-client/Dockerfile` | Builds the client image and installs DNS utilities and `curl`. |
| `backends/backend*/index.html` | Individual pages served by the three Nginx backends. |
| `docs/load_balancing.md` | Detailed description of the DNS load-balancing experiment and its results. |
| `tests/caching/test_caching.sh` | Automated test for external DNS forwarding, cache hits, and cache expiration. |
| `tests/load_balancing/test_load_balancing.sh` | Automated test that validates DNS answers and records the first A-record address across multiple queries. |
| `results/load_balancing/` | Raw query data in TSV format and a summary from a load-balancing experiment. |

## Requirements

Before starting, install:

- **Docker Engine**
- **Docker Compose v2** (the `docker compose` command)
- **Git**

The first build requires network access to download the container images and build the DNS client image. External DNS forwarding also requires the environment to be able to reach the configured upstream resolvers.

The Compose file uses the subnet `172.28.0.0/24`. Make sure this subnet does not conflict with an existing local or Docker network.

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/alesyacurtis/csn-final-project.git
cd csn-final-project
```

Run the remaining commands from the repository root, where `compose.yml` is located.

### 2. Build and start the environment

```bash
docker compose up -d --build
```

This builds the DNS client image if needed, pulls the CoreDNS and Nginx images, creates the `dns-lab` network, and starts all five services.

### 3. Check the containers

```bash
docker compose ps
```

The expected services are `dns-server`, `dns-client`, `backend1`, `backend2`, and `backend3`.

### 4. Open the DNS client shell

```bash
docker compose exec dns-client bash
```

The client container is configured to use `172.28.0.53` as its DNS resolver. From inside the container, you can issue DNS queries and HTTP requests.

For example, to query the internal application name:

```bash
dig app.lab.test A
```

To explicitly send the query to CoreDNS:

```bash
dig @172.28.0.53 app.lab.test A
```

To query an external domain through the configured forwarding and caching path:

```bash
dig example.com A
```

To request a specific backend directly:

```bash
curl http://172.28.0.11
curl http://172.28.0.12
curl http://172.28.0.13
```

Exit the client shell with `exit` when finished.

## Automated Tests

Run test scripts from the repository root while the Compose environment is running.

### DNS load-balancing test

```bash
./tests/load_balancing/test_load_balancing.sh 100
```

The argument sets the number of DNS queries. For each query, the script checks that the expected three backend IP addresses are present, records their order, and extracts the first address. It writes timestamped query data to a TSV file and a summary to a text file under `results/load_balancing/`.

The documented 100-query run completed with 100 valid DNS answers. The first-position distribution was 32% for `172.28.0.11`, 38% for `172.28.0.12`, and 30% for `172.28.0.13`. These figures describe DNS answer ordering, not actual HTTP traffic distribution. See [`docs/load_balancing.md`](docs/load_balancing.md) for the methodology and interpretation.

### DNS caching and forwarding test

The caching test uses CoreDNS metrics to check an initial upstream lookup, a cache hit on a repeated query, and a new upstream lookup after the 30-second cache entry expires.

Before running the script, make sure the external (`.`) server block in `dns/Corefile` contains both `cache 30` and the Prometheus metrics directive `prometheus :9153`. Then recreate the DNS server and run the test:

```bash
docker compose up -d --force-recreate dns-server
sudo bash tests/caching/test_caching.sh
```

Use `sudo` only if your Docker setup requires elevated permissions. The test waits for the cache entry to expire, so it takes at least 31 seconds to complete.

In the documented performance comparison, two sets of 20 queries produced a median query time of **2 ms with caching enabled** and **13.5 ms with caching disabled**. These measurements are specific to the test environment and should not be treated as guaranteed performance figures.

## Useful Docker Commands

View logs from the DNS server:

```bash
docker compose logs -f dns-server
```

Restart the DNS server after changing its configuration:

```bash
docker compose restart dns-server
```

Stop and remove the containers and the project network:

```bash
docker compose down
```

Start the environment again later with `docker compose up -d`.

## Notes and Limitations

- The internal zone is authoritative for `lab.test`; external names are resolved through the configured upstream DNS resolvers.
- The 30-second TTL and cache configuration are intended for demonstrating cache behavior in a small lab environment. Query timings can vary with network conditions and the host machine.
- DNS record reordering does not guarantee an equal distribution of web requests. Client-side DNS caching and address-selection behavior affect which backend is contacted.
- The configured backend addresses are static. The project does not include backend health monitoring or automatic failover.

## Authors

- Alesia Shemiakina
- Gleb Petrov
- Ilyas Abdulkayumov

Computer Systems and Networks — Group M26-SNE-01
