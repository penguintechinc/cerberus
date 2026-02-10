"""Shared test fixtures for API tests."""

import os
import sys

import pytest

# Add Flask backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../services/flask-backend"))

from app import create_app
from app.auth import hash_password
from app.config import TestingConfig
from app.models import create_user, get_db, init_db


@pytest.fixture(scope="session")
def app():
    """Create application for testing."""
    app = create_app(TestingConfig)
    yield app


@pytest.fixture
def client(app):
    """Create test client."""
    with app.test_client() as client:
        with app.app_context():
            yield client


@pytest.fixture
def admin_user(app):
    """Create admin user and return credentials."""
    with app.app_context():
        user = create_user(
            email="admin@test.com",
            password_hash=hash_password("adminpass123"),
            full_name="Test Admin",
            role="admin",
        )
        return {
            "id": user["id"],
            "email": "admin@test.com",
            "password": "adminpass123",
            "role": "admin",
        }


@pytest.fixture
def viewer_user(app):
    """Create viewer user and return credentials."""
    with app.app_context():
        user = create_user(
            email="viewer@test.com",
            password_hash=hash_password("viewerpass123"),
            full_name="Test Viewer",
            role="viewer",
        )
        return {
            "id": user["id"],
            "email": "viewer@test.com",
            "password": "viewerpass123",
            "role": "viewer",
        }


@pytest.fixture
def admin_token(client, admin_user):
    """Get admin access token."""
    response = client.post(
        "/api/v1/auth/login",
        json={"email": admin_user["email"], "password": admin_user["password"]},
    )
    return response.get_json()["access_token"]


@pytest.fixture
def viewer_token(client, viewer_user):
    """Get viewer access token."""
    response = client.post(
        "/api/v1/auth/login",
        json={"email": viewer_user["email"], "password": viewer_user["password"]},
    )
    return response.get_json()["access_token"]


def auth_header(token: str) -> dict:
    """Build Authorization header."""
    return {"Authorization": f"Bearer {token}"}
