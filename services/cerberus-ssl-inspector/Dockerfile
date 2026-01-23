# Cerberus SSL Inspector - Multi-stage Build
# SSL/TLS MITM Proxy for Deep Packet Inspection

# Build stage
FROM golang:1.23-bookworm AS builder

WORKDIR /build

# Copy go mod files
COPY go.mod go.sum* ./
RUN go mod download || true

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o /build/cerberus-ssl-inspector \
    ./cmd/inspector

# Runtime stage
FROM debian:bookworm-slim

# Install ca-certificates
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -r -u 1000 -s /sbin/nologin cerberus

# Create data directories
RUN mkdir -p /data/ca && \
    chown -R cerberus:cerberus /data

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/cerberus-ssl-inspector /app/cerberus-ssl-inspector

# Environment variables
ENV API_LISTEN_ADDR=:8081
ENV PROXY_LISTEN_ADDR=:8443
ENV CA_DIR=/data/ca
ENV CA_COMMON_NAME="Cerberus SSL Inspector CA"
ENV CA_ORG="Cerberus NGFW"
ENV INSPECT_HTTPS=true
ENV LOG_CONNECTIONS=true
ENV LOG_LEVEL=info

# Switch to non-root user
USER cerberus

# Expose ports
EXPOSE 8081 8443

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8081/healthz || exit 1

# Run the service
ENTRYPOINT ["/app/cerberus-ssl-inspector"]
