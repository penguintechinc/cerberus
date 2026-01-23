"""PyDAL Database Models."""

from datetime import datetime
from typing import Optional

from flask import Flask, g
from pydal import DAL, Field
from pydal.validators import (
    IS_EMAIL, IS_IN_SET, IS_NOT_EMPTY, IS_INT_IN_RANGE,
    IS_IPV4, IS_MATCH, IS_LENGTH
)

from .config import Config

# Valid roles for the application
VALID_ROLES = ["admin", "maintainer", "viewer"]

# NGFW Constants
ZONE_TYPES = ["wan", "lan", "dmz", "vpn", "custom"]
FIREWALL_ACTIONS = ["accept", "drop", "reject", "log"]
FIREWALL_PROTOCOLS = ["any", "tcp", "udp", "icmp", "icmpv6", "esp", "ah", "gre"]
NAT_TYPES = ["snat", "dnat", "masquerade"]
XDP_ACTIONS = ["pass", "drop", "inspect_ips", "capture_arkime", "inspect_all"]
XDP_MATCH_TYPES = ["src_ip", "dst_ip", "src_net", "dst_net", "src_port", "dst_port", "protocol", "vlan"]
IPS_ACTIONS = ["alert", "drop", "pass", "reject"]
VPN_TYPES = ["wireguard", "ipsec", "openvpn"]
VPN_STATUS = ["active", "inactive", "connecting", "error"]
AUDIT_ACTIONS = ["create", "update", "delete", "login", "logout", "config_change"]


