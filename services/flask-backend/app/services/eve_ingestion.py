"""EVE JSON Ingestion Service for Suricata IPS Alerts."""

import json
import os
import time
import threading
from datetime import datetime
from typing import Optional, Callable
from dataclasses import dataclass

from opensearchpy import OpenSearch


@dataclass
class EVEAlert:
    """Parsed EVE JSON alert."""

    timestamp: datetime
    event_type: str
    src_ip: str
    src_port: int
    dest_ip: str
    dest_port: int
    protocol: str
    alert_signature: Optional[str] = None
    alert_sid: Optional[int] = None
    alert_severity: Optional[int] = None
    alert_category: Optional[str] = None
    alert_action: Optional[str] = None
    flow_id: Optional[str] = None
    payload_printable: Optional[str] = None
    raw_event: Optional[dict] = None


class EVEIngestionService:
    """Service for ingesting Suricata EVE JSON logs."""

    def __init__(
        self,
        eve_file_path: str = "/var/log/suricata/eve.json",
        opensearch_host: str = None,
        opensearch_port: int = 9200,
        opensearch_user: str = "admin",
        opensearch_password: str = None,
        index_prefix: str = "cerberus-ips",
        batch_size: int = 100,
        flush_interval: float = 5.0,
    ):
        """Initialize EVE ingestion service.

        Args:
            eve_file_path: Path to Suricata EVE JSON log file
            opensearch_host: OpenSearch host
            opensearch_port: OpenSearch port
            opensearch_user: OpenSearch username
            opensearch_password: OpenSearch password
            index_prefix: Index prefix for OpenSearch
            batch_size: Number of events to batch before sending
            flush_interval: Seconds between flushes
        """
        self.eve_file_path = eve_file_path
        self.index_prefix = index_prefix
        self.batch_size = batch_size
        self.flush_interval = flush_interval

        # OpenSearch client
        self.opensearch_host = opensearch_host or os.environ.get("OPENSEARCH_HOST", "opensearch")
        self.opensearch_port = opensearch_port or int(os.environ.get("OPENSEARCH_PORT", 9200))
        self.opensearch_user = opensearch_user or os.environ.get("OPENSEARCH_USER", "admin")
        self.opensearch_password = opensearch_password or os.environ.get(
            "OPENSEARCH_PASSWORD", "Cerberus@123"
        )

        self._client: Optional[OpenSearch] = None
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._event_buffer: list = []
        self._last_flush = time.time()
        self._file_position = 0

        # Callbacks
        self._alert_callback: Optional[Callable[[EVEAlert], None]] = None

    @property
    def client(self) -> OpenSearch:
        """Get or create OpenSearch client."""
        if self._client is None:
            self._client = OpenSearch(
                hosts=[{"host": self.opensearch_host, "port": self.opensearch_port}],
                http_auth=(self.opensearch_user, self.opensearch_password),
                use_ssl=True,
                verify_certs=False,
                ssl_show_warn=False,
            )
        return self._client

    def set_alert_callback(self, callback: Callable[[EVEAlert], None]):
        """Set callback for new alerts (for real-time processing)."""
        self._alert_callback = callback

    def parse_eve_event(self, line: str) -> Optional[EVEAlert]:
        """Parse a single EVE JSON line into an EVEAlert."""
        try:
            event = json.loads(line.strip())
        except json.JSONDecodeError:
            return None

        event_type = event.get("event_type", "unknown")

        # Parse timestamp
        ts_str = event.get("timestamp", "")
        try:
            timestamp = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
        except (ValueError, AttributeError):
            timestamp = datetime.utcnow()

        # Extract common fields
        alert = EVEAlert(
            timestamp=timestamp,
            event_type=event_type,
            src_ip=event.get("src_ip", "0.0.0.0"),
            src_port=event.get("src_port", 0),
            dest_ip=event.get("dest_ip", "0.0.0.0"),
            dest_port=event.get("dest_port", 0),
            protocol=event.get("proto", "unknown"),
            flow_id=str(event.get("flow_id", "")),
            raw_event=event,
        )

        # Extract alert-specific fields
        if event_type == "alert" and "alert" in event:
            alert_data = event["alert"]
            alert.alert_signature = alert_data.get("signature", "")
            alert.alert_sid = alert_data.get("signature_id")
            alert.alert_severity = alert_data.get("severity")
            alert.alert_category = alert_data.get("category", "")
            alert.alert_action = alert_data.get("action", "")

        # Extract payload if present
        if "payload_printable" in event:
            alert.payload_printable = event["payload_printable"]

        return alert

    def _get_index_name(self, timestamp: datetime) -> str:
        """Get OpenSearch index name for a given timestamp."""
        date_suffix = timestamp.strftime("%Y.%m.%d")
        return f"{self.index_prefix}-{date_suffix}"

    def _prepare_document(self, alert: EVEAlert) -> dict:
        """Prepare document for OpenSearch indexing."""
        doc = {
            "@timestamp": alert.timestamp.isoformat(),
            "event_type": alert.event_type,
            "src_ip": alert.src_ip,
            "src_port": alert.src_port,
            "dest_ip": alert.dest_ip,
            "dest_port": alert.dest_port,
            "protocol": alert.protocol,
            "flow_id": alert.flow_id,
        }

        if alert.alert_signature:
            doc["alert"] = {
                "signature": alert.alert_signature,
                "signature_id": alert.alert_sid,
                "severity": alert.alert_severity,
                "category": alert.alert_category,
                "action": alert.alert_action,
            }

        if alert.payload_printable:
            doc["payload_printable"] = alert.payload_printable[:4096]

        if alert.raw_event:
            doc["raw"] = alert.raw_event

        return doc

    def _flush_buffer(self):
        """Flush event buffer to OpenSearch."""
        if not self._event_buffer:
            return

        try:
            bulk_body = []
            for alert in self._event_buffer:
                index_name = self._get_index_name(alert.timestamp)
                bulk_body.append({"index": {"_index": index_name}})
                bulk_body.append(self._prepare_document(alert))

            if bulk_body:
                self.client.bulk(body=bulk_body)

        except Exception as e:
            print(f"Error flushing to OpenSearch: {e}")

        self._event_buffer = []
        self._last_flush = time.time()

    def _process_line(self, line: str):
        """Process a single line from EVE JSON."""
        alert = self.parse_eve_event(line)
        if alert is None:
            return

        # Add to buffer
        self._event_buffer.append(alert)

        # Call callback for real-time processing
        if self._alert_callback and alert.event_type == "alert":
            try:
                self._alert_callback(alert)
            except Exception as e:
                print(f"Alert callback error: {e}")

        # Flush if buffer is full or interval exceeded
        if len(self._event_buffer) >= self.batch_size:
            self._flush_buffer()
        elif time.time() - self._last_flush >= self.flush_interval:
            self._flush_buffer()

    def _tail_file(self):
        """Tail the EVE JSON file and process new lines."""
        while self._running:
            try:
                if not os.path.exists(self.eve_file_path):
                    time.sleep(1)
                    continue

                with open(self.eve_file_path, "r") as f:
                    # Seek to last known position
                    f.seek(self._file_position)

                    while self._running:
                        line = f.readline()
                        if line:
                            self._process_line(line)
                            self._file_position = f.tell()
                        else:
                            # No new lines, check for flush
                            if time.time() - self._last_flush >= self.flush_interval:
                                self._flush_buffer()
                            time.sleep(0.1)

                            # Check if file was rotated
                            try:
                                current_size = os.path.getsize(self.eve_file_path)
                                if current_size < self._file_position:
                                    # File was rotated, start from beginning
                                    self._file_position = 0
                                    break
                            except OSError:
                                break

            except Exception as e:
                print(f"Error tailing EVE file: {e}")
                time.sleep(1)

    def start(self):
        """Start the EVE ingestion service in a background thread."""
        if self._running:
            return

        self._running = True
        self._thread = threading.Thread(target=self._tail_file, daemon=True)
        self._thread.start()

    def stop(self):
        """Stop the EVE ingestion service."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=5)
            self._thread = None
        self._flush_buffer()

    def process_file_once(self, file_path: str = None):
        """Process an entire EVE JSON file once (for batch processing)."""
        path = file_path or self.eve_file_path
        if not os.path.exists(path):
            return 0

        count = 0
        with open(path, "r") as f:
            for line in f:
                self._process_line(line)
                count += 1

        self._flush_buffer()
        return count

    def get_stats(self) -> dict:
        """Get ingestion statistics."""
        return {
            "file_path": self.eve_file_path,
            "file_position": self._file_position,
            "buffer_size": len(self._event_buffer),
            "running": self._running,
            "opensearch_host": self.opensearch_host,
            "index_prefix": self.index_prefix,
        }
