"""Cerberus NGFW API Endpoints."""

from flask import Blueprint

from .firewall import firewall_bp
from .ips import ips_bp
from .xdp import xdp_bp
from .vpn import vpn_bp
from .filter import filter_bp
from .logs import logs_bp
from .proxy import proxy_bp


def register_api_blueprints(app):
    """Register all API blueprints with the Flask app."""
    api_prefix = "/api/v1"

    app.register_blueprint(firewall_bp, url_prefix=f"{api_prefix}/firewall")
    app.register_blueprint(ips_bp, url_prefix=f"{api_prefix}/ips")
    app.register_blueprint(xdp_bp, url_prefix=f"{api_prefix}/xdp")
    app.register_blueprint(vpn_bp, url_prefix=f"{api_prefix}/vpn")
    app.register_blueprint(filter_bp, url_prefix=f"{api_prefix}/filter")
    app.register_blueprint(logs_bp, url_prefix=f"{api_prefix}/logs")
    app.register_blueprint(proxy_bp, url_prefix=f"{api_prefix}/proxy")
