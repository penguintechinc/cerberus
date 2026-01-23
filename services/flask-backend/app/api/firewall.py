"""Firewall Rules API Endpoints."""

from datetime import datetime
from flask import Blueprint, request, jsonify, g
from functools import wraps

from ..models import get_db, FIREWALL_ACTIONS, FIREWALL_PROTOCOLS

firewall_bp = Blueprint("firewall", __name__)


def require_auth(f):
    """Decorator to require authentication."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not hasattr(g, "current_user") or g.current_user is None:
            return jsonify({"error": "Authentication required"}), 401
        return f(*args, **kwargs)
    return decorated


def audit_log(action: str, resource_type: str, resource_id: int,
              resource_name: str, old_value=None, new_value=None):
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
    )
    db.commit()


# =============================================================================
# Zone Endpoints
# =============================================================================

@firewall_bp.route("/zones", methods=["GET"])
@require_auth
def list_zones():
    """List all network zones."""
    db = get_db()
    zones = db(db.zones).select(orderby=db.zones.name)
    return jsonify({
        "zones": [z.as_dict() for z in zones],
        "total": len(zones)
    })


@firewall_bp.route("/zones", methods=["POST"])
@require_auth
def create_zone():
    """Create a new network zone."""
    db = get_db()
    data = request.get_json()

    if not data or not data.get("name"):
        return jsonify({"error": "Zone name is required"}), 400

    existing = db(db.zones.name == data["name"]).select().first()
    if existing:
        return jsonify({"error": "Zone name already exists"}), 409

    zone_id = db.zones.insert(
        name=data["name"],
        zone_type=data.get("zone_type", "custom"),
        interface=data.get("interface"),
        network=data.get("network"),
        description=data.get("description"),
        is_active=data.get("is_active", True),
    )
    db.commit()

    zone = db.zones[zone_id]
    audit_log("create", "zone", zone_id, data["name"], new_value=zone.as_dict())

    return jsonify({"zone": zone.as_dict()}), 201


@firewall_bp.route("/zones/<int:zone_id>", methods=["GET"])
@require_auth
def get_zone(zone_id: int):
    """Get a specific zone."""
    db = get_db()
    zone = db.zones[zone_id]
    if not zone:
        return jsonify({"error": "Zone not found"}), 404
    return jsonify({"zone": zone.as_dict()})


@firewall_bp.route("/zones/<int:zone_id>", methods=["PUT"])
@require_auth
def update_zone(zone_id: int):
    """Update a zone."""
    db = get_db()
    zone = db.zones[zone_id]
    if not zone:
        return jsonify({"error": "Zone not found"}), 404

    data = request.get_json()
    old_value = zone.as_dict()

    allowed_fields = {"name", "zone_type", "interface", "network", "description", "is_active"}
    update_data = {k: v for k, v in data.items() if k in allowed_fields}

    if update_data:
        zone.update_record(**update_data)
        db.commit()

    zone = db.zones[zone_id]
    audit_log("update", "zone", zone_id, zone.name, old_value=old_value, new_value=zone.as_dict())

    return jsonify({"zone": zone.as_dict()})


@firewall_bp.route("/zones/<int:zone_id>", methods=["DELETE"])
@require_auth
def delete_zone(zone_id: int):
    """Delete a zone."""
    db = get_db()
    zone = db.zones[zone_id]
    if not zone:
        return jsonify({"error": "Zone not found"}), 404

    rules_using_zone = db(
        (db.firewall_rules.source_zone == zone_id) |
        (db.firewall_rules.dest_zone == zone_id)
    ).count()

    if rules_using_zone > 0:
        return jsonify({
            "error": f"Cannot delete zone: {rules_using_zone} firewall rules reference it"
        }), 409

    zone_name = zone.name
    old_value = zone.as_dict()
    db(db.zones.id == zone_id).delete()
    db.commit()

    audit_log("delete", "zone", zone_id, zone_name, old_value=old_value)

    return jsonify({"message": "Zone deleted"})


# =============================================================================
# Firewall Rule Endpoints
# =============================================================================

@firewall_bp.route("/rules", methods=["GET"])
@require_auth
def list_rules():
    """List all firewall rules with pagination."""
    db = get_db()
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 50, type=int)
    is_active = request.args.get("is_active", type=lambda x: x.lower() == "true")

    query = db.firewall_rules
    if is_active is not None:
        query = db.firewall_rules.is_active == is_active

    offset = (page - 1) * per_page
    rules = db(query).select(
        orderby=db.firewall_rules.priority,
        limitby=(offset, offset + per_page),
    )
    total = db(query).count()

    return jsonify({
        "rules": [r.as_dict() for r in rules],
        "total": total,
        "page": page,
        "per_page": per_page,
        "pages": (total + per_page - 1) // per_page
    })


@firewall_bp.route("/rules", methods=["POST"])
@require_auth
def create_rule():
    """Create a new firewall rule."""
    db = get_db()
    data = request.get_json()

    if not data or not data.get("name"):
        return jsonify({"error": "Rule name is required"}), 400

    if data.get("action") and data["action"] not in FIREWALL_ACTIONS:
        return jsonify({"error": f"Invalid action. Must be one of: {FIREWALL_ACTIONS}"}), 400

    if data.get("protocol") and data["protocol"] not in FIREWALL_PROTOCOLS:
        return jsonify({"error": f"Invalid protocol. Must be one of: {FIREWALL_PROTOCOLS}"}), 400

    rule_id = db.firewall_rules.insert(
        name=data["name"],
        priority=data.get("priority", 100),
        source_zone=data.get("source_zone"),
        dest_zone=data.get("dest_zone"),
        source_address=data.get("source_address"),
        dest_address=data.get("dest_address"),
        source_port=data.get("source_port"),
        dest_port=data.get("dest_port"),
        protocol=data.get("protocol", "any"),
        action=data.get("action", "accept"),
        log_enabled=data.get("log_enabled", False),
        description=data.get("description"),
        is_active=data.get("is_active", True),
        created_by=getattr(g, "current_user", {}).get("id"),
    )
    db.commit()

    rule = db.firewall_rules[rule_id]
    audit_log("create", "firewall_rule", rule_id, data["name"], new_value=rule.as_dict())

    return jsonify({"rule": rule.as_dict()}), 201


@firewall_bp.route("/rules/<int:rule_id>", methods=["GET"])
@require_auth
def get_rule(rule_id: int):
    """Get a specific firewall rule."""
    db = get_db()
    rule = db.firewall_rules[rule_id]
    if not rule:
        return jsonify({"error": "Rule not found"}), 404
    return jsonify({"rule": rule.as_dict()})


@firewall_bp.route("/rules/<int:rule_id>", methods=["PUT"])
@require_auth
def update_rule(rule_id: int):
    """Update a firewall rule."""
    db = get_db()
    rule = db.firewall_rules[rule_id]
    if not rule:
        return jsonify({"error": "Rule not found"}), 404

    data = request.get_json()
    old_value = rule.as_dict()

    allowed_fields = {
        "name", "priority", "source_zone", "dest_zone", "source_address",
        "dest_address", "source_port", "dest_port", "protocol", "action",
        "log_enabled", "description", "is_active"
    }
    update_data = {k: v for k, v in data.items() if k in allowed_fields}

    if update_data:
        rule.update_record(**update_data)
        db.commit()

    rule = db.firewall_rules[rule_id]
    audit_log("update", "firewall_rule", rule_id, rule.name, old_value=old_value, new_value=rule.as_dict())

    return jsonify({"rule": rule.as_dict()})


@firewall_bp.route("/rules/<int:rule_id>", methods=["DELETE"])
@require_auth
def delete_rule(rule_id: int):
    """Delete a firewall rule."""
    db = get_db()
    rule = db.firewall_rules[rule_id]
    if not rule:
        return jsonify({"error": "Rule not found"}), 404

    rule_name = rule.name
    old_value = rule.as_dict()
    db(db.firewall_rules.id == rule_id).delete()
    db.commit()

    audit_log("delete", "firewall_rule", rule_id, rule_name, old_value=old_value)

    return jsonify({"message": "Rule deleted"})


@firewall_bp.route("/rules/<int:rule_id>/toggle", methods=["POST"])
@require_auth
def toggle_rule(rule_id: int):
    """Toggle a firewall rule's active status."""
    db = get_db()
    rule = db.firewall_rules[rule_id]
    if not rule:
        return jsonify({"error": "Rule not found"}), 404

    old_value = rule.as_dict()
    new_status = not rule.is_active
    rule.update_record(is_active=new_status)
    db.commit()

    rule = db.firewall_rules[rule_id]
    audit_log("update", "firewall_rule", rule_id, rule.name, old_value=old_value, new_value=rule.as_dict())

    return jsonify({"rule": rule.as_dict()})


