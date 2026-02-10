#!/usr/bin/env python3
"""Seed mock data for Cerberus NGFW development and testing.

Creates 3-4 items per NGFW feature following the PenguinTech mock data pattern.
Requires a running Flask backend with database access.

Usage:
    python scripts/seed-mock-data.py
    # Or via Makefile:
    make seed-mock-data
"""

import json
import os
import sys

import requests

API_URL = os.getenv("API_URL", "http://localhost:5000/api/v1")
ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "admin@example.com")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "changeme123")


def get_token() -> str:
    """Login and get admin access token."""
    response = requests.post(
        f"{API_URL}/auth/login",
        json={"email": ADMIN_EMAIL, "password": ADMIN_PASSWORD},
        timeout=10,
    )
    if response.status_code != 200:
        print(f"ERROR: Login failed ({response.status_code}): {response.text}")
        sys.exit(1)
    return response.json()["access_token"]


def seed_users(token: str):
    """Create sample users (3 users across roles)."""
    headers = {"Authorization": f"Bearer {token}"}
    users = [
        {
            "email": "maintainer@cerberus.local",
            "password": "maintainer123",
            "full_name": "Network Engineer",
            "role": "maintainer",
        },
        {
            "email": "viewer@cerberus.local",
            "password": "viewer12345",
            "full_name": "Security Analyst",
            "role": "viewer",
        },
        {
            "email": "ops@cerberus.local",
            "password": "operator123",
            "full_name": "Operations Staff",
            "role": "viewer",
        },
    ]

    print("\n--- Users ---")
    for user in users:
        response = requests.post(
            f"{API_URL}/users", headers=headers, json=user, timeout=10
        )
        if response.status_code == 201:
            print(f"  Created: {user['email']} ({user['role']})")
        elif response.status_code == 409:
            print(f"  Exists:  {user['email']} ({user['role']})")
        else:
            print(f"  Failed:  {user['email']} - {response.status_code}: {response.text}")


# Mock data definitions for NGFW features.
# These represent the data that would be seeded via future API endpoints.

FIREWALL_RULES = [
    {
        "name": "Allow HTTP/HTTPS",
        "source_zone": "LAN",
        "destination_zone": "WAN",
        "protocol": "tcp",
        "destination_port": "80,443",
        "action": "allow",
        "logging": True,
        "description": "Allow outbound web traffic from LAN to WAN",
    },
    {
        "name": "Allow DNS",
        "source_zone": "LAN",
        "destination_zone": "WAN",
        "protocol": "udp",
        "destination_port": "53",
        "action": "allow",
        "logging": False,
        "description": "Allow DNS resolution from LAN",
    },
    {
        "name": "Deny All",
        "source_zone": "any",
        "destination_zone": "any",
        "protocol": "any",
        "destination_port": "any",
        "action": "deny",
        "logging": True,
        "description": "Default deny rule - blocks all unmatched traffic",
    },
]

IPS_CATEGORIES = [
    {
        "name": "Network Scan Detection",
        "severity": "medium",
        "description": "Detects port scans, host discovery, and network mapping attempts",
        "rule_count": 47,
    },
    {
        "name": "Brute Force Prevention",
        "severity": "high",
        "description": "Detects credential stuffing, password spraying, and brute force attacks",
        "rule_count": 23,
    },
    {
        "name": "Web Attack Signatures",
        "severity": "critical",
        "description": "SQL injection, XSS, CSRF, and OWASP Top 10 attack patterns",
        "rule_count": 156,
    },
]

VPN_CONFIGS = [
    {
        "name": "HQ-Branch Site-to-Site",
        "type": "wireguard",
        "endpoint": "branch.example.com:51820",
        "status": "active",
        "description": "WireGuard tunnel between HQ and branch office",
    },
    {
        "name": "Employee Remote Access",
        "type": "wireguard",
        "endpoint": "vpn.cerberus.local:51820",
        "status": "active",
        "description": "Remote access VPN for employees",
    },
    {
        "name": "Multi-Site Mesh",
        "type": "ipsec",
        "endpoint": "mesh.example.com:500",
        "status": "standby",
        "description": "IPSec mesh VPN connecting all branch offices",
    },
]

CONTENT_FILTER_RULES = [
    {
        "name": "Block Malware Domains",
        "action": "block",
        "category": "malware",
        "description": "Block known malware distribution and C2 domains",
    },
    {
        "name": "Allow Business Applications",
        "action": "allow",
        "category": "business",
        "description": "Allow access to approved business SaaS applications",
    },
    {
        "name": "Block Social Media",
        "action": "block",
        "category": "social-media",
        "description": "Block social media platforms during business hours",
    },
]


def print_mock_data():
    """Print mock data summary (for features without API endpoints yet)."""
    print("\n--- Firewall Rules (mock) ---")
    for rule in FIREWALL_RULES:
        print(f"  {rule['name']}: {rule['source_zone']} -> {rule['destination_zone']} [{rule['action']}]")

    print("\n--- IPS Categories (mock) ---")
    for cat in IPS_CATEGORIES:
        print(f"  {cat['name']}: {cat['severity']} ({cat['rule_count']} rules)")

    print("\n--- VPN Configs (mock) ---")
    for vpn in VPN_CONFIGS:
        print(f"  {vpn['name']}: {vpn['type']} [{vpn['status']}]")

    print("\n--- Content Filter Rules (mock) ---")
    for rule in CONTENT_FILTER_RULES:
        print(f"  {rule['name']}: {rule['category']} [{rule['action']}]")


def main():
    print("Cerberus NGFW - Seeding Mock Data")
    print("=" * 40)

    try:
        token = get_token()
        print(f"Authenticated as {ADMIN_EMAIL}")
    except requests.ConnectionError:
        print(f"ERROR: Cannot connect to API at {API_URL}")
        print("Make sure the Flask backend is running: make dev")
        sys.exit(1)

    # Seed users via API
    seed_users(token)

    # Print mock data for features without API endpoints yet
    print_mock_data()

    print("\n" + "=" * 40)
    print("Mock data seeding complete!")
    print("Note: Firewall, IPS, VPN, and Content Filter data is")
    print("displayed only (API endpoints not yet implemented).")


if __name__ == "__main__":
    main()
