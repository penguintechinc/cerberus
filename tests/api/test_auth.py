"""API tests for authentication endpoints."""

from conftest import auth_header


class TestLogin:
    """Tests for POST /api/v1/auth/login."""

    def test_login_success(self, client, admin_user):
        response = client.post(
            "/api/v1/auth/login",
            json={"email": admin_user["email"], "password": admin_user["password"]},
        )
        assert response.status_code == 200
        data = response.get_json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["token_type"] == "Bearer"
        assert data["user"]["email"] == admin_user["email"]
        assert data["user"]["role"] == "admin"

    def test_login_bad_password(self, client, admin_user):
        response = client.post(
            "/api/v1/auth/login",
            json={"email": admin_user["email"], "password": "wrongpassword"},
        )
        assert response.status_code == 401

    def test_login_nonexistent_user(self, client):
        response = client.post(
            "/api/v1/auth/login",
            json={"email": "nobody@test.com", "password": "whatever"},
        )
        assert response.status_code == 401

    def test_login_missing_fields(self, client):
        response = client.post("/api/v1/auth/login", json={"email": "test@test.com"})
        assert response.status_code == 400

    def test_login_empty_body(self, client):
        response = client.post(
            "/api/v1/auth/login", content_type="application/json"
        )
        assert response.status_code == 400


class TestRegister:
    """Tests for POST /api/v1/auth/register."""

    def test_register_success(self, client):
        response = client.post(
            "/api/v1/auth/register",
            json={
                "email": "newuser@test.com",
                "password": "password123",
                "full_name": "New User",
            },
        )
        assert response.status_code == 201
        data = response.get_json()
        assert data["user"]["role"] == "viewer"

    def test_register_short_password(self, client):
        response = client.post(
            "/api/v1/auth/register",
            json={"email": "short@test.com", "password": "short", "full_name": "Short"},
        )
        assert response.status_code == 400

    def test_register_duplicate_email(self, client, admin_user):
        response = client.post(
            "/api/v1/auth/register",
            json={
                "email": admin_user["email"],
                "password": "password123",
                "full_name": "Duplicate",
            },
        )
        assert response.status_code == 409


class TestMe:
    """Tests for GET /api/v1/auth/me."""

    def test_me_authenticated(self, client, admin_token):
        response = client.get("/api/v1/auth/me", headers=auth_header(admin_token))
        assert response.status_code == 200
        data = response.get_json()
        assert "email" in data
        assert "role" in data

    def test_me_no_token(self, client):
        response = client.get("/api/v1/auth/me")
        assert response.status_code == 401


class TestRefresh:
    """Tests for POST /api/v1/auth/refresh."""

    def test_refresh_success(self, client, admin_user):
        login_response = client.post(
            "/api/v1/auth/login",
            json={"email": admin_user["email"], "password": admin_user["password"]},
        )
        refresh_token = login_response.get_json()["refresh_token"]

        response = client.post(
            "/api/v1/auth/refresh", json={"refresh_token": refresh_token}
        )
        assert response.status_code == 200
        data = response.get_json()
        assert "access_token" in data
        assert "refresh_token" in data

    def test_refresh_invalid_token(self, client):
        response = client.post(
            "/api/v1/auth/refresh", json={"refresh_token": "invalid.token.here"}
        )
        assert response.status_code == 401


class TestLogout:
    """Tests for POST /api/v1/auth/logout."""

    def test_logout_success(self, client, admin_token):
        response = client.post(
            "/api/v1/auth/logout", headers=auth_header(admin_token)
        )
        assert response.status_code == 200

    def test_logout_no_token(self, client):
        response = client.post("/api/v1/auth/logout")
        assert response.status_code == 401
