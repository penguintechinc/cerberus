"""Unit tests for Flask configuration loading."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../services/flask-backend"))

from app.config import Config, DevelopmentConfig, ProductionConfig, TestingConfig


class TestConfig:
    """Tests for base configuration."""

    def test_default_db_type(self):
        assert Config.DB_TYPE == os.getenv("DB_TYPE", "postgres")

    def test_get_db_uri_postgres(self):
        uri = Config.get_db_uri()
        assert uri.startswith("postgres://")

    def test_jwt_defaults(self):
        assert Config.JWT_ACCESS_TOKEN_EXPIRES.total_seconds() > 0
        assert Config.JWT_REFRESH_TOKEN_EXPIRES.total_seconds() > 0


class TestDevelopmentConfig:
    """Tests for development configuration."""

    def test_debug_enabled(self):
        assert DevelopmentConfig.DEBUG is True


class TestProductionConfig:
    """Tests for production configuration."""

    def test_debug_disabled(self):
        assert ProductionConfig.DEBUG is False


class TestTestingConfig:
    """Tests for testing configuration."""

    def test_testing_flag(self):
        assert TestingConfig.TESTING is True

    def test_sqlite_db(self):
        assert TestingConfig.DB_TYPE == "sqlite"
