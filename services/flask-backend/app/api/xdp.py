"""XDP (eXpress Data Path) Packet Steering API Endpoints."""

from datetime import datetime
from flask import Blueprint, request, jsonify, g
from functools import wraps

from ..models import get_db, XDP_ACTIONS, XDP_MATCH_TYPES

xdp_bp = Blueprint("xdp", __name__)


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
# XDP Filter Rule Endpoints
# =============================================================================

@xdp_bp.route("/rules", methods=["GET"])
@require_auth
def list_xdp_rules():
    """List all XDP filter rules with pagination."""
    db = get_db()
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 50, type=int)
    is_active = request.args.get("is_active", type=lambda x: x.lower() == "true")

    query = db.xdp_filter_rules
    if is_active is not None:
        query = db.xdp_filter_rules.is_active == is_active

    offset = (page - 1) * per_page
    rules = db(query).select(
        orderby=db.xdp_filter_rules.priority,
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


@xdp_bp.route("/rules", methods=["POST"])
@require_auth
def create_xdp_rule():
    """Create a new XDP filter rule."""
    db = get_db()
    data = request.get_json()

    if not data or not data.get("name"):
        return jsonify({"error": "Rule name is required"}), 400

    if not data.get("match_type"):
        return jsonify({"error": "Match type is required"}), 400

    if not data.get("match_value"):
        return jsonify({"error": "Match value is required"}), 400

    if data.get("match_type") not in XDP_MATCH_TYPES:
        return jsonify({
            "error": f"Invalid match type. Must be one of: {XDP_MATCH_TYPES}"
        }), 400

    if data.get("action") and data["action"] not in XDP_ACTIONS:
        return jsonify({
            "error": f"Invalid action. Must be one of: {XDP_ACTIONS}"
        }), 400

    rule_id = db.xdp_filter_rules.insert(
        name=data["name"],
        priority=data.get("priority", 100),
        match_type=data["match_type"],
        match_value=data["match_value"],
        action=data.get("action", "inspect_all"),
        description=data.get("description"),
        is_active=data.get("is_active", True),
        created_by=getattr(g, "current_user", {}).get("id"),
    )
    db.commit()

    rule = db.xdp_filter_rules[rule_id]
    audit_log("create", "xdp_filter_rule", rule_id, data["name"],
              new_value=rule.as_dict())

    return jsonify({"rule": rule.as_dict()}), 201


@xdp_bp.route("/rules/<int:rule_id>", methods=["GET"])
@require_auth
def get_xdp_rule(rule_id: int):
    """Get a specific XDP filter rule."""
    db = get_db()
    rule = db.xdp_filter_rules[rule_id]
    if not rule:
        return jsonify({"error": "XDP rule not found"}), 404
    return jsonify({"rule": rule.as_dict()})


@xdp_bp.route("/rules/<int:rule_id>", methods=["PUT"])
@require_auth
def update_xdp_rule(rule_id: int):
    """Update an XDP filter rule."""
    db = get_db()
    rule = db.xdp_filter_rules[rule_id]
    if not rule:
        return jsonify({"error": "XDP rule not found"}), 404

    data = request.get_json()
    old_value = rule.as_dict()

    # Validate match_type if provided
    if data.get("match_type") and data["match_type"] not in XDP_MATCH_TYPES:
        return jsonify({
            "error": f"Invalid match type. Must be one of: {XDP_MATCH_TYPES}"
        }), 400

    # Validate action if provided
    if data.get("action") and data["action"] not in XDP_ACTIONS:
        return jsonify({
            "error": f"Invalid action. Must be one of: {XDP_ACTIONS}"
        }), 400

    allowed_fields = {
        "name", "priority", "match_type", "match_value", "action",
        "description", "is_active"
    }
    update_data = {k: v for k, v in data.items() if k in allowed_fields}

    if update_data:
        rule.update_record(**update_data)
        db.commit()

    rule = db.xdp_filter_rules[rule_id]
    audit_log("update", "xdp_filter_rule", rule_id, rule.name,
              old_value=old_value, new_value=rule.as_dict())

    return jsonify({"rule": rule.as_dict()})


@xdp_bp.route("/rules/<int:rule_id>", methods=["DELETE"])
@require_auth
def delete_xdp_rule(rule_id: int):
    """Delete an XDP filter rule."""
    db = get_db()
    rule = db.xdp_filter_rules[rule_id]
    if not rule:
        return jsonify({"error": "XDP rule not found"}), 404

    rule_name = rule.name
    old_value = rule.as_dict()
    db(db.xdp_filter_rules.id == rule_id).delete()
    db.commit()

    audit_log("delete", "xdp_filter_rule", rule_id, rule_name,
              old_value=old_value)

    return jsonify({"message": "XDP rule deleted"})


@xdp_bp.route("/rules/<int:rule_id>/toggle", methods=["POST"])
@require_auth
def toggle_xdp_rule(rule_id: int):
    """Toggle an XDP filter rule's active status."""
    db = get_db()
    rule = db.xdp_filter_rules[rule_id]
    if not rule:
        return jsonify({"error": "XDP rule not found"}), 404

    old_value = rule.as_dict()
    new_status = not rule.is_active
    rule.update_record(is_active=new_status)
    db.commit()

    rule = db.xdp_filter_rules[rule_id]
    audit_log("update", "xdp_filter_rule", rule_id, rule.name,
              old_value=old_value, new_value=rule.as_dict())

    return jsonify({"rule": rule.as_dict()})


@xdp_bp.route("/rules/reorder", methods=["POST"])
@require_auth
def reorder_xdp_rules():
    """Reorder XDP filter rules by updating priorities."""
    db = get_db()
    data = request.get_json()

    if not data or not data.get("rule_order"):
        return jsonify({"error": "rule_order array is required"}), 400

    if not isinstance(data["rule_order"], list):
        return jsonify({"error": "rule_order must be an array"}), 400

    for idx, rule_id in enumerate(data["rule_order"]):
        rule = db.xdp_filter_rules[rule_id]
        if rule:
            rule.update_record(priority=idx + 1)

    db.commit()

    rules = db(db.xdp_filter_rules).select(
        orderby=db.xdp_filter_rules.priority
    )
    return jsonify({"rules": [r.as_dict() for r in rules]})


# =============================================================================
# XDP Statistics Endpoints
# =============================================================================

@xdp_bp.route("/stats", methods=["GET"])
@require_auth
def get_xdp_stats():
    """Get XDP statistics (packets passed, dropped, redirected)."""
    db = get_db()

    # Aggregate statistics from all active XDP rules
    rules = db(db.xdp_filter_rules.is_active == True).select()

    stats = {
        "timestamp": datetime.utcnow().isoformat(),
        "total_rules": len(rules),
        "total_packets_passed": 0,
        "total_packets_dropped": 0,
        "total_packets_redirected": 0,
        "total_hits": 0,
        "rules_by_action": {},
        "rule_details": []
    }

    # Initialize action counters
    for action in XDP_ACTIONS:
        stats["rules_by_action"][action] = {
            "count": 0,
            "hits": 0
        }

    # Process each rule
    for rule in rules:
        rule_dict = rule.as_dict()
        action = rule.action

        # Count rules by action
        stats["rules_by_action"][action]["count"] += 1
        stats["rules_by_action"][action]["hits"] += rule.hit_count or 0

        # Accumulate packet counts based on action
        if action == "pass":
            stats["total_packets_passed"] += rule.hit_count or 0
        elif action == "drop":
            stats["total_packets_dropped"] += rule.hit_count or 0
        elif action in ["redirect", "capture_arkime"]:
            stats["total_packets_redirected"] += rule.hit_count or 0

        stats["total_hits"] += rule.hit_count or 0

        # Add rule details with last hit information
        rule_dict["last_hit_ago_seconds"] = None
        if rule.last_hit:
            delta = datetime.utcnow() - rule.last_hit
            rule_dict["last_hit_ago_seconds"] = int(delta.total_seconds())

        stats["rule_details"].append(rule_dict)

    return jsonify(stats)
