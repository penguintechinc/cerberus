"""Content Filter API Endpoints."""

from datetime import datetime
from flask import Blueprint, request, jsonify, g
from functools import wraps
from collections import defaultdict

from ..models import get_db

filter_bp = Blueprint("filter", __name__)


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
# URL Categories Endpoints
# =============================================================================

@filter_bp.route("/categories", methods=["GET"])
@require_auth
def list_categories():
    """List all URL categories."""
    db = get_db()
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 50, type=int)
    is_blocked = request.args.get("is_blocked", type=lambda x: x.lower() == "true")

    query = db.url_categories
    if is_blocked is not None:
        query = db.url_categories.is_blocked == is_blocked

    offset = (page - 1) * per_page
    categories = db(query).select(
        orderby=db.url_categories.name,
        limitby=(offset, offset + per_page),
    )
    total = db(query).count()

    return jsonify({
        "categories": [c.as_dict() for c in categories],
        "total": total,
        "page": page,
        "per_page": per_page,
        "pages": (total + per_page - 1) // per_page
    })


@filter_bp.route("/categories", methods=["POST"])
@require_auth
def create_category():
    """Create a new URL category."""
    db = get_db()
    data = request.get_json()

    if not data or not data.get("name"):
        return jsonify({"error": "Category name is required"}), 400

    existing = db(db.url_categories.name == data["name"]).select().first()
    if existing:
        return jsonify({"error": "Category name already exists"}), 409

    category_id = db.url_categories.insert(
        name=data["name"],
        description=data.get("description"),
        is_blocked=data.get("is_blocked", False),
        log_enabled=data.get("log_enabled", True),
    )
    db.commit()

    category = db.url_categories[category_id]
    audit_log("create", "url_category", category_id, data["name"],
              new_value=category.as_dict())

    return jsonify({"category": category.as_dict()}), 201


@filter_bp.route("/categories/<int:category_id>", methods=["GET"])
@require_auth
def get_category(category_id: int):
    """Get a specific URL category."""
    db = get_db()
    category = db.url_categories[category_id]
    if not category:
        return jsonify({"error": "Category not found"}), 404
    return jsonify({"category": category.as_dict()})


@filter_bp.route("/categories/<int:category_id>", methods=["PUT"])
@require_auth
def update_category(category_id: int):
    """Update a URL category."""
    db = get_db()
    category = db.url_categories[category_id]
    if not category:
        return jsonify({"error": "Category not found"}), 404

    data = request.get_json()
    old_value = category.as_dict()

    allowed_fields = {"name", "description", "is_blocked", "log_enabled"}
    update_data = {k: v for k, v in data.items() if k in allowed_fields}

    if update_data:
        # Check for name uniqueness if updating name
        if "name" in update_data and update_data["name"] != category.name:
            existing = db(db.url_categories.name == update_data["name"]).select().first()
            if existing:
                return jsonify({"error": "Category name already exists"}), 409

        category.update_record(**update_data)
        db.commit()

    category = db.url_categories[category_id]
    audit_log("update", "url_category", category_id, category.name,
              old_value=old_value, new_value=category.as_dict())

    return jsonify({"category": category.as_dict()})


@filter_bp.route("/categories/<int:category_id>", methods=["DELETE"])
@require_auth
def delete_category(category_id: int):
    """Delete a URL category."""
    db = get_db()
    category = db.url_categories[category_id]
    if not category:
        return jsonify({"error": "Category not found"}), 404

    # Check if category is used in any filter policies
    policies_using_category = db(
        db.filter_policies.blocked_categories.contains(str(category_id))
    ).count()

    if policies_using_category > 0:
        return jsonify({
            "error": f"Cannot delete category: {policies_using_category} filter policies reference it"
        }), 409

    category_name = category.name
    old_value = category.as_dict()
    db(db.url_categories.id == category_id).delete()
    db.commit()

    audit_log("delete", "url_category", category_id, category_name,
              old_value=old_value)

    return jsonify({"message": "Category deleted"})


# =============================================================================
# Filter Policies Endpoints
# =============================================================================

@filter_bp.route("/policies", methods=["GET"])
@require_auth
def list_policies():
    """List all filter policies."""
    db = get_db()
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 50, type=int)
    is_active = request.args.get("is_active", type=lambda x: x.lower() == "true")

    query = db.filter_policies
    if is_active is not None:
        query = db.filter_policies.is_active == is_active

    offset = (page - 1) * per_page
    policies = db(query).select(
        orderby=db.filter_policies.priority,
        limitby=(offset, offset + per_page),
    )
    total = db(query).count()

    return jsonify({
        "policies": [p.as_dict() for p in policies],
        "total": total,
        "page": page,
        "per_page": per_page,
        "pages": (total + per_page - 1) // per_page
    })


