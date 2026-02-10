# Cerberus NGFW - Development Guide

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Python | 3.13+ | Flask backend |
| Go | 1.24+ | XDP backend |
| Node.js | 22+ | WebUI |
| Docker | 24+ | Container runtime |
| Docker Compose | 2.20+ | Service orchestration |

## Quick Start

```bash
# Clone and setup
git clone <repository-url>
cd cerberus
make setup

# Start infrastructure (PostgreSQL, Redis)
make dev-db

# Start all services in development mode
make dev
```

## Environment Configuration

Copy environment variables from `docker-compose.yml` service definitions. Key variables:

### Flask Backend (port 5000)

```env
FLASK_DEBUG=true
SECRET_KEY=dev-secret-key-change-in-production
JWT_SECRET_KEY=<same-as-SECRET_KEY>
DB_TYPE=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=cerberus_db
DB_USER=cerberus
DB_PASS=cerberus_pass
DEFAULT_ADMIN_EMAIL=admin@example.com
DEFAULT_ADMIN_PASSWORD=changeme123
LICENSE_SERVER_URL=https://license.penguintech.io
LICENSE_KEY=<optional>
```

### Go Backend (port 8080)

```env
GO_ENV=development
HOST=0.0.0.0
PORT=8080
NUMA_ENABLED=false
XDP_ENABLED=false
XDP_MODE=skb
MEMORY_POOL_SLOTS=1024
MEMORY_POOL_SLOT_SIZE=2048
```

### WebUI (port 3000)

```env
NODE_ENV=development
FLASK_API_URL=http://localhost:5000
GO_API_URL=http://localhost:8080
VITE_API_URL=/api/v1
VITE_VERSION=1.0.0
VITE_BUILD_TIME=0
```

## Service Startup Order

1. **PostgreSQL** and **Redis** (infrastructure)
2. **Flask Backend** (needs PostgreSQL for migrations/auth)
3. **Go Backend** (independent, but Flask provides config)
4. **WebUI** (proxies to Flask and Go)

## Development Workflow

### Individual Services

```bash
# Flask backend with hot reload
cd services/flask-backend && python run.py

# Go backend
cd services/go-backend && go run ./cmd/server

# WebUI with Vite HMR
cd services/webui && npm run dev
```

### Docker Compose Development

```bash
# Full stack with development overrides
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

# Just core services (API + WebUI + DB)
docker-compose up postgres redis cerberus-api cerberus-webui
```

## Mock Data Seeding

```bash
# Seed 3-4 items per NGFW feature
make seed-mock-data

# Or run directly
python scripts/seed-mock-data.py
```

This creates:
- 3 firewall rules (allow HTTP, allow DNS, deny all)
- 3 IPS categories (network scan, brute force, web attack)
- 3 VPN configs (site-to-site, remote access, mesh)
- 3 content filter rules (block malware, allow business, block social)

## Common Tasks

### Adding a New API Endpoint

1. Create route in `services/flask-backend/app/<module>.py`
2. Register blueprint in `services/flask-backend/app/__init__.py`
3. Add API test in `tests/api/test_<module>.py`
4. Update WebUI page to consume the endpoint

### Adding a New NGFW Feature Page

1. Create page component in `services/webui/src/client/pages/<Feature>.tsx`
2. Add route in `services/webui/src/client/App.tsx`
3. Add sidebar entry in `services/webui/src/client/components/Sidebar.tsx`

### Database Migrations

PyDAL handles migrations automatically. Add new table definitions to `services/flask-backend/app/models.py`.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Port 5432 in use | `docker-compose down` or check for local PostgreSQL |
| Flask can't connect to DB | Ensure PostgreSQL is running: `make dev-db` |
| WebUI proxy errors | Ensure Flask/Go backends are running first |
| XDP permission denied | Run Go backend with `--cap-add=NET_ADMIN` |
| npm install fails for @penguintechinc | Configure GitHub Packages auth in `.npmrc` |
