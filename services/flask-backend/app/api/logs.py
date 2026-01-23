"""Logs API Endpoints - OpenSearch Integration."""

import os
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List
from functools import wraps

from flask import Blueprint, request, jsonify, g
from opensearchpy import OpenSearch, NotFoundError, ConnectionError as OSConnectionError

logs_bp = Blueprint("logs", __name__)


def require_auth(f):
    """Decorator to require authentication."""
    @wraps(f)
    def decorated(*args, **kwargs):
        if not hasattr(g, "current_user") or g.current_user is None:
            return jsonify({"error": "Authentication required"}), 401
        return f(*args, **kwargs)
    return decorated


class OpenSearchClient:
    """OpenSearch client wrapper with connection pooling."""

    _instance = None

    def __new__(cls):
        """Singleton pattern for OpenSearch client."""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialize()
        return cls._instance

    def _initialize(self):
        """Initialize OpenSearch connection."""
        self.host = os.getenv("OPENSEARCH_HOST", "localhost")
        self.port = int(os.getenv("OPENSEARCH_PORT", "9200"))
        self.user = os.getenv("OPENSEARCH_USER", "admin")
        self.password = os.getenv("OPENSEARCH_PASSWORD", "admin")
        self.use_ssl = os.getenv("OPENSEARCH_USE_SSL", "true").lower() == "true"
        self.verify_certs = os.getenv("OPENSEARCH_VERIFY_CERTS", "false").lower() == "true"

        self.client = OpenSearch(
            hosts=[{"host": self.host, "port": self.port}],
            http_auth=(self.user, self.password),
            use_ssl=self.use_ssl,
            verify_certs=self.verify_certs,
            ssl_show_warn=False,
            timeout=30,
            max_retries=3,
            retry_on_timeout=True,
        )

    def search(self, index: str, query: Dict[str, Any], size: int = 100, from_: int = 0) -> Dict:
        """Execute a search query."""
        try:
            return self.client.search(index=index, body=query, size=size, from_=from_)
        except (OSConnectionError, Exception) as e:
            raise Exception(f"OpenSearch error: {str(e)}")

    def get_indices(self, pattern: str = "*") -> Dict:
        """List indices matching pattern."""
        try:
            return self.client.indices.get_alias(index=pattern)
        except (OSConnectionError, Exception) as e:
            raise Exception(f"OpenSearch error: {str(e)}")

    def get_index_stats(self, index: str) -> Dict:
        """Get statistics for an index."""
        try:
            stats = self.client.indices.stats(index=index)
            return stats
        except NotFoundError:
            return {"indices": {}}
        except (OSConnectionError, Exception) as e:
            raise Exception(f"OpenSearch error: {str(e)}")


# =============================================================================
# Generic Search Endpoint
# =============================================================================

