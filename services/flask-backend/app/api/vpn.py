"""VPN Server and User Management API Endpoints."""

from datetime import datetime
from flask import Blueprint, request, jsonify, g
from functools import wraps
import json
import os
import base64

from ..models import get_db, VPN_TYPES, VPN_STATUS

vpn_bp = Blueprint("vpn", __name__)


def require_auth(f):
    """Decorator to require authentication."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not hasattr(g, "current_user") or g.current_user is None:
            return jsonify({"error": "Authentication required"}), 401
        return f(*args, **kwargs)
    return decorated


def audit_log(action: str, resource_type: str, resource_id: int,
              resource_name: str, old_value=None, new_value=None, details: str = None):
    """Create an audit log entry."""
    db = get_db()
    db.audit_log.insert(
        user_id=getattr(g, "current_user", {}).get("id"),
        user_email=getattr(g, "current_user", {}).get("email"),
        action=action,
        resource_type=resource_type,
        resource_id=resource_id,
        resource_name=resource_name,
        old_value=old_value,
        new_value=new_value,
        ip_address=request.remote_addr,
        user_agent=request.user_agent.string[:512] if request.user_agent else None,
        details=details,
    )
    db.commit()


# =============================================================================
# VPN Server Endpoints
# =============================================================================

@vpn_bp.route("/servers", methods=["GET"])
@require_auth
def list_vpn_servers():
    """List all VPN servers with optional filtering."""
    db = get_db()
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 20, type=int)
    vpn_type = request.args.get("vpn_type", type=str)
    is_active = request.args.get("is_active", type=lambda x: x.lower() == "true")

    query = db.vpn_servers

    if vpn_type:
        query = query.vpn_type == vpn_type
    if is_active is not None:
        if vpn_type:
            query = (db.vpn_servers.vpn_type == vpn_type) & (db.vpn_servers.is_active == is_active)
        else:
            query = db.vpn_servers.is_active == is_active

    offset = (page - 1) * per_page
    servers = db(query).select(
        orderby=db.vpn_servers.name,
        limitby=(offset, offset + per_page),
    )
    total = db(query).count()

    # Convert servers, excluding encrypted private keys from response
    servers_data = []
    for server in servers:
        server_dict = server.as_dict()
        server_dict.pop("private_key_encrypted", None)  # Remove sensitive data
        servers_data.append(server_dict)

    return jsonify({
        "servers": servers_data,
        "total": total,
        "page": page,
        "per_page": per_page,
        "pages": (total + per_page - 1) // per_page
    })


@vpn_bp.route("/servers", methods=["POST"])
@require_auth
def create_vpn_server():
    """Create a new VPN server."""
    db = get_db()
    data = request.get_json()

    if not data or not data.get("name") or not data.get("vpn_type"):
        return jsonify({"error": "Name and vpn_type are required"}), 400

    if data["vpn_type"] not in VPN_TYPES:
        return jsonify({
            "error": f"Invalid vpn_type. Must be one of: {', '.join(VPN_TYPES)}"
        }), 400

    # Check for duplicate server name
    existing = db(db.vpn_servers.name == data["name"]).select().first()
    if existing:
        return jsonify({"error": "Server name already exists"}), 409

    # Default listen port based on VPN type if not provided
    default_ports = {"wireguard": 51820, "ipsec": 500, "openvpn": 1194}
    listen_port = data.get("listen_port", default_ports.get(data["vpn_type"]))

    server_id = db.vpn_servers.insert(
        name=data["name"],
        vpn_type=data["vpn_type"],
        listen_port=listen_port,
        listen_interface=data.get("listen_interface"),
        server_address=data.get("server_address"),
        dns_servers=data.get("dns_servers", []),
        allowed_ips=data.get("allowed_ips"),
        private_key_encrypted=data.get("private_key_encrypted", ""),
        public_key=data.get("public_key", ""),
        config_data=data.get("config_data", {}),
        status="inactive",
        is_active=data.get("is_active", True),
    )
    db.commit()

    server = db.vpn_servers[server_id]
    server_dict = server.as_dict()
    server_dict.pop("private_key_encrypted", None)

    audit_log("create", "vpn_server", server_id, data["name"], new_value=server_dict)

    return jsonify({"server": server_dict}), 201


@vpn_bp.route("/servers/<int:server_id>", methods=["GET"])
@require_auth
def get_vpn_server(server_id: int):
    """Get a specific VPN server."""
    db = get_db()
    server = db.vpn_servers[server_id]
    if not server:
        return jsonify({"error": "VPN server not found"}), 404

    server_dict = server.as_dict()
    server_dict.pop("private_key_encrypted", None)
    return jsonify({"server": server_dict})


@vpn_bp.route("/servers/<int:server_id>", methods=["PUT"])
@require_auth
def update_vpn_server(server_id: int):
    """Update a VPN server."""
    db = get_db()
    server = db.vpn_servers[server_id]
    if not server:
        return jsonify({"error": "VPN server not found"}), 404

    data = request.get_json()
    old_value = server.as_dict()

    allowed_fields = {
        "name", "listen_port", "listen_interface", "server_address",
        "dns_servers", "allowed_ips", "public_key", "config_data", "is_active"
    }
    update_data = {k: v for k, v in data.items() if k in allowed_fields}

    if update_data:
        server.update_record(**update_data)
        db.commit()

    server = db.vpn_servers[server_id]
    new_value = server.as_dict()
    new_value.pop("private_key_encrypted", None)
    old_value.pop("private_key_encrypted", None)

    audit_log("update", "vpn_server", server_id, server.name, old_value=old_value, new_value=new_value)

    return jsonify({"server": new_value})


@vpn_bp.route("/servers/<int:server_id>", methods=["DELETE"])
@require_auth
def delete_vpn_server(server_id: int):
    """Delete a VPN server."""
    db = get_db()
    server = db.vpn_servers[server_id]
    if not server:
        return jsonify({"error": "VPN server not found"}), 404

    # Check if server has active users
    active_users = db(db.vpn_users.vpn_server == server_id).count()
    if active_users > 0:
        return jsonify({
            "error": f"Cannot delete server: {active_users} VPN users are associated with it"
        }), 409

    server_name = server.name
    old_value = server.as_dict()
    db(db.vpn_servers.id == server_id).delete()
    db.commit()

    audit_log("delete", "vpn_server", server_id, server_name, old_value=old_value)

    return jsonify({"message": "VPN server deleted"})


@vpn_bp.route("/servers/<int:server_id>/start", methods=["POST"])
@require_auth
def start_vpn_server(server_id: int):
    """Start a VPN server."""
    db = get_db()
    server = db.vpn_servers[server_id]
    if not server:
        return jsonify({"error": "VPN server not found"}), 404

    old_value = server.as_dict()

    # Update server status to active
    server.update_record(status="active")
    db.commit()

    server = db.vpn_servers[server_id]
    new_value = server.as_dict()
    new_value.pop("private_key_encrypted", None)
    old_value.pop("private_key_encrypted", None)

    audit_log("update", "vpn_server", server_id, server.name,
              old_value=old_value, new_value=new_value,
              details=f"Started VPN server")

    return jsonify({
        "message": f"VPN server '{server.name}' started",
        "server": new_value
    })


@vpn_bp.route("/servers/<int:server_id>/stop", methods=["POST"])
@require_auth
def stop_vpn_server(server_id: int):
    """Stop a VPN server."""
    db = get_db()
    server = db.vpn_servers[server_id]
    if not server:
        return jsonify({"error": "VPN server not found"}), 404

    old_value = server.as_dict()

    # Update server status to inactive
    server.update_record(status="inactive")
    db.commit()

    server = db.vpn_servers[server_id]
    new_value = server.as_dict()
    new_value.pop("private_key_encrypted", None)
    old_value.pop("private_key_encrypted", None)

    audit_log("update", "vpn_server", server_id, server.name,
              old_value=old_value, new_value=new_value,
              details=f"Stopped VPN server")

    return jsonify({
        "message": f"VPN server '{server.name}' stopped",
        "server": new_value
    })


# =============================================================================
# VPN User Endpoints
# =============================================================================

@vpn_bp.route("/users", methods=["GET"])
@require_auth
def list_vpn_users():
    """List all VPN users with optional filtering."""
    db = get_db()
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 20, type=int)
    vpn_server = request.args.get("vpn_server", type=int)
    is_active = request.args.get("is_active", type=lambda x: x.lower() == "true")

    query = db.vpn_users

    if vpn_server:
        query = query.vpn_server == vpn_server
    if is_active is not None:
        if vpn_server:
            query = (db.vpn_users.vpn_server == vpn_server) & (db.vpn_users.is_active == is_active)
        else:
            query = db.vpn_users.is_active == is_active

    offset = (page - 1) * per_page
    users = db(query).select(
        orderby=db.vpn_users.username,
        limitby=(offset, offset + per_page),
    )
    total = db(query).count()

    # Convert users, excluding encrypted keys from response
    users_data = []
    for user in users:
        user_dict = user.as_dict()
        user_dict.pop("preshared_key_encrypted", None)  # Remove sensitive data
        users_data.append(user_dict)

    return jsonify({
        "users": users_data,
        "total": total,
        "page": page,
        "per_page": per_page,
        "pages": (total + per_page - 1) // per_page
    })


@vpn_bp.route("/users", methods=["POST"])
@require_auth
def create_vpn_user():
    """Create a new VPN user."""
    db = get_db()
    data = request.get_json()

    if not data or not data.get("username") or not data.get("vpn_server"):
        return jsonify({"error": "Username and vpn_server are required"}), 400

    # Check for duplicate username
    existing = db(db.vpn_users.username == data["username"]).select().first()
    if existing:
        return jsonify({"error": "Username already exists"}), 409

    # Verify VPN server exists
    server = db.vpn_servers[data["vpn_server"]]
    if not server:
        return jsonify({"error": "VPN server not found"}), 404

    user_id = db.vpn_users.insert(
        username=data["username"],
        email=data.get("email"),
        vpn_server=data["vpn_server"],
        public_key=data.get("public_key", ""),
        allowed_ips=data.get("allowed_ips"),
        preshared_key_encrypted=data.get("preshared_key_encrypted", ""),
        config_data=data.get("config_data", {}),
        status=data.get("status", "inactive"),
        is_active=data.get("is_active", True),
        expires_at=data.get("expires_at"),
        created_by=getattr(g, "current_user", {}).get("id"),
    )
    db.commit()

    user = db.vpn_users[user_id]
    user_dict = user.as_dict()
    user_dict.pop("preshared_key_encrypted", None)

    audit_log("create", "vpn_user", user_id, data["username"], new_value=user_dict)

    return jsonify({"user": user_dict}), 201


@vpn_bp.route("/users/<int:user_id>", methods=["GET"])
@require_auth
def get_vpn_user(user_id: int):
    """Get a specific VPN user."""
    db = get_db()
    user = db.vpn_users[user_id]
    if not user:
        return jsonify({"error": "VPN user not found"}), 404

    user_dict = user.as_dict()
    user_dict.pop("preshared_key_encrypted", None)
    return jsonify({"user": user_dict})


@vpn_bp.route("/users/<int:user_id>", methods=["PUT"])
@require_auth
def update_vpn_user(user_id: int):
    """Update a VPN user."""
    db = get_db()
    user = db.vpn_users[user_id]
    if not user:
        return jsonify({"error": "VPN user not found"}), 404

    data = request.get_json()
    old_value = user.as_dict()

    allowed_fields = {
        "email", "public_key", "allowed_ips", "config_data",
        "status", "is_active", "expires_at"
    }
    update_data = {k: v for k, v in data.items() if k in allowed_fields}

    if update_data:
        user.update_record(**update_data)
        db.commit()

    user = db.vpn_users[user_id]
    new_value = user.as_dict()
    new_value.pop("preshared_key_encrypted", None)
    old_value.pop("preshared_key_encrypted", None)

    audit_log("update", "vpn_user", user_id, user.username, old_value=old_value, new_value=new_value)

    return jsonify({"user": new_value})


@vpn_bp.route("/users/<int:user_id>", methods=["DELETE"])
@require_auth
def delete_vpn_user(user_id: int):
    """Delete a VPN user."""
    db = get_db()
    user = db.vpn_users[user_id]
    if not user:
        return jsonify({"error": "VPN user not found"}), 404

    username = user.username
    old_value = user.as_dict()
    db(db.vpn_users.id == user_id).delete()
    db.commit()

    audit_log("delete", "vpn_user", user_id, username, old_value=old_value)

    return jsonify({"message": "VPN user deleted"})


@vpn_bp.route("/users/<int:user_id>/config", methods=["GET"])
@require_auth
def get_vpn_user_config(user_id: int):
    """Generate and return VPN user configuration file."""
    db = get_db()
    user = db.vpn_users[user_id]
    if not user:
        return jsonify({"error": "VPN user not found"}), 404

    # Get associated VPN server
    server = db.vpn_servers[user.vpn_server]
    if not server:
        return jsonify({"error": "Associated VPN server not found"}), 404

    # Build configuration based on VPN type
    config = {
        "username": user.username,
        "vpn_type": server.vpn_type,
        "server_name": server.name,
        "server_address": server.server_address,
        "listen_port": server.listen_port,
        "public_key": user.public_key,
        "allowed_ips": user.allowed_ips,
        "dns_servers": server.dns_servers,
        "generated_at": datetime.utcnow().isoformat(),
    }

    # Include custom config data if present
    if user.config_data:
        config.update(user.config_data)

    audit_log("update", "vpn_user", user_id, user.username,
              details=f"Downloaded VPN configuration")

    # Return configuration
    format_type = request.args.get("format", "json")

    if format_type == "wg":
        # Return WireGuard format
        wg_config = f"""[Interface]
