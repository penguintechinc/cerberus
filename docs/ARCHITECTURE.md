# Cerberus NGFW/UTM - System Architecture

Complete system architecture overview for Cerberus, an enterprise-grade Next-Generation Firewall and Unified Threat Management platform.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [System Diagram](#system-diagram)
3. [Component Architecture](#component-architecture)
4. [Data Flow](#data-flow)
5. [Technology Stack](#technology-stack)
6. [Design Patterns](#design-patterns)
7. [Scalability](#scalability)
8. [High Availability](#high-availability)
9. [Security Architecture](#security-architecture)

## Architecture Overview

Cerberus implements a **microservices-based NGFW architecture** with clear separation of concerns:

```
User/Admin Layer
       ↓
┌─────────────────────────────────────────────────────────┐
│  Control Plane (Cerberus API + WebUI)                   │
│  - Policy Management                                     │
│  - User/Role Management                                 │
│  - Configuration & Orchestration                        │
└──────────────────┬──────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────┐
│  xDS Control Plane (MarchProxy API Server)              │
│  - Service Discovery                                    │
│  - Load Balancing Configuration                        │
│  - Dynamic Routing                                      │
└──────────┬───────────────────┬──────────────────────────┘
           ↓                   ↓
    ┌──────────────┐   ┌──────────────┐
    │ L3/L4 LB     │   │ L7 LB        │
    │ (NLB)        │   │ (ALB/Envoy)  │
    │              │   │              │
    │ eBPF/eBPF    │   │ Envoy Proxy  │
    │ Rate Limit   │   │ TLS Term     │
    └──────────────┘   └──────────────┘
           ↓                   ↓
    Data Plane (Ingress/Egress traffic)
           ↓
┌─────────────────────────────────────────────────────────┐
│  Packet Processing Pipeline                             │
├─────────────────────────────────────────────────────────┤
│  1. XDP/eBPF Steering (Kernel - Ultra-high throughput)  │
│  2. IPS/IDS (Suricata - Inline/Batch)                   │
│  3. Content Filter (URL/Category filtering)             │
│  4. SSL Inspector (TLS decryption & inspection)         │
│  5. VPN (WireGuard/IPSec/OpenVPN)                       │
│  6. Egress                                              │
└─────────────────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────────────────┐
│  Observability & Storage                                │
├─────────────────────────────────────────────────────────┤
│  - Prometheus (Metrics)                                 │
│  - OpenSearch (Logs)                                    │
│  - Jaeger (Tracing)                                     │
│  - MinIO/Arkime (PCAPs - NSM profile)                   │
└─────────────────────────────────────────────────────────┘
```

## System Diagram

### High-Level Architecture (ASCII)

```
┌──────────────────────────────────────────────────────────────────────┐
│                         CERBERUS NGFW/UTM                             │
├──────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                      CONTROL PLANE                             │  │
│  │  ┌────────────────┐  ┌────────────────┐  ┌─────────────────┐  │  │
│  │  │  Cerberus API  │  │  Cerberus WebUI│  │  MarchProxy API │  │  │
│  │  │   (Flask)      │  │   (React)      │  │    (Python)     │  │  │
│  │  │                │  │                │  │                 │  │  │
│  │  │ - Policies     │  │ - Dashboard    │  │ - xDS Service   │  │  │
│  │  │ - Users/Roles  │  │ - Management   │  │   Discovery     │  │  │
│  │  │ - Config       │  │ - Monitoring   │  │ - Load Balancer │  │  │
│  │  │ - Auth         │  │                │  │   Config        │  │  │
│  │  └────────────────┘  └────────────────┘  └─────────────────┘  │  │
│  │         ↓                   ↓                      ↓            │  │
│  │  ┌───────────────────────────────────────────────────────┐    │  │
│  │  │              PostgreSQL Database                     │    │  │
│  │  │  - Policies, Users, Rules, Config, State            │    │  │
│  │  └───────────────────────────────────────────────────────┘    │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                              ↓                                        │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                      DATA PLANE                               │  │
│  │  ┌────────────────────────────────────────────────────────┐  │  │
│  │  │         MarchProxy Load Balancers                      │  │  │
│  │  │  ┌────────────────────┐  ┌────────────────────────┐   │  │  │
│  │  │  │ NLB (L3/L4)        │  │ ALB (L7)               │   │  │  │
│  │  │  │ eBPF/XDP enabled   │  │ Envoy-based            │   │  │  │
│  │  │  │ Rate limiting      │  │ TLS termination        │   │  │  │
│  │  │  │ HA Proxy           │  │ Header-based routing   │   │  │  │
│  │  │  │ ~10K rps           │  │ ~5K rps (TLS)          │   │  │  │
│  │  │  └────────────────────┘  └────────────────────────┘   │  │  │
│  │  └────────────────────────────────────────────────────────┘  │  │
│  │                              ↓                                 │  │
│  │  ┌────────────────────────────────────────────────────────┐  │  │
│  │  │          eBPF/XDP Packet Processing                   │  │  │
│  │  │  ┌──────────────────────────────────────────────┐    │  │  │
│  │  │  │ Cerberus XDP (kernel-level steering)        │    │  │  │
│  │  │  │ - Packet classification                     │    │  │  │
│  │  │  │ - Early drop / redirect                     │    │  │  │
│  │  │  │ - NUMA-aware processing                     │    │  │  │
│  │  │  │ - ~40Gbps+ line rate target                 │    │  │  │
│  │  │  └──────────────────────────────────────────────┘    │  │  │
│  │  └────────────────────────────────────────────────────────┘  │  │
│  │                              ↓                                 │  │
│  │  ┌────────────────────────────────────────────────────────┐  │  │
│  │  │         Security Processing Pipeline                  │  │  │
│  │  │  ┌────────────┐  ┌────────────┐  ┌──────────────┐   │  │  │
│  │  │  │   Suricata │  │  Content   │  │  SSL Inspector│  │  │  │
│  │  │  │   IPS/IDS  │  │  Filter    │  │              │  │  │  │
│  │  │  │            │  │            │  │ - TLS Decrypt│  │  │  │
│  │  │  │ - Real-time│  │ - URL cat  │  │ - Inspect    │  │  │  │
│  │  │  │   threat   │  │ - Pattern  │  │ - Cert valid │  │  │  │
│  │  │  │   prevent  │  │ - DLP      │  │              │  │  │  │
│  │  │  └────────────┘  └────────────┘  └──────────────┘   │  │  │
│  │  └────────────────────────────────────────────────────────┘  │  │
│  │                              ↓                                 │  │
│  │  ┌────────────────────────────────────────────────────────┐  │  │
│  │  │            VPN Services                               │  │  │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌──────────────┐   │  │  │
│  │  │  │ WireGuard   │ │ IPSec       │ │ OpenVPN      │   │  │  │
│  │  │  │             │ │             │ │              │   │  │  │
│  │  │  │ Modern/Fast │ │ Enterprise  │ │ Flexible     │   │  │  │
│  │  │  │ UDP 51820   │ │ 500/4500    │ │ UDP 1194     │   │  │  │
│  │  │  └─────────────┘ └─────────────┘ └──────────────┘   │  │  │
│  │  └────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                              ↓                                        │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                  OBSERVABILITY STACK                           │  │
│  │  ┌────────────────┐  ┌──────────────┐  ┌─────────────────┐   │  │
│  │  │  Prometheus    │  │  OpenSearch  │  │  Jaeger Tracing │   │  │
│  │  │  (Metrics)     │  │  (Logs)      │  │  (Distributed)  │   │  │
│  │  │                │  │              │  │                 │   │  │
│  │  │ - CPU/Memory   │  │ - Ingestion  │  │ - Spans         │   │  │
│  │  │ - Network      │  │ - Full-text  │  │ - Latency       │   │  │
│  │  │ - Throughput   │  │ - Analytics  │  │ - Dependencies  │   │  │
│  │  └────────────────┘  └──────────────┘  └─────────────────┘   │  │
│  │         ↓                   ↓                    ↓             │  │
│  │  ┌────────────────────────────────────────────────────────┐  │  │
│  │  │  Grafana (Dashboard)  /  Fluent-Bit (Log Shipping)    │  │  │
│  │  └────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │        Optional: Network Security Monitoring (NSM Profile)    │  │
│  │  ┌────────────────┐  ┌──────────────┐  ┌─────────────────┐   │  │
│  │  │  MinIO (S3)    │  │  Arkime      │  │  Zeek           │   │  │
│  │  │                │  │  (PCAP)      │  │  (Analysis)     │   │  │
│  │  │ - PCAP storage │  │              │  │                 │   │  │
│  │  │ - S3-compat    │  │ - Real-time  │  │ - IDS Analysis  │   │  │
│  │  │                │  │ - Capture    │  │ - Batch mode    │   │  │
│  │  └────────────────┘  └──────────────┘  └─────────────────┘   │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                        │
└──────────────────────────────────────────────────────────────────────┘
```

## Component Architecture

### Tier 1: Control Plane

**Purpose**: Policy management, orchestration, user interface

#### Cerberus API (Flask + PyDAL)

- **Technology**: Python 3.13, Flask, Flask-Security-Too, PyDAL
- **Port**: 5000 (internal), 5000 (exposed)
- **Key Responsibilities**:
  - REST API for policy and configuration management
  - User authentication and authorization (JWT + MFA)
  - Role-based access control (RBAC)
  - Database abstraction via PyDAL (multi-DB support)
  - Health checks and metrics (Prometheus)
  - Event logging to OpenSearch

**Key Endpoints**:
```
GET    /healthz                     - Health check
POST   /api/v1/auth/login          - User authentication
POST   /api/v1/users               - User management
GET    /api/v1/policies            - List policies
POST   /api/v1/policies            - Create policy
PUT    /api/v1/policies/{id}       - Update policy
DELETE /api/v1/policies/{id}       - Delete policy
GET    /api/v1/rules               - IPS/filter rules
POST   /api/v1/vpn/wireguard       - Manage WireGuard
GET    /metrics                     - Prometheus metrics
```

**Data Model**:
- Users & Roles (RBAC)
- Firewall policies & rules
- VPN configurations
- System settings & licenses
- Audit logs

#### Cerberus WebUI (React + Node.js)

- **Technology**: React, TypeScript, Node.js 18+
- **Port**: 3000
- **Key Features**:
  - Dashboard with real-time metrics
  - Policy creation and management UI
  - User and role management
  - Network topology visualization
  - Threat alerts and event logs
  - Configuration import/export
  - System health monitoring

**Sections**:
```
Dashboard
  - Traffic overview
  - Top threats
  - System health

Policies
  - Firewall rules
  - NAT rules
  - QoS policies

Security
  - IPS/IDS alerts
  - Blocked content
  - SSL certificate management

VPN
  - User VPN clients
  - Site-to-site tunnels
  - Connection status

Users & Roles
  - User accounts
  - Role definitions
  - API keys
  - Audit trail

Monitor
  - Live traffic
  - System resources
  - Network performance
  - Log search (OpenSearch)
```

#### MarchProxy API Server (Python)

- **Technology**: Python, FastAPI, asyncpg, Redis
- **Ports**: 8000 (REST), 18000 (xDS gRPC)
- **Key Responsibilities**:
  - xDS control plane for load balancers
  - Service discovery and routing configuration
  - Dynamic cluster configuration
  - Health checks for upstream services
  - License validation
  - Metrics collection

**Protocol**: gRPC xDS v3 (Envoy Data Plane API)

### Tier 2: Load Balancing & Entry Point

#### MarchProxy NLB (L3/L4 Network Load Balancer)

- **Technology**: Go with eBPF/XDP acceleration
- **Port**: 7000 (data), 7001 (admin)
- **Performance Target**: 10K+ requests/second
- **Key Features**:
  - Layer 3/4 load balancing (TCP/UDP)
  - eBPF acceleration (when available)
  - Connection tracking and state management
  - Rate limiting and DDoS mitigation
  - Active/passive health checks
  - Support for any protocol

**Load Balancing Algorithms**:
- Round robin
- Least connections
- IP hash
- Random
- Custom (via xDS)

#### MarchProxy ALB (L7 Application Load Balancer)

- **Technology**: Envoy Proxy, C++
- **Ports**: 80 (HTTP), 443 (HTTPS), 8443, 9901 (admin)
- **Performance Target**: 5K+ requests/second with TLS
- **Key Features**:
  - HTTP/1.1, HTTP/2, HTTP/3 support
  - TLS/SSL termination with 1.2/1.3
  - Header-based routing
  - Path-based routing
  - Virtual host routing
  - Request/response filtering
  - Traffic shaping and rate limiting
  - Load balancing algorithms
  - Circuit breaking and retries
  - Distributed tracing (Jaeger)

**Routing Rules**:
```
HTTP/HTTPS → Envoy ALB
  ├─ Path /api → Backend API
  ├─ Path /stream → RTMP/HLS backend
  ├─ Host admin.* → Admin dashboard
  └─ Default → Application backend
```

### Tier 3: Data Plane (Packet Processing)

#### Cerberus XDP (eBPF/XDP Packet Steering)

- **Technology**: Go with LLVM eBPF programs, Linux kernel
- **Port**: 8080 (admin/health)
- **Performance Target**: 40Gbps+ line rate
- **Privileges**: `privileged=true`, CAP_BPF, CAP_NET_ADMIN, IPC_LOCK
- **Key Features**:
  - Kernel-space packet processing with eBPF
  - XDP driver (native/skb modes)
  - AF_XDP for zero-copy user-space access
  - NUMA-aware memory pools
  - Packet classification and early drop
  - DDoS mitigation at kernel level
  - Traffic steering to userspace services
  - Performance monitoring (drop rate, throughput)

**Packet Processing Flow**:
```
Ingress ─→ XDP Programs (Kernel)
           ├─ Classify packet
           ├─ Check rate limits
           ├─ Perform early drop (DDoS)
           └─ Steer to service or drop
           ↓
        Services (Userspace)
           ├─ IPS/IDS (Suricata)
           ├─ Content Filter
           ├─ SSL Inspector
           └─ VPN
           ↓
Egress  ←─ Response
```

#### Suricata IPS/IDS (Intrusion Prevention/Detection)

- **Technology**: Suricata (C)
- **Modes**:
  - IPS: Real-time inline (default in docker-compose)
  - IDS: Batch analysis of S3 PCAPs (NSM profile)
- **Port**: 9100 (Prometheus metrics)
- **Key Features**:
  - Real-time threat detection and prevention
  - Signature-based detection (Suricata rules)
  - Protocol analysis (HTTP, DNS, TLS, etc.)
  - File extraction and analysis
  - Malware detection (via rules)
  - Full packet logging

**Rules Sources**:
```
ET Open        - Emerging Threats free rules
ET Pro         - Paid threat intelligence
Suricata IDS   - Official rules
Custom         - Organization-specific rules
```

**Threat Prevention**:
```
DROP       → Block traffic completely
REJECT     → Send RST/ICMP
ALERT      → Log and allow
PASS       → Bypass rules
CONTENT    → Inspect packet payload
FLOW       → Analyze connection flow
```

#### Content Filter (Proxy)

- **Technology**: Go
- **Port**: 8888 (filtering proxy)
- **Metrics Port**: 9101
- **Key Features**:
  - URL categorization (adult, malware, etc.)
  - DNS filtering
  - Keyword filtering
  - File type blocking
  - Regex pattern matching
  - User-based filtering
  - Time-based policies

**Categories Blocked**:
```
- Adult content
- Malware distribution
- Phishing sites
- Command & control
- Gambling
- Social media (optional)
- Video streaming (optional)
- File sharing (optional)
```

#### SSL Inspector

- **Technology**: Go
- **Port**: 8889
- **Certificate Management**: Auto-generated CA
- **Key Features**:
  - SSL/TLS decryption and inspection
  - Man-in-the-middle (transparent proxy)
  - Certificate validation
  - Encrypted threat detection
  - Certificate pinning detection
  - Perfect forward secrecy analysis

**Workflow**:
```
Client → Cerberus (intercept CONNECT)
  ↓
Cerberus (SSL Inspector)
  ├─ Generate fake cert (signed by Cerberus CA)
  ├─ Decrypt TLS stream
  ├─ Inspect payload (pass to IPS/Filter)
  └─ Re-encrypt to server
  ↓
Backend Server
```

### Tier 4: VPN Services

All VPN services run with `privileged=true` and `NET_ADMIN` capabilities.

#### WireGuard VPN

- **Technology**: WireGuard (kernel module)
- **Port**: 51820 UDP (configurable)
- **Key Features**:
  - Modern VPN protocol (post-quantum ready)
  - Ultra-high performance
  - 4KB kernel implementation
  - Stateless protocol
  - Perfect forward secrecy
  - IPV4 and IPV6 support

**Use Case**: Modern clients, highest performance requirement

#### IPSec VPN (StrongSwan)

- **Technology**: StrongSwan
- **Ports**: 500 (IKE), 4500 (NAT-T) UDP
- **Key Features**:
  - Industry-standard VPN protocol
  - Enterprise compatibility
  - IPV4/IPV6 support
  - Multiple encryption standards
  - Perfect forward secrecy
  - NAT traversal

**Use Case**: Enterprise environments, site-to-site connections

#### OpenVPN

- **Technology**: OpenVPN
- **Port**: 1194 UDP (configurable)
- **Key Features**:
  - Wide client support (Windows, Mac, Linux, iOS, Android)
  - TLS-based encryption
  - Flexible routing and tunneling
  - User authentication
  - Multiple cipher support

**Use Case**: Legacy systems, maximum client compatibility

### Tier 5: Observability & Analytics

#### Prometheus (Metrics)

- **Image**: `prom/prometheus:latest`
- **Port**: 9090
- **Retention**: 200 hours (default)
- **Purpose**: Time-series metrics collection

**Metrics from Services**:
```
cerberus-api:9105         - API metrics (requests, auth, DB)
cerberus-xdp:9106         - XDP/eBPF metrics (packets, drops)
cerberus-ips:9100         - Suricata metrics (alerts, drops)
cerberus-filter:9101      - Filter metrics (blocks, categories)
cerberus-vpn-*:9102-9104  - VPN metrics (connections, throughput)
marchproxy-*:9000+        - MarchProxy metrics
```

**Key Metrics**:
```
Network:
  - Packets/sec
  - Bytes/sec
  - Dropped packets
  - Active connections

Application:
  - HTTP requests/sec
  - API latency
  - Authentication rate
  - Database queries/sec

Security:
  - IPS alerts/sec
  - Blocked URLs
  - DDoS drops
  - VPN connections
```

#### OpenSearch (Logging)

- **Image**: `opensearchproject/opensearch:2.11.0`
- **Port**: 9200 (HTTPS)
- **Purpose**: Centralized logging and full-text search
- **Data**: Syslog, application logs, audit trails

**Log Types**:
```
- Application logs (all services)
- Suricata IPS alerts
- Content filter blocks
- VPN connection events
- API audit trail
- Authentication attempts
- System events
```

**Indices**:
```
logs-cerberus-{service}-YYYY.MM.DD
logs-suricata-YYYY.MM.DD
logs-vpn-YYYY.MM.DD
logs-audit-YYYY.MM.DD
```

#### Jaeger (Distributed Tracing)

- **Image**: `jaegertracing/all-in-one:latest`
- **Port**: 16686 (UI), 6831 (agent), 14268 (collector)
- **Purpose**: Distributed tracing across services

**Trace Examples**:
```
API Request:
  cerberus-api (100ms)
  └─ PostgreSQL query (20ms)
  └─ Redis lookup (2ms)
  └─ OpenSearch log (10ms)
  └─ MarchProxy gRPC (60ms)

Packet Processing:
  Ingress XDP (0.1ms)
  └─ IPS rule check (2ms)
  └─ Filter lookup (0.5ms)
  └─ SSL inspection (5ms)
```

#### Grafana (Visualization)

- **Image**: `grafana/grafana:latest`
- **Port**: 3001
- **Default Admin**: admin/admin
- **Purpose**: Metrics dashboards and alerting

**Default Dashboards**:
```
- System Overview (CPU, Memory, Network)
- Cerberus NGFW (Throughput, Threats, VPN)
- MarchProxy (Load balancing, rates)
- Application Performance (API latency, errors)
- Security Alerts (IPS, Filter, VPN)
```

### Tier 6: Optional Services

#### NSM Profile - Network Security Monitoring

**MinIO (S3-Compatible Storage)**
- Purpose: PCAP storage
- Protocol: S3 API (port 9000)
- Dashboard: Port 9001

**Arkime (PCAP Capture)**
- Purpose: Real-time PCAP capture
- Protocol: HTTP (port 8005)
- Storage: MinIO S3 buckets
- Mode: Real-time streaming

**Zeek IDS (Analysis)**
- Purpose: Network traffic analysis
- Mode: Batch processing (low CPU priority)
- Input: S3 PCAPs from MinIO
- Output: Logs to OpenSearch

#### Full Profile - Advanced Load Balancing

**MarchProxy DBLB** (Database Load Balancer)
- Purpose: Database failover and load distribution
- Ports: 3306 (MySQL), 5433 (PostgreSQL), 27017 (MongoDB)

**MarchProxy AILB** (AI/LLM Load Balancer)
- Purpose: LLM inference scaling
- Port: 7003
- Backends: OpenAI, Anthropic, local models

**MarchProxy RTMP** (Video Transcoding)
- Purpose: RTMP/HLS streaming
- Port: 1935 (RTMP)
- Technology: FFmpeg

#### Production Profile

**Nginx Reverse Proxy**
- Purpose: TLS termination, reverse proxy
- Ports: 8080 (HTTP), 8443 (HTTPS)
- Config: `infrastructure/docker/nginx/`

## Data Flow

### Inbound Traffic Flow

```
External Client
    ↓
Internet Gateway
    ↓
MarchProxy ALB (Envoy)
├─ TLS termination (443)
├─ Host/Path routing
├─ Rate limiting
└─ Load balance to backends
    ↓
Application Services
├─ Cerberus WebUI (3000)
├─ Cerberus API (5000)
└─ Backend applications
    ↓
Cerberus XDP (Kernel)
├─ Early packet classification
├─ DDoS detection
└─ Traffic steering
    ↓
Security Pipeline
├─ Suricata IPS (real-time threat)
├─ Content Filter (URL/category)
└─ SSL Inspector (TLS inspection)
    ↓
Upstream Server
```

### Outbound Traffic Flow

```
User/Client System
    ↓
VPN (optional)
├─ WireGuard (51820)
├─ IPSec (500/4500)
└─ OpenVPN (1194)
    ↓
Cerberus XDP
├─ Packet steering
├─ DDoS filters
└─ Rate limiting
    ↓
Security Services
├─ IPS/IDS (threat detection)
├─ Content Filter (URL blocking)
└─ SSL Inspector (encrypted threat detection)
    ↓
MarchProxy NLB
├─ L3/L4 load balancing
├─ Connection tracking
└─ Health checks
    ↓
External Services
└─ Internet
```

### Control Path Data Flow

```
Admin/User → WebUI (3000)
    ↓
Cerberus API (5000)
├─ Authentication (JWT)
├─ Authorization (RBAC)
└─ Policy validation
    ↓
PostgreSQL Database
├─ Store policies
├─ Store configuration
└─ Store user data
    ↓
MarchProxy API Server (18000 xDS)
├─ Convert policy to xDS config
├─ Push to load balancers
└─ Push to VPN services
    ↓
Data Plane Services
└─ Apply configuration
```

## Technology Stack

### Core Technologies

| Layer | Technology | Language | Purpose |
|-------|-----------|----------|---------|
| **Control Plane** | Flask | Python 3.13 | REST API, policy mgmt |
| **Control Plane** | React | TypeScript | Dashboard, UI |
| **xDS Control** | FastAPI | Python | Service discovery |
| **L7 Load Balancer** | Envoy Proxy | C++ | Application LB |
| **L3/L4 Load Balancer** | Custom Go | Go | Network LB |
| **Packet Processing** | eBPF/XDP | C + Go | Kernel acceleration |
| **IPS/IDS** | Suricata | C | Threat detection |
| **Content Filter** | Custom | Go | URL filtering |
| **VPN - Modern** | WireGuard | C | Modern VPN |
| **VPN - Enterprise** | StrongSwan | C | IPSec VPN |
| **VPN - Compat** | OpenVPN | C | Legacy VPN |
| **Metrics** | Prometheus | Go | Time-series DB |
| **Logging** | OpenSearch | Java | Search/analytics |
| **Tracing** | Jaeger | Go | Distributed traces |
| **PCAP Capture** | Arkime | Node.js | Real-time capture |
| **Network Analysis** | Zeek | C++ | IDS analysis |

### Database & Cache

- **PostgreSQL 16**: Primary relational database (policies, users, configs)
- **Redis 7**: Caching, sessions, rate limiting, distributed locks
- **OpenSearch 2.11**: Full-text logging and analytics
- **MinIO**: S3-compatible object storage (PCAPs)

### Networking

- **Kernel Module**: WireGuard (VPN)
- **IPSec Stack**: StrongSwan (VPN)
- **Routing**: Linux kernel `ip route`
- **Filtering**: Linux netfilter + eBPF
- **DNS**: Unbound (recursive resolver)

## Design Patterns

### 1. Control Plane / Data Plane Separation

**Benefit**: Independent scaling, different SLAs, security isolation

```
Control Plane (Low throughput, high reliability)
└─ API, Configuration, User Interface

Data Plane (High throughput, deterministic latency)
└─ Packet processing, Network LB, VPN
```

### 2. xDS-based Dynamic Configuration

**Benefit**: Real-time policy updates without service restart

```
Cerberus API (policy)
    ↓
MarchProxy API Server (xDS translator)
    ↓
Load Balancers (xDS client)
    ↓
Dynamic reconfiguration
```

### 3. Pluggable Security Services

**Benefit**: Mix and match services, independent lifecycle

```
Packet → XDP → IPS → Filter → SSL → VPN → Egress
         ↑     ↑     ↑       ↑     ↑
    Each service can be:
    - Updated independently
    - Scaled separately
    - Configured dynamically
    - Replaced with alternatives
```

### 4. Observability First

**Benefit**: Deep visibility into traffic and threats

```
Every service → Prometheus (metrics)
Every service → OpenSearch (logs)
Every service → Jaeger (traces)
        ↓
Grafana (unified dashboard)
OpenSearch Dashboards (log search)
```

### 5. Microservices with Async Communication

**Benefit**: Loose coupling, fault tolerance

```
Service A → Event Bus (Redis) → Service B
Service C → Event Bus (Redis) → Service D
```

## Scalability

### Horizontal Scaling

| Component | Scaling Method | Limit | Notes |
|-----------|----------------|-------|-------|
| **Cerberus API** | Docker replicas | ~100 instances | Stateless, load balanced |
| **WebUI** | CDN + replicas | Unlimited | Static assets, no state |
| **MarchProxy NLB** | Docker replicas | 10-50 | eBPF limits per host |
| **MarchProxy ALB** | Envoy auto-scaling | 100+ | Stateless proxy |
| **IPS (Suricata)** | Affinity groups | 1 per core recommended | CPU-bound, per-core rules |
| **Content Filter** | Docker replicas | 10-20 | Cache locality important |
| **PostgreSQL** | Read replicas | 1 primary + 4 read | Read-mostly workload |
| **Redis** | Cluster/Sentinel | 10-100 nodes | Cache tier, fast failover |
| **OpenSearch** | Cluster | 3-100+ nodes | Log tier, data growth |

### Vertical Scaling

```
Small Deployment (1 host):
- 4 CPU, 8 GB RAM
- Default profile only
- ~1 Gbps throughput

Medium Deployment (3 hosts):
- 8 CPU, 16 GB RAM each
- Default + NSM profiles
- ~10 Gbps throughput

Large Deployment (10+ hosts):
- 16+ CPU, 32 GB RAM each
- Full profile with clustering
- 40+ Gbps throughput
```

### Performance Tuning

1. **XDP Native Mode**: Hardware acceleration on supported NICs (10Gbps+)
2. **NUMA Awareness**: Pin processes to NUMA nodes
3. **Kernel Bypass**: AF_XDP for zero-copy packet access
4. **Connection Pooling**: Reuse database/Redis connections
5. **Caching Strategy**: Redis for IPS rules, filter categories
6. **Batch Processing**: Arkime/Zeek for historical analysis

## High Availability

### Failover Strategy

#### Active-Active (Preferred)
```
Load Balancer (DNS round-robin)
├─ Cerberus Instance 1 (API + XDP)
├─ Cerberus Instance 2 (API + XDP)
└─ Cerberus Instance 3 (API + XDP)

All instances:
- Share PostgreSQL (replication)
- Share Redis (cluster)
- Share OpenSearch (cluster)
- Independent XDP processing (distributed)
```

#### Active-Passive (Simpler)
```
Primary (Active)
├─ Cerberus API + XDP + Services
└─ Replicates state to Secondary

Secondary (Standby)
├─ Receives replication
└─ Promotes to primary on failure

Keepalived/VRRP handles VIP failover
```

### Database High Availability

**PostgreSQL Replication**:
```
Primary → Synchronous Streaming Replication → Standby
                           ↓
                    Read Replicas (3)
```

**Redis High Availability**:
```
Redis Cluster (6 nodes)
├─ 3 primary shards
└─ 3 replica shards
```

### Service Health & Recovery

**Liveness Probes**: Restart unhealthy services
**Readiness Probes**: Wait for dependencies before serving traffic
**Startup Probes**: Allow extended startup time for heavy services

```
Docker Health Checks:
- API: GET /healthz (30s interval, 3 retries)
- XDP: GET /healthz (30s interval, 3 retries)
- PostgreSQL: pg_isready (10s interval, 5 retries)
- Redis: redis-cli ping (10s interval, 5 retries)
```

## Security Architecture

### Network Segmentation

```
Internet
  ↓ (encrypted TLS)
┌─────────────────────┐
│ MarchProxy ALB      │ ← TLS Termination, DDoS Protection
└──────────┬──────────┘
           ↓
Cerberus Network (172.30.0.0/16)
  ├─ Public Services (API, WebUI)
  ├─ Private Services (Database, Cache)
  ├─ Security Pipeline
  └─ Monitoring Services
```

### Authentication & Authorization

**Multi-layer Authentication**:

1. **API Authentication**:
   - JWT tokens (Bearer token)
   - Token expiration: Configurable
   - Refresh token rotation

2. **User Management**:
   - Password hashing: bcrypt
   - 2FA: TOTP support
   - Session management: Distributed (Redis)

3. **Role-Based Access Control (RBAC)**:
   - Admin: Full access
   - Maintainer: Configuration management
   - Viewer: Read-only access
   - Custom roles with granular permissions

**Certificate-Based Auth**:
- mTLS for service-to-service communication
- Client certificates for VPN

### Threat Detection & Prevention

**Multi-layer Defense**:

1. **Network Layer**: DDoS detection (XDP)
2. **Transport Layer**: Connection tracking, rate limiting (NLB)
3. **Application Layer**: HTTP parsing, anomaly detection (ALB)
4. **Content Layer**: URL filtering, keyword matching (Filter)
5. **Encryption Layer**: TLS inspection (SSL Inspector)
6. **Behavioral Layer**: IDS signatures, pattern matching (Suricata)

### Audit & Compliance

**Audit Trail**:
- All API calls logged with user, action, timestamp
- Policy change history with versioning
- VPN connection logs with user, time, duration
- Threat alerts with full packet context

**Compliance Ready**:
- PCI-DSS: TLS 1.2+, authentication, audit logs
- HIPAA: Encryption, role-based access, audit trail
- SOC2: Monitoring, alerting, incident response
- ISO27001: Information security, access control

---

**Version**: v0.1.0 | **Last Updated**: 2025-12-27 | **Status**: Enterprise Grade