@firewall_bp.route("/rules/reorder", methods=["POST"])
@require_auth
def reorder_rules():
    """Reorder firewall rules by updating priorities."""
    db = get_db()
    data = request.get_json()

    if not data or not data.get("rule_order"):
        return jsonify({"error": "rule_order array is required"}), 400

    for idx, rule_id in enumerate(data["rule_order"]):
        rule = db.firewall_rules[rule_id]
        if rule:
            rule.update_record(priority=idx + 1)

    db.commit()

    rules = db(db.firewall_rules).select(orderby=db.firewall_rules.priority)
    return jsonify({"rules": [r.as_dict() for r in rules]})


# =============================================================================
# NAT Rule Endpoints
# =============================================================================

@firewall_bp.route("/nat", methods=["GET"])
@require_auth
def list_nat_rules():
    """List all NAT rules."""
    db = get_db()
    rules = db(db.nat_rules).select(orderby=db.nat_rules.priority)
    return jsonify({
        "rules": [r.as_dict() for r in rules],
        "total": len(rules)
    })


@firewall_bp.route("/nat", methods=["POST"])
@require_auth
def create_nat_rule():
    """Create a new NAT rule."""
    db = get_db()
    data = request.get_json()

    if not data or not data.get("name") or not data.get("nat_type"):
        return jsonify({"error": "Name and nat_type are required"}), 400

    rule_id = db.nat_rules.insert(
        name=data["name"],
        priority=data.get("priority", 100),
        nat_type=data["nat_type"],
        source_zone=data.get("source_zone"),
        dest_zone=data.get("dest_zone"),
        source_address=data.get("source_address"),
        dest_address=data.get("dest_address"),
        source_port=data.get("source_port"),
        dest_port=data.get("dest_port"),
        translated_address=data.get("translated_address"),
        translated_port=data.get("translated_port"),
        protocol=data.get("protocol", "any"),
        description=data.get("description"),
        is_active=data.get("is_active", True),
        created_by=getattr(g, "current_user", {}).get("id"),
    )
    db.commit()

    rule = db.nat_rules[rule_id]
    audit_log("create", "nat_rule", rule_id, data["name"], new_value=rule.as_dict())

    return jsonify({"rule": rule.as_dict()}), 201


