"""MarchProxy API Bridge Endpoints."""

import os
import logging
from flask import Blueprint, request, jsonify, g
from functools import wraps
import requests

proxy_bp = Blueprint("proxy", __name__)
logger = logging.getLogger(__name__)

# Get MarchProxy API URL from environment
MARCHPROXY_API_URL = os.getenv("MARCHPROXY_API_URL", "http://marchproxy:8080")


def require_auth(f):
    """Decorator to require authentication."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not hasattr(g, "current_user") or g.current_user is None:
            return jsonify({"error": "Authentication required"}), 401
        return f(*args, **kwargs)
    return decorated


def get_auth_headers():
    """Extract and prepare authentication headers for forwarding."""
    headers = {}

    # Forward Authorization header if present
    if "Authorization" in request.headers:
        headers["Authorization"] = request.headers["Authorization"]

    # Forward common headers
    if "User-Agent" in request.headers:
        headers["User-Agent"] = request.headers["User-Agent"]

    headers["Content-Type"] = "application/json"
    return headers


def proxy_request(method, endpoint, data=None, params=None):
    """Forward request to MarchProxy API and handle response."""
    try:
        url = f"{MARCHPROXY_API_URL}{endpoint}"
        headers = get_auth_headers()

        logger.info(f"Proxying {method} request to {url}")

        if method == "GET":
            response = requests.get(url, headers=headers, params=params, timeout=10)
        elif method == "POST":
            response = requests.post(url, headers=headers, json=data, params=params, timeout=10)
        elif method == "PUT":
            response = requests.put(url, headers=headers, json=data, params=params, timeout=10)
        elif method == "DELETE":
            response = requests.delete(url, headers=headers, params=params, timeout=10)
        else:
            return jsonify({"error": f"Unsupported HTTP method: {method}"}), 400

        # Forward response status and body
        try:
            return jsonify(response.json()), response.status_code
        except ValueError:
            return response.text, response.status_code

    except requests.exceptions.ConnectionError as e:
        logger.error(f"Connection error to MarchProxy: {e}")
        return jsonify({"error": "MarchProxy service unavailable"}), 503
    except requests.exceptions.Timeout as e:
        logger.error(f"Timeout connecting to MarchProxy: {e}")
        return jsonify({"error": "MarchProxy request timeout"}), 504
    except Exception as e:
        logger.error(f"Error proxying request to MarchProxy: {e}")
        return jsonify({"error": f"Proxy error: {str(e)}"}), 500


# =============================================================================
# Service Endpoints
# =============================================================================

@proxy_bp.route("/services", methods=["GET"])
@require_auth
def list_services():
    """List all proxy services from MarchProxy."""
    return proxy_request("GET", "/services")


@proxy_bp.route("/services", methods=["POST"])
@require_auth
def create_service():
    """Create a new proxy service in MarchProxy."""
    data = request.get_json()

    if not data or not data.get("name"):
        return jsonify({"error": "Service name is required"}), 400

    return proxy_request("POST", "/services", data=data)


@proxy_bp.route("/services/<service_id>", methods=["GET"])
@require_auth
def get_service(service_id):
    """Get a specific proxy service from MarchProxy."""
    return proxy_request("GET", f"/services/{service_id}")


@proxy_bp.route("/services/<service_id>", methods=["PUT"])
@require_auth
def update_service(service_id):
    """Update a proxy service in MarchProxy."""
    data = request.get_json()
    return proxy_request("PUT", f"/services/{service_id}", data=data)


@proxy_bp.route("/services/<service_id>", methods=["DELETE"])
@require_auth
def delete_service(service_id):
    """Delete a proxy service from MarchProxy."""
    return proxy_request("DELETE", f"/services/{service_id}")


# =============================================================================
# Cluster Endpoints
# =============================================================================

@proxy_bp.route("/clusters", methods=["GET"])
@require_auth
def list_clusters():
    """List all clusters from MarchProxy."""
    return proxy_request("GET", "/clusters")


# =============================================================================
# Service Mapping Endpoints
# =============================================================================

@proxy_bp.route("/mappings", methods=["GET"])
@require_auth
def list_mappings():
    """List all service mappings from MarchProxy."""
    return proxy_request("GET", "/mappings")


@proxy_bp.route("/mappings", methods=["POST"])
@require_auth
def create_mapping():
    """Create a new service mapping in MarchProxy."""
    data = request.get_json()

    if not data or not data.get("service_id"):
        return jsonify({"error": "service_id is required"}), 400

    return proxy_request("POST", "/mappings", data=data)


@proxy_bp.route("/mappings/<mapping_id>", methods=["DELETE"])
@require_auth
def delete_mapping(mapping_id):
    """Delete a service mapping from MarchProxy."""
    return proxy_request("DELETE", f"/mappings/{mapping_id}")


# =============================================================================
# Status Endpoints
# =============================================================================

@proxy_bp.route("/status", methods=["GET"])
@require_auth
def get_proxy_status():
    """Get the current status of the MarchProxy service."""
    return proxy_request("GET", "/status")