@filter_bp.route("/policies", methods=["POST"])
@require_auth
def create_policy():
    """Create a new filter policy."""
    db = get_db()
    data = request.get_json()

    if not data or not data.get("name"):
        return jsonify({"error": "Policy name is required"}), 400

    existing = db(db.filter_policies.name == data["name"]).select().first()
    if existing:
        return jsonify({"error": "Policy name already exists"}), 409

    policy_id = db.filter_policies.insert(
        name=data["name"],
        description=data.get("description"),
        priority=data.get("priority", 100),
        source_zone=data.get("source_zone"),
        blocked_categories=data.get("blocked_categories", []),
        allowed_domains=data.get("allowed_domains", []),
        blocked_domains=data.get("blocked_domains", []),
        safe_search_enabled=data.get("safe_search_enabled", False),
        ssl_inspection_enabled=data.get("ssl_inspection_enabled", False),
        log_enabled=data.get("log_enabled", True),
        is_active=data.get("is_active", True),
        created_by=getattr(g, "current_user", {}).get("id"),
    )
    db.commit()

    policy = db.filter_policies[policy_id]
    audit_log("create", "filter_policy", policy_id, data["name"],
              new_value=policy.as_dict())

    return jsonify({"policy": policy.as_dict()}), 201


@filter_bp.route("/policies/<int:policy_id>", methods=["GET"])
@require_auth
def get_policy(policy_id: int):
    """Get a specific filter policy."""
    db = get_db()
    policy = db.filter_policies[policy_id]
    if not policy:
        return jsonify({"error": "Policy not found"}), 404
    return jsonify({"policy": policy.as_dict()})


@filter_bp.route("/policies/<int:policy_id>", methods=["PUT"])
@require_auth
def update_policy(policy_id: int):
    """Update a filter policy."""
    db = get_db()
    policy = db.filter_policies[policy_id]
    if not policy:
        return jsonify({"error": "Policy not found"}), 404

    data = request.get_json()
    old_value = policy.as_dict()

    allowed_fields = {
        "name", "description", "priority", "source_zone", "blocked_categories",
        "allowed_domains", "blocked_domains", "safe_search_enabled",
        "ssl_inspection_enabled", "log_enabled", "is_active"
    }
    update_data = {k: v for k, v in data.items() if k in allowed_fields}

    if update_data:
        # Check for name uniqueness if updating name
        if "name" in update_data and update_data["name"] != policy.name:
            existing = db(db.filter_policies.name == update_data["name"]).select().first()
            if existing:
                return jsonify({"error": "Policy name already exists"}), 409

        policy.update_record(**update_data)
        db.commit()

    policy = db.filter_policies[policy_id]
    audit_log("update", "filter_policy", policy_id, policy.name,
              old_value=old_value, new_value=policy.as_dict())

    return jsonify({"policy": policy.as_dict()})


@filter_bp.route("/policies/<int:policy_id>", methods=["DELETE"])
@require_auth
def delete_policy(policy_id: int):
    """Delete a filter policy."""
    db = get_db()
    policy = db.filter_policies[policy_id]
    if not policy:
        return jsonify({"error": "Policy not found"}), 404

    policy_name = policy.name
    old_value = policy.as_dict()
    db(db.filter_policies.id == policy_id).delete()
    db.commit()

    audit_log("delete", "filter_policy", policy_id, policy_name,
              old_value=old_value)

    return jsonify({"message": "Policy deleted"})


@filter_bp.route("/policies/<int:policy_id>/toggle", methods=["POST"])
@require_auth
def toggle_policy(policy_id: int):
    """Toggle the active status of a filter policy."""
    db = get_db()
    policy = db.filter_policies[policy_id]
    if not policy:
        return jsonify({"error": "Policy not found"}), 404

    old_value = policy.as_dict()
    new_active_status = not policy.is_active
    policy.update_record(is_active=new_active_status)
    db.commit()

    policy = db.filter_policies[policy_id]
    audit_log("update", "filter_policy", policy_id, policy.name,
              old_value=old_value, new_value=policy.as_dict())

    return jsonify({
        "policy": policy.as_dict(),
        "message": f"Policy {'activated' if new_active_status else 'deactivated'}"
    })


# =============================================================================
# Filtering Statistics Endpoints
# =============================================================================

@filter_bp.route("/stats", methods=["GET"])
@require_auth
def get_stats():
    """Get filtering statistics (blocks by category, top blocked domains)."""
    db = get_db()

    # Get counts by category
    categories = db(db.url_categories.is_blocked == True).select()
    category_stats = {}
    total_blocks = 0

    for category in categories:
        count = db(
            (db.ips_alerts.category == category.name) &
            (db.ips_alerts.action_taken == "block")
        ).count()
        if count > 0:
            category_stats[category.name] = count
            total_blocks += count

    # Sort by count descending
    sorted_categories = sorted(
        category_stats.items(),
        key=lambda x: x[1],
        reverse=True
    )

    # Get top 10 blocked domains (from source IPs in alerts)
    alerts = db(db.ips_alerts.action_taken == "block").select()
    domain_blocks = defaultdict(int)

    for alert in alerts:
        if alert.dest_ip:
            domain_blocks[alert.dest_ip] += 1

    top_domains = sorted(
        domain_blocks.items(),
        key=lambda x: x[1],
        reverse=True
    )[:10]

    # Get active policy count
    active_policies = db(db.filter_policies.is_active == True).count()

    # Get active category count
    active_categories = db(db.url_categories.is_blocked == True).count()

    return jsonify({
        "total_blocks": total_blocks,
        "active_policies": active_policies,
        "active_categories": active_categories,
        "blocks_by_category": [
            {"category": cat, "blocks": count}
            for cat, count in sorted_categories
        ],
        "top_blocked_domains": [
            {"domain": domain, "blocks": count}
            for domain, count in top_domains
        ]
    })