def init_db(app: Flask) -> DAL:
    """Initialize database connection and define tables."""
    db_uri = Config.get_db_uri()

    # Use /app/databases for PyDAL migration files in container
    # Falls back to current directory for local development
    import os
    db_folder = "/app/databases" if os.path.isdir("/app/databases") else None

    # Check if we need to fake_migrate (table files don't exist but tables might)
    fake_migrate = False
    if db_folder:
        # If db_folder exists but has no .table files, use fake_migrate
        table_files = [f for f in os.listdir(db_folder) if f.endswith('.table')] if os.path.isdir(db_folder) else []
        fake_migrate = len(table_files) == 0

    db = DAL(
        db_uri,
        pool_size=Config.DB_POOL_SIZE,
        migrate=True,
        fake_migrate=fake_migrate,
        check_reserved=["common"],
        lazy_tables=False,
        folder=db_folder,
    )

    # Define users table
    db.define_table(
        "users",
        Field("email", "string", length=255, unique=True, requires=[
            IS_NOT_EMPTY(error_message="Email is required"),
            IS_EMAIL(error_message="Invalid email format"),
        ]),
        Field("password_hash", "string", length=255, requires=IS_NOT_EMPTY()),
        Field("full_name", "string", length=255),
        Field("role", "string", length=50, default="viewer", requires=IS_IN_SET(
            VALID_ROLES,
            error_message=f"Role must be one of: {', '.join(VALID_ROLES)}"
        )),
        Field("is_active", "boolean", default=True),
        Field("created_at", "datetime", default=datetime.utcnow),
        Field("updated_at", "datetime", default=datetime.utcnow, update=datetime.utcnow),
    )

    # Define refresh tokens table for token invalidation
    db.define_table(
        "refresh_tokens",
        Field("user_id", "reference users", requires=IS_NOT_EMPTY()),
        Field("token_hash", "string", length=255, unique=True),
        Field("expires_at", "datetime"),
        Field("revoked", "boolean", default=False),
        Field("created_at", "datetime", default=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - Network Zones
    # =========================================================================
    db.define_table(
        "zones",
        Field("name", "string", length=64, unique=True, requires=[
            IS_NOT_EMPTY(error_message="Zone name is required"),
            IS_LENGTH(64, 1, error_message="Zone name must be 1-64 characters"),
        ]),
        Field("zone_type", "string", length=32, default="custom", requires=IS_IN_SET(
            ZONE_TYPES, error_message=f"Zone type must be one of: {', '.join(ZONE_TYPES)}"
        )),
        Field("interface", "string", length=32),
        Field("network", "string", length=64),
        Field("description", "text"),
        Field("is_active", "boolean", default=True),
        Field("created_at", "datetime", default=datetime.utcnow),
        Field("updated_at", "datetime", default=datetime.utcnow, update=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - Firewall Rules
    # =========================================================================
    db.define_table(
        "firewall_rules",
        Field("name", "string", length=128, requires=IS_NOT_EMPTY()),
        Field("priority", "integer", default=100, requires=IS_INT_IN_RANGE(1, 65535)),
        Field("source_zone", "reference zones"),
        Field("dest_zone", "reference zones"),
        Field("source_address", "string", length=256),
        Field("dest_address", "string", length=256),
        Field("source_port", "string", length=128),
        Field("dest_port", "string", length=128),
        Field("protocol", "string", length=32, default="any", requires=IS_IN_SET(
            FIREWALL_PROTOCOLS, error_message="Invalid protocol"
        )),
        Field("action", "string", length=32, default="accept", requires=IS_IN_SET(
            FIREWALL_ACTIONS, error_message="Invalid action"
        )),
        Field("log_enabled", "boolean", default=False),
        Field("description", "text"),
        Field("is_active", "boolean", default=True),
        Field("hit_count", "bigint", default=0),
        Field("last_hit", "datetime"),
        Field("created_by", "reference users"),
        Field("created_at", "datetime", default=datetime.utcnow),
        Field("updated_at", "datetime", default=datetime.utcnow, update=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - NAT Rules
    # =========================================================================
    db.define_table(
        "nat_rules",
        Field("name", "string", length=128, requires=IS_NOT_EMPTY()),
        Field("priority", "integer", default=100, requires=IS_INT_IN_RANGE(1, 65535)),
        Field("nat_type", "string", length=32, requires=IS_IN_SET(
            NAT_TYPES, error_message="Invalid NAT type"
        )),
        Field("source_zone", "reference zones"),
        Field("dest_zone", "reference zones"),
        Field("source_address", "string", length=256),
        Field("dest_address", "string", length=256),
        Field("source_port", "string", length=128),
        Field("dest_port", "string", length=128),
        Field("translated_address", "string", length=256),
        Field("translated_port", "string", length=128),
        Field("protocol", "string", length=32, default="any"),
        Field("description", "text"),
        Field("is_active", "boolean", default=True),
        Field("created_by", "reference users"),
        Field("created_at", "datetime", default=datetime.utcnow),
        Field("updated_at", "datetime", default=datetime.utcnow, update=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - XDP Filter Rules (Packet Steering)
    # =========================================================================
    db.define_table(
        "xdp_filter_rules",
        Field("name", "string", length=128, requires=IS_NOT_EMPTY()),
        Field("priority", "integer", default=100, requires=IS_INT_IN_RANGE(1, 65535)),
        Field("match_type", "string", length=32, requires=IS_IN_SET(
            XDP_MATCH_TYPES, error_message="Invalid match type"
        )),
        Field("match_value", "string", length=256, requires=IS_NOT_EMPTY()),
        Field("action", "string", length=32, default="inspect_all", requires=IS_IN_SET(
            XDP_ACTIONS, error_message="Invalid XDP action"
        )),
        Field("description", "text"),
        Field("is_active", "boolean", default=True),
        Field("hit_count", "bigint", default=0),
        Field("last_hit", "datetime"),
        Field("created_by", "reference users"),
        Field("created_at", "datetime", default=datetime.utcnow),
        Field("updated_at", "datetime", default=datetime.utcnow, update=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - IPS Categories
    # =========================================================================
    db.define_table(
        "ips_categories",
        Field("name", "string", length=128, unique=True, requires=IS_NOT_EMPTY()),
        Field("description", "text"),
        Field("severity", "string", length=32, default="medium"),
        Field("is_active", "boolean", default=True),
        Field("rule_count", "integer", default=0),
        Field("created_at", "datetime", default=datetime.utcnow),
        Field("updated_at", "datetime", default=datetime.utcnow, update=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - IPS Rules
    # =========================================================================
    db.define_table(
        "ips_rules",
        Field("sid", "integer", unique=True, requires=IS_NOT_EMPTY()),
        Field("revision", "integer", default=1),
        Field("category", "reference ips_categories"),
        Field("message", "string", length=512),
        Field("action", "string", length=32, default="alert", requires=IS_IN_SET(
            IPS_ACTIONS, error_message="Invalid IPS action"
        )),
        Field("severity", "string", length=32, default="medium"),
        Field("rule_content", "text"),
        Field("is_active", "boolean", default=True),
        Field("hit_count", "bigint", default=0),
        Field("last_hit", "datetime"),
        Field("created_at", "datetime", default=datetime.utcnow),
        Field("updated_at", "datetime", default=datetime.utcnow, update=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - IPS Alerts
    # =========================================================================
    db.define_table(
        "ips_alerts",
        Field("timestamp", "datetime", requires=IS_NOT_EMPTY()),
        Field("sid", "integer"),
        Field("signature", "string", length=512),
        Field("category", "string", length=128),
        Field("severity", "string", length=32),
        Field("source_ip", "string", length=64),
        Field("source_port", "integer"),
        Field("dest_ip", "string", length=64),
        Field("dest_port", "integer"),
        Field("protocol", "string", length=32),
        Field("action_taken", "string", length=32),
        Field("payload_printable", "text"),
        Field("flow_id", "string", length=64),
        Field("raw_event", "json"),
        Field("created_at", "datetime", default=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - URL Categories
    # =========================================================================
    db.define_table(
        "url_categories",
        Field("name", "string", length=128, unique=True, requires=IS_NOT_EMPTY()),
        Field("description", "text"),
        Field("is_blocked", "boolean", default=False),
        Field("log_enabled", "boolean", default=True),
        Field("domain_count", "integer", default=0),
        Field("created_at", "datetime", default=datetime.utcnow),
        Field("updated_at", "datetime", default=datetime.utcnow, update=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - Filter Policies
    # =========================================================================
    db.define_table(
        "filter_policies",
        Field("name", "string", length=128, unique=True, requires=IS_NOT_EMPTY()),
        Field("description", "text"),
        Field("priority", "integer", default=100),
        Field("source_zone", "reference zones"),
        Field("blocked_categories", "list:reference url_categories"),
        Field("allowed_domains", "list:string"),
        Field("blocked_domains", "list:string"),
        Field("safe_search_enabled", "boolean", default=False),
        Field("ssl_inspection_enabled", "boolean", default=False),
        Field("log_enabled", "boolean", default=True),
        Field("is_active", "boolean", default=True),
        Field("created_by", "reference users"),
        Field("created_at", "datetime", default=datetime.utcnow),
        Field("updated_at", "datetime", default=datetime.utcnow, update=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - VPN Servers
    # =========================================================================
    db.define_table(
        "vpn_servers",
        Field("name", "string", length=128, unique=True, requires=IS_NOT_EMPTY()),
        Field("vpn_type", "string", length=32, requires=IS_IN_SET(
            VPN_TYPES, error_message="Invalid VPN type"
        )),
        Field("listen_port", "integer", default=51820),
        Field("listen_interface", "string", length=32),
        Field("server_address", "string", length=256),
        Field("dns_servers", "list:string"),
        Field("allowed_ips", "string", length=512),
        Field("private_key_encrypted", "text"),
        Field("public_key", "string", length=128),
        Field("config_data", "json"),
        Field("status", "string", length=32, default="inactive"),
        Field("is_active", "boolean", default=True),
        Field("created_at", "datetime", default=datetime.utcnow),
        Field("updated_at", "datetime", default=datetime.utcnow, update=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - VPN Users
    # =========================================================================
    db.define_table(
        "vpn_users",
        Field("username", "string", length=128, unique=True, requires=IS_NOT_EMPTY()),
        Field("email", "string", length=255),
        Field("vpn_server", "reference vpn_servers"),
        Field("public_key", "string", length=128),
        Field("allowed_ips", "string", length=512),
        Field("preshared_key_encrypted", "text"),
        Field("config_data", "json"),
        Field("status", "string", length=32, default="inactive", requires=IS_IN_SET(VPN_STATUS)),
        Field("last_handshake", "datetime"),
        Field("bytes_received", "bigint", default=0),
        Field("bytes_sent", "bigint", default=0),
        Field("is_active", "boolean", default=True),
        Field("expires_at", "datetime"),
        Field("created_by", "reference users"),
        Field("created_at", "datetime", default=datetime.utcnow),
        Field("updated_at", "datetime", default=datetime.utcnow, update=datetime.utcnow),
    )

    # =========================================================================
    # NGFW Tables - Audit Log
    # =========================================================================
    db.define_table(
        "audit_log",
        Field("timestamp", "datetime", default=datetime.utcnow),
        Field("user_id", "reference users"),
        Field("user_email", "string", length=255),
        Field("action", "string", length=32, requires=IS_IN_SET(AUDIT_ACTIONS)),
        Field("resource_type", "string", length=64),
        Field("resource_id", "integer"),
        Field("resource_name", "string", length=256),
        Field("old_value", "json"),
        Field("new_value", "json"),
        Field("ip_address", "string", length=64),
        Field("user_agent", "string", length=512),
        Field("details", "text"),
    )

    # Commit table definitions
    db.commit()

    # Store db instance in app
    app.config["db"] = db

    return db


def get_db() -> DAL:
    """Get database connection for current request context."""
    from flask import current_app

    if "db" not in g:
        g.db = current_app.config.get("db")
    return g.db


def get_user_by_email(email: str) -> Optional[dict]:
    """Get user by email address."""
    db = get_db()
    user = db(db.users.email == email).select().first()
    return user.as_dict() if user else None


def get_user_by_id(user_id: int) -> Optional[dict]:
    """Get user by ID."""
    db = get_db()
    user = db(db.users.id == user_id).select().first()
    return user.as_dict() if user else None


def create_user(email: str, password_hash: str, full_name: str = "",
                role: str = "viewer") -> dict:
    """Create a new user."""
    db = get_db()
    user_id = db.users.insert(
        email=email,
        password_hash=password_hash,
        full_name=full_name,
        role=role,
        is_active=True,
    )
    db.commit()
    return get_user_by_id(user_id)


def update_user(user_id: int, **kwargs) -> Optional[dict]:
    """Update user by ID."""
    db = get_db()

    # Filter allowed fields
    allowed_fields = {"email", "password_hash", "full_name", "role", "is_active"}
    update_data = {k: v for k, v in kwargs.items() if k in allowed_fields}

    if not update_data:
        return get_user_by_id(user_id)

    db(db.users.id == user_id).update(**update_data)
    db.commit()
    return get_user_by_id(user_id)


def delete_user(user_id: int) -> bool:
    """Delete user by ID."""
    db = get_db()
    deleted = db(db.users.id == user_id).delete()
    db.commit()
    return deleted > 0


def list_users(page: int = 1, per_page: int = 20) -> tuple[list[dict], int]:
    """List users with pagination."""
    db = get_db()
    offset = (page - 1) * per_page

    users = db(db.users).select(
        orderby=db.users.created_at,
        limitby=(offset, offset + per_page),
    )
    total = db(db.users).count()

    return [u.as_dict() for u in users], total


def store_refresh_token(user_id: int, token_hash: str, expires_at: datetime) -> int:
    """Store a refresh token."""
    db = get_db()
    token_id = db.refresh_tokens.insert(
        user_id=user_id,
        token_hash=token_hash,
        expires_at=expires_at,
    )
    db.commit()
    return token_id


def revoke_refresh_token(token_hash: str) -> bool:
    """Revoke a refresh token."""
    db = get_db()
    updated = db(db.refresh_tokens.token_hash == token_hash).update(revoked=True)
    db.commit()
    return updated > 0


def is_refresh_token_valid(token_hash: str) -> bool:
    """Check if refresh token is valid (not revoked and not expired)."""
    db = get_db()
    token = db(
        (db.refresh_tokens.token_hash == token_hash) &
        (db.refresh_tokens.revoked == False) &
        (db.refresh_tokens.expires_at > datetime.utcnow())
    ).select().first()
    return token is not None


def revoke_all_user_tokens(user_id: int) -> int:
    """Revoke all refresh tokens for a user."""
    db = get_db()
    updated = db(db.refresh_tokens.user_id == user_id).update(revoked=True)
    db.commit()
    return updated
