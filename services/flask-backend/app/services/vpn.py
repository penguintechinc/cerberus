"""Cerberus VPN Service - VPN Server Management."""

import os
import base64
import requests
from typing import Optional, List, Dict, Any
from dataclasses import dataclass, asdict
from datetime import datetime


@dataclass
class VPNServer:
    """VPN server information."""

    name: str
    type: str  # wireguard, ipsec, openvpn
    status: str
    endpoint: str
    api_url: str
    connected_clients: int = 0
    public_key: Optional[str] = None


@dataclass
class VPNClient:
    """VPN client information."""

    name: str
    server_type: str
    created: datetime
    public_key: Optional[str] = None
    address: Optional[str] = None


class VPNService:
    """Service for managing VPN servers and clients."""

    def __init__(
        self,
        wireguard_url: str = None,
        ipsec_url: str = None,
        openvpn_url: str = None,
        request_timeout: int = 10,
    ):
        """Initialize VPN service.

        Args:
            wireguard_url: URL for WireGuard API
            ipsec_url: URL for IPSec API
            openvpn_url: URL for OpenVPN API
            request_timeout: Request timeout in seconds
        """
        self.wireguard_url = wireguard_url or os.environ.get(
            "WIREGUARD_API_URL", "http://cerberus-vpn-wireguard:8080"
        )
        self.ipsec_url = ipsec_url or os.environ.get(
            "IPSEC_API_URL", "http://cerberus-vpn-ipsec:8080"
        )
        self.openvpn_url = openvpn_url or os.environ.get(
            "OPENVPN_API_URL", "http://cerberus-vpn-openvpn:8080"
        )
        self.timeout = request_timeout

    def _get(self, url: str) -> Optional[Dict[str, Any]]:
        """Make GET request to VPN API."""
        try:
            resp = requests.get(url, timeout=self.timeout)
            resp.raise_for_status()
            return resp.json()
        except Exception:
            return None

    def _post(self, url: str, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Make POST request to VPN API."""
        try:
            resp = requests.post(url, json=data, timeout=self.timeout)
            resp.raise_for_status()
            return resp.json()
        except Exception:
            return None

    def _delete(self, url: str) -> Optional[Dict[str, Any]]:
        """Make DELETE request to VPN API."""
        try:
            resp = requests.delete(url, timeout=self.timeout)
            resp.raise_for_status()
            return resp.json()
        except Exception:
            return None

    # Server Status Methods

    def get_servers_status(self) -> List[VPNServer]:
        """Get status of all VPN servers."""
        servers = []

        # WireGuard
        wg_status = self._get(f"{self.wireguard_url}/api/v1/status")
        if wg_status:
            servers.append(
                VPNServer(
                    name="WireGuard",
                    type="wireguard",
                    status="running",
                    endpoint=f"{self.wireguard_url}",
                    api_url=self.wireguard_url,
                    connected_clients=wg_status.get("peer_count", 0),
                    public_key=wg_status.get("public_key"),
                )
            )
        else:
            servers.append(
                VPNServer(
                    name="WireGuard",
                    type="wireguard",
                    status="offline",
                    endpoint=self.wireguard_url,
                    api_url=self.wireguard_url,
                )
            )

        # IPSec
        ipsec_status = self._get(f"{self.ipsec_url}/api/v1/status")
        if ipsec_status:
            servers.append(
                VPNServer(
                    name="IPSec/IKEv2",
                    type="ipsec",
                    status="running",
                    endpoint=self.ipsec_url,
                    api_url=self.ipsec_url,
                    connected_clients=ipsec_status.get("active_connections", 0),
                )
            )
        else:
            servers.append(
                VPNServer(
                    name="IPSec/IKEv2",
                    type="ipsec",
                    status="offline",
                    endpoint=self.ipsec_url,
                    api_url=self.ipsec_url,
                )
            )

        # OpenVPN
        ovpn_status = self._get(f"{self.openvpn_url}/api/v1/status")
        if ovpn_status:
            servers.append(
                VPNServer(
                    name="OpenVPN",
                    type="openvpn",
                    status="running",
                    endpoint=self.openvpn_url,
                    api_url=self.openvpn_url,
                    connected_clients=ovpn_status.get("connected_clients", 0),
                )
            )
        else:
            servers.append(
                VPNServer(
                    name="OpenVPN",
                    type="openvpn",
                    status="offline",
                    endpoint=self.openvpn_url,
                    api_url=self.openvpn_url,
                )
            )

        return servers

    def get_server_status(self, server_type: str) -> Optional[VPNServer]:
        """Get status of a specific VPN server."""
        servers = self.get_servers_status()
        for server in servers:
            if server.type == server_type:
                return server
        return None

    # WireGuard Methods

    def wg_list_peers(self) -> List[Dict[str, Any]]:
        """List WireGuard peers."""
        result = self._get(f"{self.wireguard_url}/api/v1/peers")
        return result.get("peers", []) if result else []

    def wg_add_peer(self, name: str) -> Optional[Dict[str, Any]]:
        """Add a WireGuard peer."""
        return self._post(f"{self.wireguard_url}/api/v1/peers/add", {"name": name})

    def wg_remove_peer(self, name: str) -> bool:
        """Remove a WireGuard peer."""
        result = self._post(f"{self.wireguard_url}/api/v1/peers/remove/{name}", {})
        return result is not None and result.get("status") == "removed"

    def wg_get_client_config(self, name: str) -> Optional[str]:
        """Get WireGuard client configuration."""
        result = self.wg_add_peer(name)
        if result and "client_config" in result:
            return base64.b64decode(result["client_config"]).decode("utf-8")
        return None

    # IPSec Methods

    def ipsec_list_users(self) -> List[Dict[str, Any]]:
        """List IPSec users."""
        result = self._get(f"{self.ipsec_url}/api/v1/users")
        return result.get("users", []) if result else []

    def ipsec_add_user(self, username: str, password: str) -> Optional[Dict[str, Any]]:
        """Add an IPSec user."""
        return self._post(
            f"{self.ipsec_url}/api/v1/users/add",
            {"username": username, "password": password},
        )

    def ipsec_remove_user(self, username: str) -> bool:
        """Remove an IPSec user."""
        result = self._post(f"{self.ipsec_url}/api/v1/users/remove/{username}", {})
        return result is not None and result.get("status") == "removed"

    def ipsec_get_ca_cert(self) -> Optional[str]:
        """Get IPSec CA certificate."""
        result = self._get(f"{self.ipsec_url}/api/v1/ca")
        if result and "ca_cert" in result:
            return base64.b64decode(result["ca_cert"]).decode("utf-8")
        return None

    # OpenVPN Methods

    def openvpn_list_clients(self) -> List[Dict[str, Any]]:
        """List OpenVPN clients."""
        result = self._get(f"{self.openvpn_url}/api/v1/clients")
        return result.get("clients", []) if result else []

    def openvpn_add_client(self, name: str) -> Optional[Dict[str, Any]]:
        """Add an OpenVPN client."""
        return self._post(f"{self.openvpn_url}/api/v1/clients/add", {"name": name})

    def openvpn_revoke_client(self, name: str) -> bool:
        """Revoke an OpenVPN client."""
        result = self._post(f"{self.openvpn_url}/api/v1/clients/revoke/{name}", {})
        return result is not None and result.get("status") == "revoked"

    def openvpn_get_client_config(self, name: str) -> Optional[str]:
        """Get OpenVPN client configuration."""
        result = self._get(f"{self.openvpn_url}/api/v1/clients/config/{name}")
        if result and "config" in result:
            return base64.b64decode(result["config"]).decode("utf-8")
        return None

    def openvpn_get_ca_cert(self) -> Optional[str]:
        """Get OpenVPN CA certificate."""
        result = self._get(f"{self.openvpn_url}/api/v1/ca")
        if result and "ca_cert" in result:
            return base64.b64decode(result["ca_cert"]).decode("utf-8")
        return None

    # Unified Methods

    def list_all_clients(self) -> Dict[str, List[Dict[str, Any]]]:
        """List all VPN clients across all servers."""
        return {
            "wireguard": self.wg_list_peers(),
            "ipsec": self.ipsec_list_users(),
            "openvpn": self.openvpn_list_clients(),
        }

    def get_stats(self) -> Dict[str, Any]:
        """Get aggregate VPN statistics."""
        servers = self.get_servers_status()

        total_connected = sum(s.connected_clients for s in servers)
        running_servers = sum(1 for s in servers if s.status == "running")

        return {
            "total_connected_clients": total_connected,
            "running_servers": running_servers,
            "total_servers": len(servers),
            "servers": [asdict(s) for s in servers],
        }
