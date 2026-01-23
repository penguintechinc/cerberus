"""IPS (Intrusion Prevention System) API Endpoints."""

from datetime import datetime
from flask import Blueprint, request, jsonify, g
from functools import wraps

from ..models import get_db, IPS_ACTIONS

ips_bp = Blueprint("ips", __name__)


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
# IPS Category Endpoints
# =============================================================================

@ips_bp.route("/categories", methods=["GET"])
@require_auth
def list_categories():
    """List all IPS categories."""
    db = get_db()
    categories = db(db.ips_categories).select(orderby=db.ips_categories.name)
    return jsonify({
        "categories": [c.as_dict() for c in categories],
        "total": len(categories)
    })


@ips_bp.route("/categories", methods=["POST"])
@require_auth
def create_category():
    """Create a new IPS category."""
    db = get_db()
    data = request.get_json()

    if not data or not data.get("name"):
        return jsonify({"error": "Category name is required"}), 400

    existing = db(db.ips_categories.name == data["name"]).select().first()
    if existing:
        return jsonify({"error": "Category name already exists"}), 409

    category_id = db.ips_categories.insert(
        name=data["name"],
        description=data.get("description"),
        severity=data.get("severity", "medium"),
        is_active=data.get("is_active", True),
    )
    db.commit()

    category = db.ips_categories[category_id]
    audit_log("create", "ips_category", category_id, data["name"],
              new_value=category.as_dict())

    return jsonify({"category": category.as_dict()}), 201


@ips_bp.route("/categories/<int:category_id>", methods=["PUT"])
@require_auth
def update_category(category_id: int):
    """Update an IPS category."""
    db = get_db()
    category = db.ips_categories[category_id]
    if not category:
        return jsonify({"error": "Category not found"}), 404

    data = request.get_json()
    old_value = category.as_dict()

    allowed_fields = {"name", "description", "severity", "is_active"}
    update_data = {k: v for k, v in data.items() if k in allowed_fields}

    # Check for duplicate name
    if "name" in update_data and update_data["name"] != category.name:
        existing = db(db.ips_categories.name == update_data["name"]).select().first()
        if existing:
            return jsonify({"error": "Category name already exists"}), 409

    if update_data:
        category.update_record(**update_data)
        db.commit()

    category = db.ips_categories[category_id]
    audit_log("update", "ips_category", category_id, category.name,
              old_value=old_value, new_value=category.as_dict())

    return jsonify({"category": category.as_dict()})


@ips_bp.route("/categories/<int:category_id>", methods=["DELETE"])
@require_auth
def delete_category(category_id: int):
    """Delete an IPS category."""
    db = get_db()
    category = db.ips_categories[category_id]
    if not category:
        return jsonify({"error": "Category not found"}), 404

    rules_using_category = db(db.ips_rules.category == category_id).count()
    if rules_using_category > 0:
        return jsonify({
            "error": f"Cannot delete category: {rules_using_category} IPS rules reference it"
        }), 409

    category_name = category.name
    old_value = category.as_dict()
    db(db.ips_categories.id == category_id).delete()
    db.commit()

    audit_log("delete", "ips_category", category_id, category_name,
              old_value=old_value)

    return jsonify({"message": "Category deleted"})


# =============================================================================
# IPS Rule Endpoints
# =============================================================================

@ips_bp.route("/rules", methods=["GET"])
@require_auth
def list_rules():
    """List IPS rules with pagination."""
    db = get_db()
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 50, type=int)
    is_active = request.args.get("is_active", type=lambda x: x.lower() == "true")
    category_id = request.args.get("category", type=int)

    query = db.ips_rules
    if is_active is not None:
        query = (query.is_active == is_active) if query != db.ips_rules else (db.ips_rules.is_active == is_active)
    if category_id is not None:
        if query == db.ips_rules:
            query = db.ips_rules.category == category_id
        else:
            query = query & (db.ips_rules.category == category_id)

    offset = (page - 1) * per_page
    rules = db(query).select(
        orderby=db.ips_rules.sid,
        limitby=(offset, offset + per_page),
    ) if query != db.ips_rules else db(db.ips_rules).select(
        orderby=db.ips_rules.sid,
        limitby=(offset, offset + per_page),
    )
    total = db(query).count() if query != db.ips_rules else db(db.ips_rules).count()

    return jsonify({
        "rules": [r.as_dict() for r in rules],
        "total": total,
        "page": page,
        "per_page": per_page,
        "pages": (total + per_page - 1) // per_page
    })


