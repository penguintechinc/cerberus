# Cerberus VPN - OpenVPN Server
# Legacy VPN support with broad client compatibility

FROM debian:bookworm-slim

LABEL maintainer="Penguin Tech Inc"
LABEL description="Cerberus OpenVPN Server"

# Install OpenVPN and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openvpn \
    easy-rsa \
    iptables \
    iproute2 \
    procps \
    curl \
    jq \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /etc/openvpn/server \
    /etc/openvpn/ccd \
    /data/openvpn/pki \
    /data/openvpn/clients

# Copy scripts
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Copy default configs
COPY config/ /etc/openvpn/

# Environment variables
ENV VPN_PROTO=udp
ENV VPN_PORT=1194
ENV VPN_SUBNET=10.150.0.0
ENV VPN_NETMASK=255.255.255.0
ENV VPN_DNS=1.1.1.1,8.8.8.8
ENV VPN_DOMAIN=vpn.example.com
ENV VPN_CIPHER=AES-256-GCM
ENV VPN_AUTH=SHA256
ENV API_LISTEN_ADDR=:8080

# Expose ports
EXPOSE 1194/udp 1194/tcp
EXPOSE 8080/tcp

# Volume for persistent data
VOLUME ["/data/openvpn"]

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD pgrep openvpn > /dev/null || exit 1

# Entrypoint
ENTRYPOINT ["/scripts/entrypoint.sh"]
