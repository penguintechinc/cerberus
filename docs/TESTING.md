# Cerberus NGFW - Testing Guide

## Test Structure

```
tests/
├── smoke/           # Build and health verification (<2 min)
├── api/             # Flask API endpoint tests
├── unit/
│   ├── flask/       # Python unit tests
│   └── go/          # Go unit tests
├── integration/     # Cross-service tests
└── e2e/             # Browser-based end-to-end tests
```

## Running Tests

```bash
# All tests
make test

# By category
make smoke-test        # Smoke tests (build, health, basic API)
make test-python       # Flask unit + API tests
make test-go           # Go unit tests
make test-node         # WebUI tests
make test-integration  # Cross-service integration tests
```

## Smoke Tests

Smoke tests verify the system is fundamentally working. Run before every commit.

```bash
make smoke-test
# Or individually:
bash tests/smoke/test_build.sh    # All containers build successfully
bash tests/smoke/test_health.sh   # All /healthz endpoints respond
bash tests/smoke/test_api.sh      # Basic API CRUD operations work
```

### What Smoke Tests Verify

1. **Build**: All Docker images build without errors
2. **Health**: `/healthz` returns 200 on Flask (5000), Go (8080), WebUI (3000)
3. **API**: Login, token refresh, user CRUD all return expected status codes

## Mock Data

Seed realistic test data before running tests or taking screenshots:

```bash
make seed-mock-data
```

### Mock Data Pattern (3-4 items per feature)

| Feature | Items |
|---------|-------|
| Firewall Rules | Allow HTTP (80/443), Allow DNS (53), Deny All |
| IPS Categories | Network Scan Detection, Brute Force Prevention, Web Attack Signatures |
| VPN Configs | Site-to-Site (HQ-Branch), Remote Access (Employee), Mesh (Multi-site) |
| Content Filter | Block Malware Domains, Allow Business Apps, Block Social Media |

## API Tests

Located in `tests/api/`. Use pytest with Flask test client.

```bash
# Run API tests
pytest tests/api/ -v

# With coverage
pytest tests/api/ --cov=services/flask-backend/app --cov-report=html
```

### Key Test Files

- `tests/api/conftest.py` - Shared fixtures (test client, auth tokens, test users)
- `tests/api/test_auth.py` - Login, register, refresh, logout flows
- `tests/api/test_users.py` - User CRUD with role-based access

## Unit Tests

### Flask (Python)

```bash
pytest tests/unit/flask/ -v
```

Tests cover:
- Model operations (PyDAL CRUD)
- Configuration loading
- Password hashing/verification
- JWT token creation/validation

### Go

```bash
cd services/go-backend && go test -v -race ./...
```

Tests cover:
- Server handlers (health, status, hello)
- Memory pool allocation/release
- Packet parsing/serialization
- Configuration loading

## Integration Tests

```bash
pytest tests/integration/ -v
```

Tests verify:
- Flask API can communicate with Go backend
- WebUI proxy routes work correctly
- Database operations across services

## E2E Tests

Using Playwright for browser-based testing:

```bash
npx playwright test tests/e2e/
```

Tests cover:
- Login flow (enter credentials, redirect to dashboard)
- Navigation (sidebar links, role-based visibility)
- NGFW pages (firewall rules CRUD, IPS alerts view)

## Performance Testing

For XDP data path performance:

```bash
# Memory pool benchmarks
cd services/go-backend && go test -bench=. ./internal/memory/

# Packet processing benchmarks
cd services/go-backend && go test -bench=. ./internal/xdp/
```

## Pre-Commit Test Execution

Before every commit, run in this order:

1. `make lint` - All linters pass
2. `make smoke-test` - Build and health checks
3. `make test` - Full test suite
4. `make seed-mock-data` - Seed realistic data
5. Capture screenshots with realistic data
