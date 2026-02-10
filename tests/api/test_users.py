"""API tests for user management endpoints."""

from conftest import auth_header


class TestListUsers:
    """Tests for GET /api/v1/users."""

    def test_list_users_as_admin(self, client, admin_token):
        response = client.get("/api/v1/users", headers=auth_header(admin_token))
        assert response.status_code == 200
        data = response.get_json()
        assert "users" in data
        assert "pagination" in data

    def test_list_users_as_viewer(self, client, viewer_token):
        response = client.get("/api/v1/users", headers=auth_header(viewer_token))
        assert response.status_code == 403

    def test_list_users_no_auth(self, client):
        response = client.get("/api/v1/users")
        assert response.status_code == 401

    def test_list_users_pagination(self, client, admin_token):
        response = client.get(
            "/api/v1/users?page=1&per_page=5",
            headers=auth_header(admin_token),
        )
        assert response.status_code == 200
        data = response.get_json()
        assert data["pagination"]["per_page"] == 5


class TestCreateUser:
    """Tests for POST /api/v1/users."""

    def test_create_user_as_admin(self, client, admin_token):
        response = client.post(
            "/api/v1/users",
            headers=auth_header(admin_token),
            json={
                "email": "created@test.com",
                "password": "password123",
                "full_name": "Created User",
                "role": "maintainer",
            },
        )
        assert response.status_code == 201
        data = response.get_json()
        assert data["user"]["role"] == "maintainer"
        assert "password_hash" not in data["user"]

    def test_create_user_as_viewer(self, client, viewer_token):
        response = client.post(
            "/api/v1/users",
            headers=auth_header(viewer_token),
            json={
                "email": "blocked@test.com",
                "password": "password123",
                "full_name": "Blocked",
                "role": "viewer",
            },
        )
        assert response.status_code == 403

    def test_create_user_invalid_role(self, client, admin_token):
        response = client.post(
            "/api/v1/users",
            headers=auth_header(admin_token),
            json={
                "email": "bad@test.com",
                "password": "password123",
                "full_name": "Bad Role",
                "role": "superadmin",
            },
        )
        assert response.status_code == 400


class TestGetUser:
    """Tests for GET /api/v1/users/<id>."""

    def test_get_user_as_admin(self, client, admin_token, admin_user):
        response = client.get(
            f"/api/v1/users/{admin_user['id']}",
            headers=auth_header(admin_token),
        )
        assert response.status_code == 200
        data = response.get_json()
        assert data["email"] == admin_user["email"]
        assert "password_hash" not in data

    def test_get_nonexistent_user(self, client, admin_token):
        response = client.get(
            "/api/v1/users/99999", headers=auth_header(admin_token)
        )
        assert response.status_code == 404


class TestUpdateUser:
    """Tests for PUT /api/v1/users/<id>."""

    def test_update_user_name(self, client, admin_token, admin_user):
        response = client.put(
            f"/api/v1/users/{admin_user['id']}",
            headers=auth_header(admin_token),
            json={"full_name": "Updated Name"},
        )
        assert response.status_code == 200
        data = response.get_json()
        assert data["user"]["full_name"] == "Updated Name"


class TestDeleteUser:
    """Tests for DELETE /api/v1/users/<id>."""

    def test_cannot_delete_self(self, client, admin_token, admin_user):
        response = client.delete(
            f"/api/v1/users/{admin_user['id']}",
            headers=auth_header(admin_token),
        )
        assert response.status_code == 400


class TestRoles:
    """Tests for GET /api/v1/users/roles."""

    def test_get_roles(self, client, admin_token):
        response = client.get(
            "/api/v1/users/roles", headers=auth_header(admin_token)
        )
        assert response.status_code == 200
        data = response.get_json()
        assert "admin" in data["roles"]
        assert "maintainer" in data["roles"]
        assert "viewer" in data["roles"]
