"""
apns.py — token-based (.p8) APNs sender over HTTP/2.

The provider JWT is signed with ES256 using only `cryptography` (no PyJWT), and
cached/refreshed under Apple's 60-minute limit. Sending needs HTTP/2, so it uses
httpx[http2]; if httpx is missing or the key isn't configured it runs in
DRY_RUN, logging the request instead of contacting Apple — handy for local
testing of the whole pipeline.
"""

import base64
import json
import logging
import time

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives.serialization import load_pem_private_key

log = logging.getLogger("apns")

PROD_HOST = "https://api.push.apple.com"
SANDBOX_HOST = "https://api.sandbox.push.apple.com"


def _b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


class APNsClient:
    def __init__(self, key_path, key_id, team_id, bundle_id, env="sandbox"):
        self.key_id = key_id
        self.team_id = team_id
        self.bundle_id = bundle_id
        self.env = env
        self._key = None
        self._jwt = None
        self._jwt_iat = 0

        # DRY_RUN if the key can't be loaded or httpx isn't available.
        self.dry_run = False
        try:
            with open(key_path, "rb") as f:
                self._key = load_pem_private_key(f.read(), password=None)
        except Exception as e:
            log.warning("APNs key not loaded (%s) — running DRY_RUN", e)
            self.dry_run = True
        try:
            import httpx  # noqa: F401
            self._httpx = httpx
        except Exception:
            log.warning("httpx not installed — running DRY_RUN")
            self.dry_run = True
            self._httpx = None

        self._client = None
        if not self.dry_run:
            self._client = self._httpx.Client(http2=True, timeout=10.0)

    # ── provider JWT ─────────────────────────────────────────────────────────
    def _token(self):
        # Reuse within 50 min (Apple requires refresh between 20 and 60 min).
        if self._jwt and time.time() - self._jwt_iat < 50 * 60:
            return self._jwt
        header = {"alg": "ES256", "kid": self.key_id}
        payload = {"iss": self.team_id, "iat": int(time.time())}
        signing_input = (
            _b64url(json.dumps(header, separators=(",", ":")).encode())
            + b"."
            + _b64url(json.dumps(payload, separators=(",", ":")).encode())
        )
        der = self._key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
        r, s = decode_dss_signature(der)
        raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
        self._jwt = (signing_input + b"." + _b64url(raw)).decode()
        self._jwt_iat = time.time()
        return self._jwt

    def _host(self, env):
        return SANDBOX_HOST if env == "sandbox" else PROD_HOST

    # ── send ─────────────────────────────────────────────────────────────────
    def send(self, device_token, title, body, category=None):
        """Send one alert. Returns (ok: bool, status: int|str, reason: str)."""
        payload = {"aps": {"alert": {"title": title, "body": body}, "sound": "default"}}
        if category:
            payload["category"] = category
        body_bytes = json.dumps(payload).encode()

        if self.dry_run:
            log.info("DRY_RUN push -> %s… : %s / %s", device_token[:12], title, body)
            return True, "dry-run", ""

        headers_base = {
            "apns-topic": self.bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10",
        }
        # Try the configured env; on a token/env mismatch, try the other once.
        for env in (self.env, "production" if self.env == "sandbox" else "sandbox"):
            url = f"{self._host(env)}/3/device/{device_token}"
            headers = dict(headers_base, authorization=f"bearer {self._token()}")
            try:
                resp = self._client.post(url, headers=headers, content=body_bytes)
            except Exception as e:
                return False, "error", str(e)
            if resp.status_code == 200:
                return True, 200, ""
            reason = ""
            try:
                reason = resp.json().get("reason", "")
            except Exception:
                pass
            # BadDeviceToken often just means wrong environment — retry the other.
            if reason == "BadDeviceToken" and env == self.env:
                continue
            return False, resp.status_code, reason
        return False, "error", "exhausted environments"

    def close(self):
        if self._client:
            self._client.close()
