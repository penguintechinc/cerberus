# Cerberus Content Filter - Multi-stage Build
# URL categorization and content filtering service

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
    -o /build/cerberus-filter \
    ./cmd/filter

# Runtime stage
FROM debian:bookworm-slim

# Install ca-certificates for HTTPS requests
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -r -u 1000 -s /sbin/nologin cerberus

# Create data directories
RUN mkdir -p /data/blocklists/categories && \
    chown -R cerberus:cerberus /data

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/cerberus-filter /app/cerberus-filter

# Copy default blocklists if any
COPY --chown=cerberus:cerberus blocklists/ /data/blocklists/

# Environment variables
ENV LISTEN_ADDR=:8080
ENV LOG_LEVEL=info
ENV REDIS_ADDR=redis:6379
ENV BLOCKLIST_DIR=/data/blocklists
ENV DEFAULT_ACTION=allow
ENV CACHE_ENABLED=true
ENV CACHE_TTL=3600
ENV MAX_BATCH_SIZE=100

# Switch to non-root user
USER cerberus

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/healthz || exit 1

# Run the service
ENTRYPOINT ["/app/cerberus-filter"]