@logs_bp.route("/search", methods=["GET"])
@require_auth
def search_logs():
    """
    Search logs across all indices with query and filters.

    Query parameters:
    - q: Search query (KQL or simple text search)
    - indices: Comma-separated list of index patterns (default: *)
    - start_time: Start timestamp (ISO 8601 or relative like -24h)
    - end_time: End timestamp (ISO 8601 or relative like now)
    - size: Number of results (default: 100, max: 10000)
    - from: Offset for pagination (default: 0)
    - sort: Sort field and direction (e.g., timestamp:desc)
    """
    try:
        # Extract parameters
        query_str = request.args.get("q", "*")
        indices = request.args.get("indices", "*")
        size = min(int(request.args.get("size", 100)), 10000)
        from_ = int(request.args.get("from", 0))
        sort = request.args.get("sort", "timestamp:desc")
        start_time = request.args.get("start_time", "now-24h")
        end_time = request.args.get("end_time", "now")

        # Build query
        query_body = {
            "query": {
                "bool": {
                    "must": [
                        {
                            "multi_match": {
                                "query": query_str,
                                "fields": ["*"],
                                "fuzziness": "AUTO",
                            }
                        }
                    ],
                    "filter": [
                        {
                            "range": {
                                "timestamp": {
                                    "gte": start_time,
                                    "lte": end_time,
                                }
                            }
                        }
                    ],
                }
            },
            "sort": [{"timestamp": {"order": sort.split(":")[1] if ":" in sort else "desc"}}],
        }

        client = OpenSearchClient()
        results = client.search(indices, query_body, size=size, from_=from_)

        return jsonify({
            "query": query_str,
            "indices": indices,
            "total": results["hits"]["total"]["value"],
            "size": size,
            "from": from_,
            "hits": results["hits"]["hits"],
            "took_ms": results["took"],
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# =============================================================================
# IPS Logs Endpoint
# =============================================================================

@logs_bp.route("/ips", methods=["GET"])
@require_auth
def get_ips_logs():
    """
    Get IPS logs and alerts from cerberus-ips-* indices.

    Query parameters:
    - severity: Filter by severity (alert, high, medium, low)
    - action: Filter by action (alert, drop, pass, reject)
    - source_ip: Filter by source IP
    - dest_ip: Filter by destination IP
    - protocol: Filter by protocol
    - start_time: Start timestamp (default: -24h)
    - end_time: End timestamp (default: now)
    - size: Number of results (default: 100)
    - from: Offset for pagination (default: 0)
    """
    try:
        severity = request.args.get("severity")
        action = request.args.get("action")
        source_ip = request.args.get("source_ip")
        dest_ip = request.args.get("dest_ip")
        protocol = request.args.get("protocol")
        size = min(int(request.args.get("size", 100)), 10000)
        from_ = int(request.args.get("from", 0))
        start_time = request.args.get("start_time", "now-24h")
        end_time = request.args.get("end_time", "now")

        # Build filters
        filters = [
            {
                "range": {
                    "timestamp": {
                        "gte": start_time,
                        "lte": end_time,
                    }
                }
            }
        ]

        if severity:
            filters.append({"term": {"severity": severity}})
        if action:
            filters.append({"term": {"action": action}})
        if source_ip:
            filters.append({"term": {"source_ip": source_ip}})
        if dest_ip:
            filters.append({"term": {"dest_ip": dest_ip}})
        if protocol:
            filters.append({"term": {"protocol": protocol}})

        query_body = {
            "query": {
                "bool": {
                    "filter": filters
                }
            },
            "sort": [{"timestamp": {"order": "desc"}}],
        }

        client = OpenSearchClient()
        results = client.search("cerberus-ips-*", query_body, size=size, from_=from_)

        return jsonify({
            "index": "cerberus-ips-*",
            "total": results["hits"]["total"]["value"],
            "size": size,
            "from": from_,
            "hits": results["hits"]["hits"],
            "filters": {
                "severity": severity,
                "action": action,
                "source_ip": source_ip,
                "dest_ip": dest_ip,
                "protocol": protocol,
                "start_time": start_time,
                "end_time": end_time,
            },
            "took_ms": results["took"],
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# =============================================================================
# VPN Logs Endpoint
# =============================================================================

@logs_bp.route("/vpn", methods=["GET"])
@require_auth
def get_vpn_logs():
    """
    Get VPN logs from cerberus-vpn-* indices.

    Query parameters:
    - status: Filter by status (connected, disconnected, failed, authenticating)
    - user: Filter by username
    - vpn_type: Filter by VPN type (wireguard, ipsec, openvpn)
    - client_ip: Filter by client IP
    - start_time: Start timestamp (default: -24h)
    - end_time: End timestamp (default: now)
    - size: Number of results (default: 100)
    - from: Offset for pagination (default: 0)
    """
    try:
        status = request.args.get("status")
        user = request.args.get("user")
        vpn_type = request.args.get("vpn_type")
        client_ip = request.args.get("client_ip")
        size = min(int(request.args.get("size", 100)), 10000)
        from_ = int(request.args.get("from", 0))
        start_time = request.args.get("start_time", "now-24h")
        end_time = request.args.get("end_time", "now")

        # Build filters
        filters = [
            {
                "range": {
                    "timestamp": {
                        "gte": start_time,
                        "lte": end_time,
                    }
                }
            }
        ]

        if status:
            filters.append({"term": {"status": status}})
        if user:
            filters.append({"term": {"username": user}})
        if vpn_type:
            filters.append({"term": {"vpn_type": vpn_type}})
        if client_ip:
            filters.append({"term": {"client_ip": client_ip}})

        query_body = {
            "query": {
                "bool": {
                    "filter": filters
                }
            },
            "sort": [{"timestamp": {"order": "desc"}}],
        }

        client = OpenSearchClient()
        results = client.search("cerberus-vpn-*", query_body, size=size, from_=from_)

        return jsonify({
            "index": "cerberus-vpn-*",
            "total": results["hits"]["total"]["value"],
            "size": size,
            "from": from_,
            "hits": results["hits"]["hits"],
            "filters": {
                "status": status,
                "user": user,
                "vpn_type": vpn_type,
                "client_ip": client_ip,
                "start_time": start_time,
                "end_time": end_time,
            },
            "took_ms": results["took"],
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# =============================================================================
# Content Filter Logs Endpoint
# =============================================================================

@logs_bp.route("/filter", methods=["GET"])
@require_auth
def get_filter_logs():
    """
    Get content filter logs from cerberus-filter-* indices.

    Query parameters:
    - category: Filter by category (malware, phishing, adult, etc.)
    - action: Filter by action (block, allow, log)
    - user: Filter by username
    - domain: Filter by domain accessed
    - source_ip: Filter by source IP
    - start_time: Start timestamp (default: -24h)
    - end_time: End timestamp (default: now)
    - size: Number of results (default: 100)
    - from: Offset for pagination (default: 0)
    """
    try:
        category = request.args.get("category")
        action = request.args.get("action")
        user = request.args.get("user")
        domain = request.args.get("domain")
        source_ip = request.args.get("source_ip")
        size = min(int(request.args.get("size", 100)), 10000)
        from_ = int(request.args.get("from", 0))
        start_time = request.args.get("start_time", "now-24h")
        end_time = request.args.get("end_time", "now")

        # Build filters
        filters = [
            {
                "range": {
                    "timestamp": {
                        "gte": start_time,
                        "lte": end_time,
                    }
                }
            }
        ]

        if category:
            filters.append({"term": {"category": category}})
        if action:
            filters.append({"term": {"action": action}})
        if user:
            filters.append({"term": {"username": user}})
        if domain:
            filters.append({"wildcard": {"domain": f"*{domain}*"}})
        if source_ip:
            filters.append({"term": {"source_ip": source_ip}})

        query_body = {
            "query": {
                "bool": {
                    "filter": filters
                }
            },
            "sort": [{"timestamp": {"order": "desc"}}],
        }

        client = OpenSearchClient()
        results = client.search("cerberus-filter-*", query_body, size=size, from_=from_)

        return jsonify({
            "index": "cerberus-filter-*",
            "total": results["hits"]["total"]["value"],
            "size": size,
            "from": from_,
            "hits": results["hits"]["hits"],
            "filters": {
                "category": category,
                "action": action,
                "user": user,
                "domain": domain,
                "source_ip": source_ip,
                "start_time": start_time,
                "end_time": end_time,
            },
            "took_ms": results["took"],
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# =============================================================================
# Audit Logs Endpoint
# =============================================================================

@logs_bp.route("/audit", methods=["GET"])
@require_auth
def get_audit_logs():
    """
    Get audit logs from cerberus-audit-* indices.

    Query parameters:
    - action: Filter by action (create, update, delete, login, logout, config_change)
    - user: Filter by username
    - resource_type: Filter by resource type
    - start_time: Start timestamp (default: -30d)
    - end_time: End timestamp (default: now)
    - size: Number of results (default: 100)
    - from: Offset for pagination (default: 0)
    """
    try:
        action = request.args.get("action")
        user = request.args.get("user")
        resource_type = request.args.get("resource_type")
        size = min(int(request.args.get("size", 100)), 10000)
        from_ = int(request.args.get("from", 0))
        start_time = request.args.get("start_time", "now-30d")
        end_time = request.args.get("end_time", "now")

        # Build filters
        filters = [
            {
                "range": {
                    "timestamp": {
                        "gte": start_time,
                        "lte": end_time,
                    }
                }
            }
        ]

        if action:
            filters.append({"term": {"action": action}})
        if user:
            filters.append({"term": {"username": user}})
        if resource_type:
            filters.append({"term": {"resource_type": resource_type}})

        query_body = {
            "query": {
                "bool": {
                    "filter": filters
                }
            },
            "sort": [{"timestamp": {"order": "desc"}}],
        }

        client = OpenSearchClient()
        results = client.search("cerberus-audit-*", query_body, size=size, from_=from_)

        return jsonify({
            "index": "cerberus-audit-*",
            "total": results["hits"]["total"]["value"],
            "size": size,
            "from": from_,
            "hits": results["hits"]["hits"],
            "filters": {
                "action": action,
                "user": user,
                "resource_type": resource_type,
                "start_time": start_time,
                "end_time": end_time,
            },
            "took_ms": results["took"],
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# =============================================================================
# Proxy Logs Endpoint
# =============================================================================

@logs_bp.route("/proxy", methods=["GET"])
@require_auth
def get_proxy_logs():
    """
    Get proxy logs from marchproxy-* indices.

    Query parameters:
    - source_ip: Filter by source IP
    - dest_ip: Filter by destination IP
    - method: Filter by HTTP method (GET, POST, etc.)
    - status_code: Filter by HTTP status code
    - uri: Filter by URI
    - user: Filter by authenticated user
    - start_time: Start timestamp (default: -24h)
    - end_time: End timestamp (default: now)
    - size: Number of results (default: 100)
    - from: Offset for pagination (default: 0)
    """
    try:
        source_ip = request.args.get("source_ip")
        dest_ip = request.args.get("dest_ip")
        method = request.args.get("method")
        status_code = request.args.get("status_code")
        uri = request.args.get("uri")
        user = request.args.get("user")
        size = min(int(request.args.get("size", 100)), 10000)
        from_ = int(request.args.get("from", 0))
        start_time = request.args.get("start_time", "now-24h")
        end_time = request.args.get("end_time", "now")

        # Build filters
        filters = [
            {
                "range": {
                    "timestamp": {
                        "gte": start_time,
                        "lte": end_time,
                    }
                }
            }
        ]

        if source_ip:
            filters.append({"term": {"source_ip": source_ip}})
        if dest_ip:
            filters.append({"term": {"dest_ip": dest_ip}})
        if method:
            filters.append({"term": {"method": method}})
        if status_code:
            filters.append({"term": {"status_code": int(status_code)}})
        if uri:
            filters.append({"wildcard": {"uri": f"*{uri}*"}})
        if user:
            filters.append({"term": {"username": user}})

        query_body = {
            "query": {
                "bool": {
                    "filter": filters
                }
            },
            "sort": [{"timestamp": {"order": "desc"}}],
        }

        client = OpenSearchClient()
        results = client.search("marchproxy-*", query_body, size=size, from_=from_)

        return jsonify({
            "index": "marchproxy-*",
            "total": results["hits"]["total"]["value"],
            "size": size,
            "from": from_,
            "hits": results["hits"]["hits"],
            "filters": {
                "source_ip": source_ip,
                "dest_ip": dest_ip,
                "method": method,
                "status_code": status_code,
                "uri": uri,
                "user": user,
                "start_time": start_time,
                "end_time": end_time,
            },
            "took_ms": results["took"],
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# =============================================================================
# Indices Management Endpoint
# =============================================================================

@logs_bp.route("/indices", methods=["GET"])
@require_auth
def list_indices():
    """
    List available log indices.

    Query parameters:
    - pattern: Index pattern filter (default: *)
    """
    try:
        pattern = request.args.get("pattern", "*")

        client = OpenSearchClient()
        indices_data = client.get_indices(pattern)

        indices_list = []
        for index_name in indices_data.get("indices", {}).keys():
            if index_name.startswith("."):
                continue  # Skip system indices
            indices_list.append({
                "name": index_name,
                "pattern_match": any(
                    p in index_name for p in ["cerberus-ips", "cerberus-vpn", "cerberus-filter",
                                               "cerberus-audit", "marchproxy"]
                )
            })

        return jsonify({
            "pattern": pattern,
            "indices": sorted(indices_list, key=lambda x: x["name"]),
            "total": len(indices_list),
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500


# =============================================================================
# Statistics Endpoint
# =============================================================================

@logs_bp.route("/stats", methods=["GET"])
@require_auth
def get_stats():
    """
    Get log statistics across indices.

    Query parameters:
    - indices: Comma-separated list of index patterns to analyze
    """
    try:
        indices_param = request.args.get("indices", "cerberus-*,marchproxy-*")
        index_list = [idx.strip() for idx in indices_param.split(",")]

        client = OpenSearchClient()
        stats = {}

        for index_pattern in index_list:
            try:
                index_stats = client.get_index_stats(index_pattern)
                if "indices" in index_stats and index_stats["indices"]:
                    for idx_name, idx_data in index_stats["indices"].items():
                        stats[idx_name] = {
                            "docs": idx_data.get("primaries", {}).get("docs", {}).get("count", 0),
                            "size_bytes": idx_data.get("primaries", {}).get("store", {}).get("size_in_bytes", 0),
                            "size_gb": round(
                                idx_data.get("primaries", {}).get("store", {}).get("size_in_bytes", 0) / (1024**3),
                                2
                            ),
                        }
            except Exception:
                pass  # Continue with other indices if one fails

        return jsonify({
            "indices_requested": index_list,
            "statistics": stats,
            "total_docs": sum(s["docs"] for s in stats.values()),
            "total_size_gb": round(sum(s["size_bytes"] for s in stats.values()) / (1024**3), 2),
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500