@firewall_bp.route("/nat/<int:rule_id>", methods=["GET"])
@require_auth
def get_nat_rule(rule_id: int):
    """Get a specific NAT rule."""
    db = get_db()
    rule = db.nat_rules[rule_id]
    if not rule:
        return jsonify({"error": "NAT rule not found"}), 404
    return jsonify({"rule": rule.as_dict()})


@firewall_bp.route("/nat/<int:rule_id>", methods=["PUT"])
@require_auth
def update_nat_rule(rule_id: int):
    """Update a NAT rule."""
    db = get_db()
    rule = db.nat_rules[rule_id]
    if not rule:
        return jsonify({"error": "NAT rule not found"}), 404

    data = request.get_json()
    old_value = rule.as_dict()

    allowed_fields = {
        "name", "priority", "nat_type", "source_zone", "dest_zone",
        "source_address", "dest_address", "source_port", "dest_port",
        "translated_address", "translated_port", "protocol", "description", "is_active"
    }
    update_data = {k: v for k, v in data.items() if k in allowed_fields}

    if update_data:
        rule.update_record(**update_data)
        db.commit()

    rule = db.nat_rules[rule_id]
    audit_log("update", "nat_rule", rule_id, rule.name, old_value=old_value, new_value=rule.as_dict())

    return jsonify({"rule": rule.as_dict()})


@firewall_bp.route("/nat/<int:rule_id>", methods=["DELETE"])
@require_auth
def delete_nat_rule(rule_id: int):
    """Delete a NAT rule."""
    db = get_db()
    rule = db.nat_rules[rule_id]
    if not rule:
        return jsonify({"error": "NAT rule not found"}), 404

    rule_name = rule.name
    old_value = rule.as_dict()
    db(db.nat_rules.id == rule_id).delete()
    db.commit()

    audit_log("delete", "nat_rule", rule_id, rule_name, old_value=old_value)

    return jsonify({"message": "NAT rule deleted"})
