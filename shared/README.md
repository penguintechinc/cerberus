# Shared Libraries

## What Remains Here

These directories contain local library code that does NOT yet have a published penguin-libs equivalent:

| Directory | Purpose | Status |
|-----------|---------|--------|
| `go_libs/` | Go validation, crypto, HTTP, gRPC utilities | No published Go package yet |
| `node_libs/` | Node.js server-side utilities | No published npm package yet |
| `database/` | Database helper utilities (Go) | No published package yet |
| `licensing/` | Go licensing client and middleware | No published Go licensing client yet |

## What Was Removed (Now Published Packages)

| Removed Directory | Replaced By | Install |
|-------------------|-------------|---------|
| `py_libs/` | `penguin-libs` PyPI package | `pip install penguin-libs[flask,http]` |
| `react_libs/` | `@penguintechinc/react-libs` npm package | `npm install @penguintechinc/react-libs` |
| `licensing/python_client.py` | `penguin-licensing` PyPI package | `pip install penguin-licensing[flask]` |

## Migration Notes

- **Python services**: Import from `penguin_libs` instead of `shared.py_libs`
- **React frontends**: Import from `@penguintechinc/react-libs` instead of `@penguin/react_libs`
- **Go services**: Continue importing from `shared/go_libs` until a Go package is published
