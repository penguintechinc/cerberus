"""Cerberus PKI Service - Certificate Authority Management."""

import os
import hashlib
from datetime import datetime, timedelta
from typing import Optional, Tuple
from dataclasses import dataclass

from cryptography import x509
from cryptography.x509.oid import NameOID, ExtensionOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.backends import default_backend


@dataclass
class CertificateInfo:
    """Certificate information."""

    subject_cn: str
    issuer_cn: str
    serial_number: str
    not_before: datetime
    not_after: datetime
    fingerprint_sha256: str
    is_ca: bool


class PKIService:
    """Service for managing PKI and CA certificates."""

    def __init__(
        self,
        ca_dir: str = "/data/ca",
        ca_cn: str = "Cerberus Root CA",
        ca_org: str = "Cerberus NGFW",
        ca_validity_days: int = 3650,
    ):
        """Initialize PKI service.

        Args:
            ca_dir: Directory to store CA certificates and keys
            ca_cn: Common Name for the CA certificate
            ca_org: Organization name for the CA certificate
            ca_validity_days: Validity period in days for CA certificate
        """
        self.ca_dir = ca_dir
        self.ca_cn = ca_cn
        self.ca_org = ca_org
        self.ca_validity_days = ca_validity_days

        self._ca_cert: Optional[x509.Certificate] = None
        self._ca_key: Optional[rsa.RSAPrivateKey] = None

        # Ensure CA directory exists
        os.makedirs(ca_dir, exist_ok=True)

        # Load or create CA
        self._load_or_create_ca()

    @property
    def ca_cert_path(self) -> str:
        """Path to CA certificate file."""
        return os.path.join(self.ca_dir, "ca.crt")

    @property
    def ca_key_path(self) -> str:
        """Path to CA private key file."""
        return os.path.join(self.ca_dir, "ca.key")

    def _load_or_create_ca(self):
        """Load existing CA or create a new one."""
        if os.path.exists(self.ca_cert_path) and os.path.exists(self.ca_key_path):
            try:
                self._load_ca()
                return
            except Exception:
                pass

        self._create_ca()

    def _load_ca(self):
        """Load CA certificate and key from disk."""
        with open(self.ca_cert_path, "rb") as f:
            self._ca_cert = x509.load_pem_x509_certificate(f.read(), default_backend())

        with open(self.ca_key_path, "rb") as f:
            self._ca_key = serialization.load_pem_private_key(
                f.read(), password=None, backend=default_backend()
            )

    def _create_ca(self):
        """Create a new CA certificate and key."""
        # Generate RSA key
        self._ca_key = rsa.generate_private_key(
            public_exponent=65537, key_size=4096, backend=default_backend()
        )

        # Build CA certificate
        subject = issuer = x509.Name(
            [
                x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
                x509.NameAttribute(NameOID.ORGANIZATION_NAME, self.ca_org),
                x509.NameAttribute(NameOID.COMMON_NAME, self.ca_cn),
            ]
        )

        self._ca_cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(self._ca_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.utcnow())
            .not_valid_after(datetime.utcnow() + timedelta(days=self.ca_validity_days))
            .add_extension(
                x509.BasicConstraints(ca=True, path_length=1),
                critical=True,
            )
            .add_extension(
                x509.KeyUsage(
                    digital_signature=False,
                    content_commitment=False,
                    key_encipherment=False,
                    data_encipherment=False,
                    key_agreement=False,
                    key_cert_sign=True,
                    crl_sign=True,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )
            .sign(self._ca_key, hashes.SHA256(), default_backend())
        )

        # Save to disk
        self._save_ca()

    def _save_ca(self):
        """Save CA certificate and key to disk."""
        with open(self.ca_cert_path, "wb") as f:
            f.write(
                self._ca_cert.public_bytes(serialization.Encoding.PEM)
            )

        with open(self.ca_key_path, "wb") as f:
            f.write(
                self._ca_key.private_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PrivateFormat.TraditionalOpenSSL,
                    encryption_algorithm=serialization.NoEncryption(),
                )
            )

        # Secure key file permissions
        os.chmod(self.ca_key_path, 0o600)

    def get_ca_cert_pem(self) -> bytes:
        """Get CA certificate in PEM format."""
        return self._ca_cert.public_bytes(serialization.Encoding.PEM)

    def get_ca_fingerprint(self) -> str:
        """Get SHA256 fingerprint of CA certificate."""
        digest = hashlib.sha256(
            self._ca_cert.public_bytes(serialization.Encoding.DER)
        ).hexdigest()
        return digest

    def get_ca_info(self) -> CertificateInfo:
        """Get CA certificate information."""
        return self._cert_to_info(self._ca_cert)

    def regenerate_ca(self) -> CertificateInfo:
        """Regenerate the CA certificate."""
        self._create_ca()
        return self.get_ca_info()

    def generate_server_cert(
        self,
        hostname: str,
        validity_days: int = 365,
    ) -> Tuple[bytes, bytes]:
        """Generate a server certificate signed by the CA.

        Args:
            hostname: Hostname for the certificate
            validity_days: Certificate validity in days

        Returns:
            Tuple of (certificate_pem, private_key_pem)
        """
        # Generate key
        key = rsa.generate_private_key(
            public_exponent=65537, key_size=2048, backend=default_backend()
        )

        # Build certificate
        subject = x509.Name(
            [
                x509.NameAttribute(NameOID.COMMON_NAME, hostname),
            ]
        )

        cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(self._ca_cert.subject)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.utcnow())
            .not_valid_after(datetime.utcnow() + timedelta(days=validity_days))
            .add_extension(
                x509.SubjectAlternativeName([x509.DNSName(hostname)]),
                critical=False,
            )
            .add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    content_commitment=False,
                    key_encipherment=True,
                    data_encipherment=False,
                    key_agreement=False,
                    key_cert_sign=False,
                    crl_sign=False,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )
            .add_extension(
                x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]),
                critical=False,
            )
            .sign(self._ca_key, hashes.SHA256(), default_backend())
        )

        cert_pem = cert.public_bytes(serialization.Encoding.PEM)
        key_pem = key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        )

        return cert_pem, key_pem

    def generate_client_cert(
        self,
        common_name: str,
        email: Optional[str] = None,
        validity_days: int = 365,
    ) -> Tuple[bytes, bytes]:
        """Generate a client certificate signed by the CA.

        Args:
            common_name: Common name for the certificate
            email: Email address (optional)
            validity_days: Certificate validity in days

        Returns:
            Tuple of (certificate_pem, private_key_pem)
        """
        # Generate key
        key = rsa.generate_private_key(
            public_exponent=65537, key_size=2048, backend=default_backend()
        )

        # Build subject
        subject_attrs = [x509.NameAttribute(NameOID.COMMON_NAME, common_name)]
        if email:
            subject_attrs.append(x509.NameAttribute(NameOID.EMAIL_ADDRESS, email))

        subject = x509.Name(subject_attrs)

        cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(self._ca_cert.subject)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.utcnow())
            .not_valid_after(datetime.utcnow() + timedelta(days=validity_days))
            .add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    content_commitment=False,
                    key_encipherment=True,
                    data_encipherment=False,
                    key_agreement=False,
                    key_cert_sign=False,
                    crl_sign=False,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )
            .add_extension(
                x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.CLIENT_AUTH]),
                critical=False,
            )
            .sign(self._ca_key, hashes.SHA256(), default_backend())
        )

        cert_pem = cert.public_bytes(serialization.Encoding.PEM)
        key_pem = key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        )

        return cert_pem, key_pem

    def verify_certificate(self, cert_pem: bytes) -> bool:
        """Verify a certificate was signed by this CA.

        Args:
            cert_pem: Certificate in PEM format

        Returns:
            True if certificate is valid and signed by CA
        """
        try:
            cert = x509.load_pem_x509_certificate(cert_pem, default_backend())

            # Check if issuer matches CA subject
            if cert.issuer != self._ca_cert.subject:
                return False

            # Verify signature
            self._ca_cert.public_key().verify(
                cert.signature,
                cert.tbs_certificate_bytes,
                cert.signature_algorithm_parameters,
            )

            # Check validity period
            now = datetime.utcnow()
            if now < cert.not_valid_before or now > cert.not_valid_after:
                return False

            return True

        except Exception:
            return False

    def get_cert_info(self, cert_pem: bytes) -> CertificateInfo:
        """Get information about a certificate.

        Args:
            cert_pem: Certificate in PEM format

        Returns:
            Certificate information
        """
        cert = x509.load_pem_x509_certificate(cert_pem, default_backend())
        return self._cert_to_info(cert)

    def _cert_to_info(self, cert: x509.Certificate) -> CertificateInfo:
        """Convert certificate to info dataclass."""
        # Check if CA
        try:
            bc = cert.extensions.get_extension_for_oid(ExtensionOID.BASIC_CONSTRAINTS)
            is_ca = bc.value.ca
        except x509.ExtensionNotFound:
            is_ca = False

        return CertificateInfo(
            subject_cn=cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[
                0
            ].value,
            issuer_cn=cert.issuer.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value,
            serial_number=format(cert.serial_number, "x"),
            not_before=cert.not_valid_before,
            not_after=cert.not_valid_after,
            fingerprint_sha256=hashlib.sha256(
                cert.public_bytes(serialization.Encoding.DER)
            ).hexdigest(),
            is_ca=is_ca,
        )
