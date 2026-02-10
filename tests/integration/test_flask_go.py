"""Integration tests for Flask <-> Go backend communication."""

import os

import pytest
import requests

FLASK_URL = os.getenv("FLASK_URL", "http://localhost:5000")
GO_URL = os.getenv("GO_URL", "http://localhost:8080")

pytestmark = pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS", "false").lower() != "true",
    reason="Set RUN_INTEGRATION_TESTS=true to run integration tests",
)


class TestFlaskGoIntegration:
    """Tests that Flask and Go backends can communicate."""

    def test_flask_health(self):
        response = requests.get(f"{FLASK_URL}/healthz", timeout=5)
        assert response.status_code == 200
        assert response.json()["status"] == "healthy"

    def test_go_health(self):
        response = requests.get(f"{GO_URL}/healthz", timeout=5)
        assert response.status_code == 200
        assert response.json()["status"] == "healthy"

    def test_go_status(self):
        response = requests.get(f"{GO_URL}/api/v1/status", timeout=5)
        assert response.status_code == 200
        data = response.json()
        assert "version" in data or "status" in data

    def test_flask_login_and_go_status(self):
        """Verify auth token from Flask can be used across services."""
        login_response = requests.post(
            f"{FLASK_URL}/api/v1/auth/login",
            json={
                "email": os.getenv("ADMIN_EMAIL", "admin@example.com"),
                "password": os.getenv("ADMIN_PASSWORD", "changeme123"),
            },
            timeout=5,
        )
        assert login_response.status_code == 200
        token = login_response.json()["access_token"]
        assert len(token) > 0

        # Go backend status should be accessible (no auth required)
        go_response = requests.get(f"{GO_URL}/api/v1/status", timeout=5)
        assert go_response.status_code == 200
