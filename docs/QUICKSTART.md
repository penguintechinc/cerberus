# Cerberus NGFW/UTM - Quick Start Guide

Get Cerberus up and running in 5 minutes with Docker Compose.

## Prerequisites

- Docker 20.10+ and Docker Compose 2.0+
- 8GB RAM minimum (16GB+ recommended for full profile)
- Linux kernel 5.8+ (for eBPF/XDP features)
- `git` for cloning submodules

## Quick Start (Default Profile)

### 1. Clone and Prepare

```bash
cd /path/to/Cerberus
git submodule update --init --recursive
cp .env.example .env
```

### 2. Start Services

```bash
# Start default services (API, XDP, WebUI, IPS, Filter, VPN, monitoring)
docker compose up -d

# Wait for services to be healthy (~30-60 seconds)
docker compose ps
```

### 3. Access Cerberus

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| **WebUI Dashboard** | http://localhost:3000 | admin / admin123 |
| **Cerberus API** | http://localhost:5000 | - |
| **Prometheus** | http://localhost:9090 | - |
| **Grafana** | http://localhost:3001 | admin / admin |
| **Jaeger Tracing** | http://localhost:16686 | - |
| **OpenSearch** | https://localhost:9200 | admin / Cerberus@123 |

## Configuration

### Environment Variables (.env)

```bash
# Core Services
FLASK_ENV=production
SECRET_KEY=change-me-in-production
JWT_SECRET_KEY=change-me-jwt-secret
POSTGRES_PASSWORD=cerberus123
REDIS_PASSWORD=cerberus123
OPENSEARCH_PASSWORD=Cerberus@123

# Ports
CERBERUS_API_PORT=5000
CERBERUS_XDP_PORT=8080
WEBUI_PORT=3000
PROMETHEUS_PORT=9090
GRAFANA_PORT=3001

# XDP Settings
XDP_ENABLED=true
XDP_MODE=skb
XDP_INTERFACE=eth0
NUMA_ENABLED=false

# VPN Ports
WG_PORT=51820
OVPN_PORT=1194
```

## Common Commands

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f cerberus-api
docker compose logs -f cerberus-xdp
docker compose logs -f marchproxy-api-server
```

### Health Check

```bash
# Check all services
docker compose ps

# Check specific service
docker compose exec cerberus-api wget -O- http://localhost:5000/healthz
```

### Stop Services

```bash
# Stop all services
docker compose down

# Stop and remove all data
docker compose down -v
```

## Deployment Profiles

Cerberus supports multiple Docker Compose profiles for different use cases:

### Default (No Profile)
Core NGFW functionality:
- Cerberus API (Flask control plane)
- Cerberus XDP (eBPF packet processing)
- Cerberus WebUI (React dashboard)
- IPS (Suricata)
- Content Filter
- SSL Inspector
- VPN Services (WireGuard, IPSec, OpenVPN)
- Monitoring (Prometheus, Grafana, Jaeger)

### NSM Profile (Network Security Monitoring)
Add packet capture and analysis:
```bash
docker compose --profile nsm up -d
```

Services: Arkime (PCAP), Zeek (IDS analysis), MinIO (S3 storage)

### Full Profile (All Services)
Complete system with all optional modules:
```bash
docker compose --profile full up -d
```

Includes: NSM + Database Load Balancer + AI/LLM Load Balancer + RTMP Transcoding

### Dashboards Profile
Optional web-based dashboards:
```bash
docker compose --profile dashboards up -d
```

Services: OpenSearch Dashboards (log visualization)

### Production Profile
Production reverse proxy:
```bash
docker compose --profile production up -d
```

Services: Nginx with TLS/SSL

## Next Steps

1. **Configure Policies**: Visit WebUI → Settings to configure firewall rules
2. **Add Users**: WebUI → Users to create additional admin/viewer accounts
3. **Monitor Traffic**: WebUI → Dashboard or Grafana for real-time metrics
4. **Review Logs**: OpenSearch for centralized logging and analysis
5. **Customize Rules**: Update IPS/Filter rules via API or WebUI

## Troubleshooting

### Services not starting?
```bash
# Check docker daemon
docker ps

# Rebuild containers
docker compose build --no-cache

# Restart services
docker compose restart
```

### Database connection errors?
```bash
# Verify PostgreSQL is healthy
docker compose exec postgres pg_isready -U cerberus

# Check Redis
docker compose exec redis redis-cli ping
```

### High memory usage?
- Reduce `MEMORY_POOL_SLOTS` for XDP (default 1024)
- Scale down optional services (NSM, full profile)
- Monitor with: `docker stats`

## Performance Tuning

For production deployments targeting 40Gbps+:

1. **Enable XDP mode** (hardware acceleration):
   ```bash
   XDP_MODE=native
   XDP_INTERFACE=<your-nic>
   ```

2. **Enable NUMA** (multi-socket systems):
   ```bash
   NUMA_ENABLED=true
   ```

3. **Increase memory pools**:
   ```bash
   MEMORY_POOL_SLOTS=4096
   MEMORY_POOL_SLOT_SIZE=4096
   ```

4. **Monitor metrics**:
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:3001

## Documentation

- **Full Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **Docker Compose Details**: [DOCKER_COMPOSE.md](DOCKER_COMPOSE.md)
- **API Reference**: See Cerberus API docs in WebUI
- **Development**: See main [README.md](../README.md)

## Support

- **Issues**: GitHub Issues
- **Documentation**: [docs/](../docs/)
- **License**: Limited AGPL3 (see [LICENSE.md](../docs/LICENSE.md))

---

**Version**: v0.1.0 | **Last Updated**: 2025-12-27
