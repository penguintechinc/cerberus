"""License Server Integration via penguin-licensing."""

import logging
import os

logger = logging.getLogger(__name__)

# License server configuration
LICENSE_SERVER_URL = os.getenv("LICENSE_SERVER_URL", "https://license.penguintech.io")
LICENSE_KEY = os.getenv("LICENSE_KEY", "")
PRODUCT_NAME = os.getenv("PRODUCT_NAME", "cerberus")

try:
    from penguin_licensing.flask import license_required, feature_required
    from penguin_licensing.client import LicenseClient

    _license_client = LicenseClient(
        server_url=LICENSE_SERVER_URL,
        license_key=LICENSE_KEY,
        product=PRODUCT_NAME,
    ) if LICENSE_KEY else None

    LICENSE_AVAILABLE = True
except ImportError:
    LICENSE_AVAILABLE = False
    _license_client = None

    def license_required(f):
        """No-op decorator when penguin-licensing is not installed."""
        return f

    def feature_required(feature_name):
        """No-op decorator when penguin-licensing is not installed."""
        def decorator(f):
            return f
        return decorator


def get_license_client():
    """Get the license client instance."""
    return _license_client


def validate_license() -> dict:
    """Validate current license and return status."""
    if not LICENSE_AVAILABLE or not _license_client:
        return {"valid": False, "reason": "License client not configured"}
    try:
        return _license_client.validate()
    except Exception as e:
        logger.warning("License validation failed: %s", e)
        return {"valid": False, "reason": str(e)}


def check_feature(feature_name: str) -> bool:
    """Check if a specific feature is licensed."""
    if not LICENSE_AVAILABLE or not _license_client:
        return True  # Allow all features when no license server
    try:
        return _license_client.check_feature(feature_name)
    except Exception:
        return False
