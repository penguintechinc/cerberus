# Cerberus NGFW - Application Standards

## Architecture Overview

Cerberus is an enterprise Next-Generation Firewall (NGFW) platform built on a three-tier microservices architecture.

### Service Architecture

```
┌─────────────────────────────────────────────────────┐
│                    WebUI (React)                     │
│              Port 3000 - Dashboard                   │
│     Role-based access: Admin, Maintainer, Viewer     │
├────────────────────┬────────────────────────────────┤
│   Flask Backend    │         Go Backend              │
│   Port 5000        │         Port 8080               │
│   Control Plane    │         Data Plane              │
│   - Auth/Users     │         - XDP packet steering   │
│   - NGFW config    │         - AF_XDP zero-copy I/O  │
│   - Audit logging  │         - NUMA-aware pools      │
│   - License mgmt   │         - eBPF programs         │
├────────────────────┴────────────────────────────────┤
│                  Infrastructure                      │
│   PostgreSQL 16 │ Redis 7 │ OpenSearch 2.11          │
└─────────────────────────────────────────────────────┘
```

### Communication Patterns

- **WebUI -> Flask**: REST API via Express proxy (`/api/v1/*`)
- **WebUI -> Go**: REST API via Express proxy (`/api/go/*` -> `/api/v1/*`)
- **Flask -> Go**: Internal HTTP (service-to-service)
- **MarchProxy**: xDS control plane for dynamic load balancer config

### NGFW Domain Concepts

| Concept | Description | Service |
|---------|-------------|---------|
| Zones | Network segments (WAN, LAN, DMZ, VPN) | Flask + Go |
| Firewall Rules | Stateful L3/L4 rules with protocol matching | Flask (config) + Go (enforcement) |
| NAT Rules | SNAT, DNAT, masquerade translations | Flask (config) + Go (enforcement) |
| XDP Filters | High-performance packet steering rules | Go (direct XDP) |
| IPS/IDS | Intrusion detection/prevention signatures | Suricata container |
| Content Filter | URL/domain categorization and blocking | Go filter service |
| VPN | WireGuard, IPSec, OpenVPN tunnels | Dedicated containers |
| SSL Inspector | TLS interception for deep packet inspection | Dedicated container |

### Performance Requirements

- **Data Plane**: 40 Gbps+ line rate via XDP/eBPF (kernel bypass)
- **Control Plane**: Sub-100ms API response times
- **WebUI**: Sub-2s page load, real-time dashboard updates
- **Memory**: NUMA-aware allocation, zero-copy packet I/O

### License Tiers

| Tier | Features |
|------|----------|
| Community | Basic firewall, NAT, zone management |
| Professional | + IPS/IDS, content filtering, VPN |
| Enterprise | + SSL inspection, HA clustering, audit logging |
| Ultimate | + AI threat detection (WaddleAI), NSM, PCAP |

### Database Schema

All NGFW configuration is stored in PostgreSQL via PyDAL. Key tables:
- `users`, `refresh_tokens` - Authentication
- `zones`, `firewall_rules`, `nat_rules` - Network policy
- `xdp_filter_rules` - XDP packet steering
- `ips_categories`, `ips_rules`, `ips_alerts` - Intrusion prevention
- `url_categories`, `filter_policies` - Content filtering
- `vpn_servers`, `vpn_users` - VPN management
- `audit_log` - Complete audit trail

### penguin-libs Integration

| Service | Package | Purpose |
|---------|---------|---------|
| Flask | `penguin-libs[flask,http]` | SanitizedLogger, HTTP client |
| Flask | `penguin-licensing[flask]` | License validation decorators |
| Flask | `penguin-sal[k8s]` | Secrets management (Vault/K8s) |
| Go | `go-common` | SanitizedLogger (Zap-based) |
| WebUI | `@penguintechinc/react-libs` | SidebarMenu, FormModalBuilder, ConsoleVersion |

### Roles and Permissions

| Role | Dashboard | Security Config | User Management | Settings |
|------|-----------|----------------|-----------------|----------|
| Admin | Full | Full | Full | Full |
| Maintainer | Full | Read/Write | None | Read/Write |
| Viewer | Read-only | None | None | None |
