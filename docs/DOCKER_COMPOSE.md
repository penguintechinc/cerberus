# Cerberus Docker Compose Deployment Guide

Comprehensive guide to deploying Cerberus using Docker Compose with support for multiple profiles and configurations.

## Table of Contents

1. [Overview](#overview)
2. [Profiles](#profiles)
3. [Service Architecture](#service-architecture)
4. [Configuration](#configuration)
5. [Deployment Scenarios](#deployment-scenarios)
6. [Health Checks](#health-checks)
7. [Network Configuration](#network-configuration)
8. [Data Persistence](#data-persistence)
9. [Resource Limits](#resource-limits)
10. [Troubleshooting](#troubleshooting)

## Overview

Cerberus Docker Compose provides a unified deployment mechanism for the complete NGFW/UTM system. It includes:

- **Core Services**: API, XDP, WebUI
- **Security Services**: IPS, Content Filter, SSL Inspector
- **VPN Services**: WireGuard, IPSec, OpenVPN
- **Infrastructure**: PostgreSQL, Redis, OpenSearch
- **Monitoring**: Prometheus, Grafana, Jaeger, Fluent Bit
- **Optional Modules**: Network Security Monitoring, Load Balancers, RTMP, Nginx

## Profiles

### Default (No Profile Flag)

**Use Case**: Standard NGFW deployment with essential services

**Services Included**:
- `postgres` - PostgreSQL 16 database
- `redis` - Redis 7 caching layer
- `opensearch` - OpenSearch 2.11 centralized logging
- `cerberus-api` - Flask control plane (port 5000)
- `cerberus-xdp` - eBPF/XDP packet processor (port 8080)
- `cerberus-webui` - React dashboard (port 3000)
- `cerberus-ips` - Suricata IPS (inline, real-time)
- `cerberus-filter` - Content filtering (port 8888)
- `cerberus-ssl-inspector` - SSL/TLS inspection (port 8889)
- `cerberus-vpn-wireguard` - WireGuard VPN (port 51820 UDP)
- `cerberus-vpn-ipsec` - IPSec VPN (ports 500, 4500 UDP)
- `cerberus-vpn-openvpn` - OpenVPN server (port 1194 UDP)
- `marchproxy-api-server` - xDS control plane (ports 8000, 18000)
- `marchproxy-nlb` - L3/L4 network load balancer (port 7000)
- `marchproxy-alb` - L7 application load balancer (ports 80, 443, 8443)
- `jaeger` - Distributed tracing (port 16686)
- `prometheus` - Metrics collection (port 9090)
- `grafana` - Visualization (port 3001)
- `fluent-bit` - Log shipping

**Start Command**:
```bash
docker compose up -d
```

**Memory Usage**: ~3-4 GB
**Disk Usage**: ~1 GB initial, grows with logs

### NSM Profile (Network Security Monitoring)

**Use Case**: Add advanced packet capture and analysis

**Additional Services**:
- `minio` - S3-compatible storage for PCAPs (port 9000, console 9001)
- `cerberus-arkime` - Real-time PCAP capture to S3
- `cerberus-zeek` - Batch PCAP analysis (Zeek IDS)
- `cerberus-ids` - Batch IPS analysis (Suricata IDS mode)

**Start Command**:
```bash
docker compose --profile nsm up -d
```

**Memory Usage**: Additional ~2 GB
**Storage**: MinIO bucket for PCAP storage (scales with traffic)
**Use Cases**:
- Full packet forensics and analysis
- Long-term threat hunting
- Compliance recording (PCI-DSS, etc.)

### Full Profile (All Services)

**Use Case**: Complete deployment with all optional modules

**Includes**: Default + NSM + Load Balancers + RTMP + AI/LLM

**Additional Services**:
- `marchproxy-dblb` - Database load balancer (ports 3306, 5433, 27017)
- `marchproxy-ailb` - AI/LLM load balancer (port 7003)
- `marchproxy-rtmp` - RTMP video transcoding (port 1935)

**Start Command**:
```bash
docker compose --profile full up -d
```

**Memory Usage**: ~6-8 GB
**Use Cases**:
- Multi-region deployments
- Database failover and load distribution
- AI/ML inference scaling
- Media/video content delivery

### Dashboards Profile

**Use Case**: Add optional web-based log dashboards

**Additional Services**:
- `opensearch-dashboards` - Kibana-like interface for logs (port 5601)

**Start Command**:
```bash
docker compose --profile dashboards up -d
```

**Combine with other profiles**:
```bash
docker compose --profile nsm --profile dashboards up -d
```

### Production Profile

**Use Case**: Production deployment with reverse proxy

**Additional Services**:
- `nginx` - Nginx reverse proxy with TLS (ports 8080 HTTP, 8443 HTTPS)

**Start Command**:
```bash
docker compose --profile production up -d
```

**Configuration**:
- Update `infrastructure/docker/nginx/nginx.conf`
- Place SSL certificates in `infrastructure/docker/nginx/ssl/`
- Configure upstream services in `infrastructure/docker/nginx/conf.d/`

### Custom Profile Combinations

```bash
# NSM + Dashboards
docker compose --profile nsm --profile dashboards up -d

# Full + Production
docker compose --profile full --profile production up -d

# Just monitoring additions
docker compose --profile dashboards --profile production up -d
```

## Service Architecture

### Infrastructure Layer

#### PostgreSQL (`postgres`)
- **Image**: `postgres:16-alpine`
- **Port**: 5432 (configurable via `POSTGRES_PORT`)
- **Health Check**: pg_isready
- **Volumes**: `postgres_data:/var/lib/postgresql/data`
- **Purpose**: Primary database for all services
- **Connection String**: `postgresql://{user}:{password}@postgres:5432/{database}`

**Key Variables**:
```bash
POSTGRES_DB=cerberus
POSTGRES_USER=cerberus
POSTGRES_PASSWORD=cerberus123
POSTGRES_PORT=5432
```

#### Redis (`redis`)
- **Image**: `redis:7-alpine`
- **Port**: 6379 (configurable via `REDIS_PORT`)
- **Health Check**: redis-cli ping
- **Volumes**: `redis_data:/data`
- **Purpose**: Caching, sessions, rate limiting
- **Connection**: `redis://:password@redis:6379/db`

**Key Variables**:
```bash
REDIS_PASSWORD=cerberus123
REDIS_PORT=6379
```

#### OpenSearch (`opensearch`)
- **Image**: `opensearchproject/opensearch:2.11.0`
- **Port**: 9200 (API), 9600 (performance metrics)
- **Health Check**: HTTPS health endpoint with auth
- **Volumes**: `opensearch_data:/usr/share/opensearch/data`
- **Purpose**: Centralized logging, full-text search, analytics
- **Connection**: `https://admin:password@opensearch:9200`

**Key Variables**:
```bash
OPENSEARCH_PASSWORD=Cerberus@123
OPENSEARCH_PORT=9200
OPENSEARCH_PERF_PORT=9600
```

### Cerberus Core Services

#### API (`cerberus-api`)
- **Image**: Built from `./services/flask-backend`
- **Port**: 5000
- **Dependencies**: PostgreSQL, Redis, OpenSearch
- **Health Check**: GET /healthz
- **Metrics Port**: 9105 (Prometheus)
- **Purpose**: NGFW control plane, policy management, authentication

**Key Environment**:
```bash
DB_TYPE=postgres
DB_HOST=postgres
MARCHPROXY_API_URL=http://marchproxy-api-server:8000
PROMETHEUS_URL=http://prometheus:9090
```

#### XDP (`cerberus-xdp`)
- **Image**: Built from `./services/go-backend`
- **Port**: 8080
- **Privileges**: `privileged: true`, CAP_BPF, CAP_NET_ADMIN, IPC_LOCK
- **Metrics Port**: 9106 (Prometheus)
- **Purpose**: eBPF/XDP packet steering, kernel-level processing
- **Volumes**: `/sys/fs/bpf`, `/sys/kernel/debug`

**Key Environment**:
```bash
XDP_ENABLED=true
XDP_MODE=skb                    # or 'native' for hardware acceleration
XDP_INTERFACE=eth0
NUMA_ENABLED=false              # Enable for multi-socket systems
MEMORY_POOL_SLOTS=1024          # Increase for high throughput
MEMORY_POOL_SLOT_SIZE=2048
```

#### WebUI (`cerberus-webui`)
- **Image**: Built from `./services/webui`
- **Port**: 3000
- **Dependencies**: cerberus-api
- **Health Check**: GET /healthz
- **Purpose**: React-based NGFW dashboard

**Key Environment**:
```bash
CERBERUS_API_URL=http://cerberus-api:5000
GRAFANA_URL=http://grafana:3000
OPENSEARCH_DASHBOARDS_URL=http://opensearch-dashboards:5601
```

### Security Services

#### IPS (`cerberus-ips`)
- **Image**: Built from `./services/cerberus-ips`
- **Type**: Suricata inline real-time IPS
- **Privileges**: `privileged: true`, CAP_NET_ADMIN, CAP_NET_RAW, SYS_NICE
- **Metrics Port**: 9100 (Prometheus)
- **Purpose**: Intrusion prevention system
- **Volumes**: `suricata_rules`, `suricata_logs`

#### Content Filter (`cerberus-filter`)
- **Image**: Built from `./services/cerberus-filter`
- **Port**: 8888 (default)
- **Metrics Port**: 9101 (Prometheus)
- **Purpose**: URL/content filtering proxy

#### SSL Inspector (`cerberus-ssl-inspector`)
- **Image**: Built from `./services/cerberus-ssl-inspector`
- **Port**: 8889 (default)
- **Purpose**: SSL/TLS decryption and inspection
- **Volumes**: `ssl_certs:/etc/cerberus/ssl`

### VPN Services

All VPN services are privileged containers with `NET_ADMIN` capability and sysctls for IP forwarding.

#### WireGuard (`cerberus-vpn-wireguard`)
- **Port**: 51820 UDP (configurable)
- **Modern protocol**, low latency, high performance
- **Config Volume**: `wireguard_config:/etc/wireguard`

#### IPSec (`cerberus-vpn-ipsec`)
- **Ports**: 500 (IKE), 4500 (NAT-T) UDP
- **Software**: StrongSwan
- **Config Volume**: `ipsec_config:/etc/ipsec.d`
- **Use Case**: Enterprise VPN compatibility

#### OpenVPN (`cerberus-vpn-openvpn`)
- **Port**: 1194 UDP (configurable)
- **Config Volume**: `openvpn_config:/etc/openvpn`
- **Use Case**: Wide client compatibility

### Monitoring & Observability

#### Jaeger (`jaeger`)
- **Image**: `jaegertracing/all-in-one:latest`
- **Port**: 16686 (UI)
- **Purpose**: Distributed tracing and span collection
- **Protocol**: Zipkin HTTP on 9411, Jaeger agents on 6831-6832

#### Prometheus (`prometheus`)
- **Image**: `prom/prometheus:latest`
- **Port**: 9090
- **Purpose**: Time-series metrics collection
- **Config**: `infrastructure/monitoring/prometheus/prometheus.yml`
- **Retention**: 200 hours default

#### Grafana (`grafana`)
- **Image**: `grafana/grafana:latest`
- **Port**: 3001 (mapped from 3000)
- **Purpose**: Metrics visualization and dashboards
- **Default Admin**: `admin / admin`
- **Data Source**: Pre-configured for Prometheus

#### Fluent Bit (`fluent-bit`)
- **Image**: `fluent/fluent-bit:latest`
- **Purpose**: Log shipping and forwarding
- **Output**: OpenSearch
- **Config**: `infrastructure/fluentbit/`

### MarchProxy Services

#### API Server (`marchproxy-api-server`)
- **Image**: Built from `./marchproxy/api-server`
- **Ports**: 8000 (REST API), 18000 (xDS gRPC)
- **Purpose**: xDS control plane for load balancers
- **Database**: PostgreSQL (shared with Cerberus)

#### NLB (`marchproxy-nlb`)
- **Port**: 7000 (configurable)
- **Purpose**: Layer 3/4 network load balancer
- **Features**: eBPF acceleration, rate limiting, health checks
- **Admin**: Port 7001

#### ALB (`marchproxy-alb`)
- **Ports**: 80 (HTTP), 443 (HTTPS), 8443, 9901 (admin)
- **Technology**: Envoy proxy
- **Purpose**: Layer 7 application load balancer
- **Features**: TLS termination, header rewriting, routing

## Configuration

### Environment Variables

Create `.env` file in project root (copy from `.env.example`):

```bash
# ============================================================================
# Core Services
# ============================================================================
FLASK_ENV=production
SECRET_KEY=change-me-in-production          # CRITICAL: Change in production
JWT_SECRET_KEY=change-me-jwt-secret         # CRITICAL: Change in production
DB_TYPE=postgres

# ============================================================================
# PostgreSQL
# ============================================================================
POSTGRES_DB=cerberus
POSTGRES_USER=cerberus
POSTGRES_PASSWORD=cerberus123
POSTGRES_PORT=5432

# ============================================================================
# Redis
# ============================================================================
REDIS_PASSWORD=cerberus123
REDIS_PORT=6379

# ============================================================================
# OpenSearch
# ============================================================================
OPENSEARCH_PASSWORD=Cerberus@123
OPENSEARCH_PORT=9200
OPENSEARCH_PERF_PORT=9600
OPENSEARCH_DASHBOARDS_PORT=5601

# ============================================================================
# Cerberus Core
# ============================================================================
CERBERUS_API_PORT=5000
CERBERUS_XDP_PORT=8080
WEBUI_PORT=3000

# ============================================================================
# XDP/eBPF Configuration
# ============================================================================
XDP_ENABLED=true
XDP_MODE=skb                    # 'skb' (default) or 'native' (hardware)
XDP_INTERFACE=eth0              # Network interface for XDP
NUMA_ENABLED=false              # Enable for multi-socket systems
MEMORY_POOL_SLOTS=1024
MEMORY_POOL_SLOT_SIZE=2048

# ============================================================================
# Suricata IPS
# ============================================================================
SURICATA_INTERFACE=eth0
IPS_RULES_URL=https://rules.suricata-ids.org/

# ============================================================================
# VPN Configuration
# ============================================================================
WG_PORT=51820
OVPN_PORT=1194

# ============================================================================
# Monitoring & Observability
# ============================================================================
PROMETHEUS_PORT=9090
GRAFANA_USER=admin
GRAFANA_PASSWORD=admin
GRAFANA_PORT=3001
GRAFANA_ROOT_URL=http://localhost:3001
JAEGER_ENABLED=true
LOG_LEVEL=info

# ============================================================================
# MarchProxy
# ============================================================================
MARCHPROXY_API_PORT=8000
MARCHPROXY_XDS_PORT=18000
NLB_PORT=7000
CLUSTER_API_KEY=default-api-key

# ============================================================================
# Network Security Monitoring (NSM Profile)
# ============================================================================
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
MINIO_ROOT_USER=cerberus
MINIO_ROOT_PASSWORD=cerberus123
ARKIME_INTERFACE=eth0
ARKIME_PORT=8005

# ============================================================================
# Production (Production Profile)
# ============================================================================
NGINX_HTTP_PORT=8080
NGINX_HTTPS_PORT=8443

# ============================================================================
# License (Optional - for PenguinTech License Server)
# ============================================================================
LICENSE_KEY=
LICENSE_SERVER_URL=https://license.penguintech.io
RELEASE_MODE=false              # Set to true for production license enforcement

# ============================================================================
# AI/LLM Integration (Full Profile)
# ============================================================================
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
ALB_RATE_LIMIT=true

# ============================================================================
# Advanced Performance Tuning
# ============================================================================
ENABLE_EBPF=true                # Enable eBPF acceleration
RATE_LIMIT_ENABLED=true
RATE_LIMIT_RPS=10000            # Requests per second
NUM_WORKERS=4                   # MarchProxy ALB workers
FFMPEG_THREADS=4                # RTMP profile only
```

## Deployment Scenarios

### Scenario 1: Basic NGFW (Default Profile)

```bash
# 1. Prepare
git clone <repo>
cd Cerberus
git submodule update --init
cp .env.example .env

# 2. Configure (optional - defaults are suitable for testing)
# Edit .env if needed

# 3. Deploy
docker compose up -d

# 4. Wait for healthy services
sleep 10
docker compose ps

# 5. Access
# WebUI: http://localhost:3000
# API: http://localhost:5000
# Metrics: http://localhost:9090
```

### Scenario 2: Enterprise with Full Monitoring

```bash
# Deploy with NSM and dashboards
docker compose --profile nsm --profile dashboards up -d

# Access additional services
# MinIO: http://localhost:9001
# OpenSearch Dashboards: http://localhost:5601
# Arkime: http://localhost:8005
```

### Scenario 3: Production Deployment

```bash
# Configure for production
export FLASK_ENV=production
export SECRET_KEY=$(openssl rand -hex 32)
export JWT_SECRET_KEY=$(openssl rand -hex 32)
export POSTGRES_PASSWORD=$(openssl rand -hex 16)
export REDIS_PASSWORD=$(openssl rand -hex 16)

# Deploy with all services and Nginx
docker compose --profile full --profile production up -d

# Configure Nginx
# 1. Update infrastructure/docker/nginx/conf.d/default.conf
# 2. Place SSL certs in infrastructure/docker/nginx/ssl/
# 3. Restart Nginx: docker compose restart nginx
```

### Scenario 4: Development with Hot Reload

```bash
# Use dev compose file
docker compose -f docker-compose.dev.yml up

# Code changes rebuild automatically
# Services reload on configuration changes
```

## Health Checks

Each service includes health checks. Monitor status:

```bash
# View all service health
docker compose ps

# Check specific service
docker compose exec cerberus-api wget -O- http://localhost:5000/healthz
docker compose exec cerberus-xdp wget -O- http://localhost:8080/healthz

# View health logs
docker compose logs --follow postgres
docker compose logs --follow cerberus-api
```

**Health Check Endpoints**:
- `cerberus-api`: GET `/healthz`
- `cerberus-xdp`: GET `/healthz`
- `cerberus-webui`: GET `/healthz`
- `cerberus-filter`: GET `/healthz`
- `cerberus-ssl-inspector`: GET `/healthz`
- `postgres`: `pg_isready`
- `redis`: `redis-cli ping`
- `opensearch`: HTTPS health endpoint
- `marchproxy-api-server`: GET `/healthz`
- Others: Various

## Network Configuration

### Network Topology

```
cerberus-network (172.30.0.0/16)
├── Infrastructure Tier
│   ├── postgres
│   ├── redis
│   └── opensearch
├── Core Services Tier
│   ├── cerberus-api
│   ├── cerberus-xdp
│   └── cerberus-webui
├── Security Services Tier
│   ├── cerberus-ips
│   ├── cerberus-filter
│   ├── cerberus-ssl-inspector
│   └── VPN services
├── MarchProxy Tier
│   ├── marchproxy-api-server
│   ├── marchproxy-nlb
│   └── marchproxy-alb
├── Observability Tier
│   ├── prometheus
│   ├── grafana
│   ├── jaeger
│   └── fluent-bit
└── Optional Tier
    ├── minio
    ├── arkime
    ├── zeek
    ├── opensearch-dashboards
    └── nginx
```

### Port Mapping

| Service | Container Port | Host Port | Protocol | Purpose |
|---------|----------------|-----------|----------|---------|
| **cerberus-webui** | 3000 | 3000 | TCP | WebUI |
| **cerberus-api** | 5000 | 5000 | TCP | REST API |
| **cerberus-xdp** | 8080 | 8080 | TCP | Health/Admin |
| **cerberus-filter** | 8888 | 8888 | TCP | Filtering proxy |
| **cerberus-ssl-inspector** | 8889 | 8889 | TCP | SSL inspection |
| **marchproxy-nlb** | 7000 | 7000 | TCP | L3/L4 LB |
| **marchproxy-alb** | 80, 443 | 80, 443 | TCP | L7 LB |
| **cerberus-vpn-wireguard** | 51820 | 51820 | UDP | WireGuard |
| **cerberus-vpn-ipsec** | 500, 4500 | 500, 4500 | UDP | IPSec |
| **cerberus-vpn-openvpn** | 1194 | 1194 | UDP | OpenVPN |
| **postgres** | 5432 | 5432 | TCP | Database |
| **redis** | 6379 | 6379 | TCP | Cache |
| **opensearch** | 9200 | 9200 | TCP/HTTPS | Logs/Search |
| **prometheus** | 9090 | 9090 | TCP | Metrics |
| **grafana** | 3000 | 3001 | TCP | Dashboards |
| **jaeger** | 16686 | 16686 | TCP | Tracing UI |
| **minio** | 9000 | 9000 | TCP | S3 API (NSM) |
| **minio-console** | 9001 | 9001 | TCP | S3 Web (NSM) |
| **arkime** | 8005 | 8005 | TCP | PCAP search (NSM) |

## Data Persistence

### Volumes

```bash
# Infrastructure
postgres_data                   # PostgreSQL database
redis_data                      # Redis cache
opensearch_data                 # OpenSearch indices

# Monitoring
prometheus_data                 # Prometheus time-series
grafana_data                    # Grafana dashboards
nginx_logs                      # Nginx access/error logs

# Security
suricata_rules                  # IPS rule definitions
suricata_logs                   # IPS event logs
suricata_ids_logs               # IDS analysis logs
ssl_certs                       # SSL certificates
wireguard_config                # WireGuard config
ipsec_config                    # IPSec config
openvpn_config                  # OpenVPN config

# NSM (when using --profile nsm)
minio_data                      # S3 PCAP storage
arkime_config                   # Arkime configuration
zeek_logs                       # Zeek analysis logs

# Other
rtmp_streams                    # RTMP transcoding output
pcap_s3_mount                   # PCAP S3 mount point
```

### Backup Strategy

```bash
# Backup database
docker compose exec postgres pg_dump -U cerberus cerberus > backup.sql

# Backup volumes
docker run --rm -v cerberus_postgres_data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/postgres.tar.gz -C /data .

# Backup configuration
tar czf cerberus-config-backup.tar.gz .env infrastructure/
```

## Resource Limits

### Recommended Resources

| Profile | CPU | RAM | Disk | Notes |
|---------|-----|-----|------|-------|
| **Default** | 4 cores | 8 GB | 10 GB | Basic NGFW |
| **NSM** | 8 cores | 16 GB | 100+ GB | Add packet capture |
| **Full** | 16 cores | 32 GB | 200+ GB | All services |
| **Production** | 16+ cores | 64 GB | 500+ GB | Enterprise scale |

### CPU Shares (Priority)

```yaml
Services with higher CPU shares get more CPU time:

cerberus-ips:         4096 (highest priority)
cerberus-xdp:         default (normal)
marchproxy-nlb:       default (normal)
arkime:               2048 (medium-high)
zeek:                 512 (low)
cerberus-ids:         512 (low)
```

### Memory Limits

Add to docker-compose for resource constraints:

```yaml
services:
  cerberus-api:
    mem_limit: 2g
    memswap_limit: 2g
  cerberus-xdp:
    mem_limit: 4g
    memswap_limit: 4g
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs
docker compose logs cerberus-api

# Rebuild image
docker compose build --no-cache cerberus-api

# Restart service
docker compose restart cerberus-api
```

### Database Connection Errors

```bash
# Verify PostgreSQL is accessible
docker compose exec postgres psql -U cerberus -d cerberus -c "SELECT 1"

# Check Redis
docker compose exec redis redis-cli ping

# View database logs
docker compose logs postgres
```

### High Memory Usage

```bash
# Monitor resource usage
docker stats

# Reduce pool sizes
XDP_MEMORY_POOL_SLOTS=512
MEMORY_POOL_SLOT_SIZE=1024

# Remove optional services
docker compose --profile full down
docker compose up -d  # Default profile only
```

### Network Issues

```bash
# Check network connectivity
docker network ls
docker network inspect cerberus-network

# Test DNS within container
docker compose exec cerberus-api nslookup postgres

# Test port accessibility
docker compose exec cerberus-api nc -zv postgres 5432
```

### XDP Not Accelerating

```bash
# Verify XDP mode
docker compose exec cerberus-xdp ip link show dev eth0 | grep xdp

# Check for 'native' mode support
docker compose exec cerberus-xdp ethtool -L eth0

# Change to native mode if supported
XDP_MODE=native
docker compose up -d --build cerberus-xdp
```

---

**Version**: v0.1.0 | **Last Updated**: 2025-12-27 | **Status**: Production Ready