PrivateKey = {user.config_data.get('private_key', 'YOUR_PRIVATE_KEY')}
Address = {user.allowed_ips}
DNS = {', '.join(server.dns_servers) if server.dns_servers else '8.8.8.8'}

[Peer]
PublicKey = {server.public_key}
AllowedIPs = {server.allowed_ips}
Endpoint = {server.server_address}:{server.listen_port}
"""
        return wg_config, 200, {
            "Content-Type": "text/plain",
            "Content-Disposition": f"attachment; filename=wg-{user.username}.conf"
        }

    elif format_type == "openvpn":
        # Return OpenVPN format
        ovpn_config = f"""client
proto udp
remote {server.server_address} {server.listen_port}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
verb 3
mute 20

<ca>
{user.config_data.get('ca_cert', 'CA_CERT_HERE')}
</ca>

<cert>
{user.config_data.get('client_cert', 'CLIENT_CERT_HERE')}
</cert>

<key>
{user.config_data.get('client_key', 'CLIENT_KEY_HERE')}
</key>
"""
        return ovpn_config, 200, {
            "Content-Type": "text/plain",
            "Content-Disposition": f"attachment; filename={user.username}.ovpn"
        }

    else:
        # Default JSON format
        return jsonify({"config": config})


# =============================================================================
# VPN Status and Statistics Endpoints
# =============================================================================

@vpn_bp.route("/status", methods=["GET"])
@require_auth
def get_vpn_status():
    """Get overall VPN infrastructure status."""
    db = get_db()

    # Aggregate statistics
    total_servers = db(db.vpn_servers).count()
    active_servers = db(db.vpn_servers.status == "active").count()
    inactive_servers = db(db.vpn_servers.status == "inactive").count()
    error_servers = db(db.vpn_servers.status == "error").count()

    total_users = db(db.vpn_users).count()
    active_users = db(db.vpn_users.is_active == True).count()
    inactive_users = db(db.vpn_users.is_active == False).count()

    # Server type breakdown
    server_types = {}
    for vpn_type in VPN_TYPES:
        server_types[vpn_type] = db(db.vpn_servers.vpn_type == vpn_type).count()

    # User status breakdown
    user_statuses = {}
    for status in VPN_STATUS:
        user_statuses[status] = db(db.vpn_users.status == status).count()

    # Traffic statistics
    total_bytes_received = 0
    total_bytes_sent = 0
    for user in db(db.vpn_users).select():
        total_bytes_received += user.bytes_received or 0
        total_bytes_sent += user.bytes_sent or 0

    return jsonify({
        "servers": {
            "total": total_servers,
            "active": active_servers,
            "inactive": inactive_servers,
            "error": error_servers,
            "by_type": server_types,
        },
        "users": {
            "total": total_users,
            "active": active_users,
            "inactive": inactive_users,
            "by_status": user_statuses,
        },
        "traffic": {
            "bytes_received": total_bytes_received,
            "bytes_sent": total_bytes_sent,
        },
        "timestamp": datetime.utcnow().isoformat(),
    })
