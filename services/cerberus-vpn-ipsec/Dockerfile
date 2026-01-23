# Cerberus VPN - IPSec/IKEv2 Server (StrongSwan)
# Enterprise VPN with IKEv2 support

FROM debian:bookworm-slim

LABEL maintainer="Penguin Tech Inc"
LABEL description="Cerberus IPSec VPN Server (StrongSwan)"

# Install StrongSwan and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    strongswan \
    strongswan-pki \
    strongswan-swanctl \
    libcharon-extra-plugins \
    libcharon-extauth-plugins \
    libstrongswan-extra-plugins \
    iptables \
    iproute2 \
    procps \
    curl \
    jq \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /etc/ipsec.d/certs \
    /etc/ipsec.d/cacerts \
    /etc/ipsec.d/private \
    /data/ipsec

# Copy scripts
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Copy default configs
COPY config/ /etc/strongswan/

# Environment variables
ENV VPN_DNS=1.1.1.1,8.8.8.8
ENV VPN_SUBNET=10.200.0.0/24
ENV VPN_DOMAIN=vpn.example.com
ENV IKE_LIFETIME=3h
ENV IPSEC_LIFETIME=1h
ENV API_LISTEN_ADDR=:8080

# Expose ports
# IKE (UDP 500), NAT-T (UDP 4500)
EXPOSE 500/udp 4500/udp
EXPOSE 8080/tcp

# Volume for persistent data
VOLUME ["/data/ipsec"]

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD ipsec status 2>/dev/null | grep -q "Security Associations" || exit 1

# Entrypoint
ENTRYPOINT ["/scripts/entrypoint.sh"]