@ips_bp.route("/rules/<int:sid>/toggle", methods=["PUT"])
@require_auth
def toggle_rule(sid: int):
    """Toggle an IPS rule's active status."""
    db = get_db()
    rule = db(db.ips_rules.sid == sid).select().first()
    if not rule:
        return jsonify({"error": "Rule not found"}), 404

    old_value = rule.as_dict()
    new_status = not rule.is_active
    rule.update_record(is_active=new_status)
    db.commit()

    rule = db(db.ips_rules.sid == sid).select().first()
    audit_log("update", "ips_rule", rule.id, f"Rule {sid}",
              old_value=old_value, new_value=rule.as_dict())

    return jsonify({"rule": rule.as_dict()})


# =============================================================================
# IPS Alert Endpoints
# =============================================================================

@ips_bp.route("/alerts", methods=["GET"])
@require_auth
def list_alerts():
    """List IPS alerts with pagination and filters."""
    db = get_db()
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 50, type=int)
    severity = request.args.get("severity")
    source_ip = request.args.get("source_ip")
    start_time = request.args.get("start_time")
    end_time = request.args.get("end_time")

    query = db.ips_alerts

    # Apply filters
    if severity:
        query = (query.severity == severity) if query == db.ips_alerts else (query & (db.ips_alerts.severity == severity))
    if source_ip:
        query = (query.source_ip == source_ip) if query == db.ips_alerts else (query & (db.ips_alerts.source_ip == source_ip))
    if start_time:
        try:
            start_dt = datetime.fromisoformat(start_time)
            query = (query.timestamp >= start_dt) if query == db.ips_alerts else (query & (db.ips_alerts.timestamp >= start_dt))
        except ValueError:
            return jsonify({"error": "Invalid start_time format. Use ISO 8601"}), 400
    if end_time:
        try:
            end_dt = datetime.fromisoformat(end_time)
            query = (query.timestamp <= end_dt) if query == db.ips_alerts else (query & (db.ips_alerts.timestamp <= end_dt))
        except ValueError:
            return jsonify({"error": "Invalid end_time format. Use ISO 8601"}), 400

    offset = (page - 1) * per_page
    alerts = db(query).select(
        orderby=~db.ips_alerts.timestamp,
        limitby=(offset, offset + per_page),
    ) if query != db.ips_alerts else db(db.ips_alerts).select(
        orderby=~db.ips_alerts.timestamp,
        limitby=(offset, offset + per_page),
    )
    total = db(query).count() if query != db.ips_alerts else db(db.ips_alerts).count()

    return jsonify({
        "alerts": [a.as_dict() for a in alerts],
        "total": total,
        "page": page,
        "per_page": per_page,
        "pages": (total + per_page - 1) // per_page
    })


@ips_bp.route("/alerts/<int:alert_id>", methods=["GET"])
@require_auth
def get_alert(alert_id: int):
    """Get a specific IPS alert."""
    db = get_db()
    alert = db.ips_alerts[alert_id]
    if not alert:
        return jsonify({"error": "Alert not found"}), 404
    return jsonify({"alert": alert.as_dict()})


# =============================================================================
# IPS Statistics Endpoints
# =============================================================================

@ips_bp.route("/stats", methods=["GET"])
@require_auth
def get_stats():
    """Get IPS statistics."""
    db = get_db()

    # Total alerts
    total_alerts = db(db.ips_alerts).count()

    # Alerts by severity
    alerts_by_severity = {}
    for severity in ["critical", "high", "medium", "low"]:
        count = db(db.ips_alerts.severity == severity).count()
        alerts_by_severity[severity] = count

    # Top signatures (by hit count in rules)
    top_rules = db(db.ips_rules).select(
        orderby=~db.ips_rules.hit_count,
        limitby=(0, 10)
    )

    # Top source IPs (by alert count)
    top_source_ips = {}
    all_alerts = db(db.ips_alerts).select()
    for alert in all_alerts:
        if alert.source_ip:
            top_source_ips[alert.source_ip] = top_source_ips.get(alert.source_ip, 0) + 1

    # Sort and limit top source IPs
    sorted_ips = sorted(top_source_ips.items(), key=lambda x: x[1], reverse=True)[:10]
    top_source_ips_dict = {ip: count for ip, count in sorted_ips}

    # Active rules count
    active_rules = db(db.ips_rules.is_active == True).count()
    total_rules = db(db.ips_rules).count()

    # Active categories count
    active_categories = db(db.ips_categories.is_active == True).count()
    total_categories = db(db.ips_categories).count()

    return jsonify({
        "total_alerts": total_alerts,
        "alerts_by_severity": alerts_by_severity,
        "top_signatures": [
            {
                "sid": r.sid,
                "message": r.message,
                "hit_count": r.hit_count,
                "severity": r.severity
            }
            for r in top_rules
        ],
        "top_source_ips": top_source_ips_dict,
        "active_rules": active_rules,
        "total_rules": total_rules,
        "active_categories": active_categories,
        "total_categories": total_categories
    })
