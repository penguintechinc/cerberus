"""Unit tests for PyDAL model operations."""

import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../services/flask-backend"))

from app import create_app
from app.auth import hash_password, verify_password
from app.config import TestingConfig
from app.models import (
    create_user,
    delete_user,
    get_user_by_email,
    get_user_by_id,
    list_users,
    update_user,
)


@pytest.fixture
def app():
    app = create_app(TestingConfig)
    yield app


@pytest.fixture
def ctx(app):
    with app.app_context():
        yield


class TestPasswordHashing:
    """Tests for password hashing utilities."""

    def test_hash_and_verify(self):
        password = "secure_password_123"
        hashed = hash_password(password)
        assert hashed != password
        assert verify_password(password, hashed)

    def test_wrong_password(self):
        hashed = hash_password("correct_password")
        assert not verify_password("wrong_password", hashed)

    def test_different_hashes(self):
        password = "same_password"
        hash1 = hash_password(password)
        hash2 = hash_password(password)
        assert hash1 != hash2  # bcrypt uses random salt


class TestUserCRUD:
    """Tests for user model CRUD operations."""

    def test_create_user(self, ctx):
        user = create_user(
            email="test@example.com",
            password_hash=hash_password("password123"),
            full_name="Test User",
            role="viewer",
        )
        assert user["email"] == "test@example.com"
        assert user["role"] == "viewer"
        assert "id" in user

    def test_get_user_by_email(self, ctx):
        create_user(
            email="find@example.com",
            password_hash=hash_password("password123"),
            full_name="Find Me",
            role="viewer",
        )
        found = get_user_by_email("find@example.com")
        assert found is not None
        assert found["email"] == "find@example.com"

    def test_get_user_by_email_not_found(self, ctx):
        found = get_user_by_email("nonexistent@example.com")
        assert found is None

    def test_get_user_by_id(self, ctx):
        user = create_user(
            email="byid@example.com",
            password_hash=hash_password("password123"),
            full_name="By ID",
            role="admin",
        )
        found = get_user_by_id(user["id"])
        assert found is not None
        assert found["id"] == user["id"]

    def test_update_user(self, ctx):
        user = create_user(
            email="update@example.com",
            password_hash=hash_password("password123"),
            full_name="Before Update",
            role="viewer",
        )
        updated = update_user(user["id"], full_name="After Update", role="maintainer")
        assert updated["full_name"] == "After Update"
        assert updated["role"] == "maintainer"

    def test_delete_user(self, ctx):
        user = create_user(
            email="delete@example.com",
            password_hash=hash_password("password123"),
            full_name="Delete Me",
            role="viewer",
        )
        result = delete_user(user["id"])
        assert result is True
        assert get_user_by_id(user["id"]) is None

    def test_list_users(self, ctx):
        for i in range(3):
            create_user(
                email=f"list{i}@example.com",
                password_hash=hash_password("password123"),
                full_name=f"List User {i}",
                role="viewer",
            )
        users, total = list_users(page=1, per_page=10)
        assert total >= 3
        assert len(users) >= 3
