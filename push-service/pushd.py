#!/usr/bin/env python3
"""
pushd.py — SpaControl push-notification service.

Bridges the MQTT status stream to Apple Push Notifications:

    spa/status (MQTT)  ->  SpaAlertDetector  ->  APNs push  ->  iPhone

Runs the same alert detection as the app (detector.py) so notifications arrive
even when the app is suspended or closed. Phones self-register their APNs token
and per-category preferences over a small HTTP endpoint.

Single-spa by default (topic "spa/status", one logical device). It already keys
detection/offline state per device parsed from the topic, so scaling to many
units later is just per-device topics ("spa/<id>/status") + a device id in the
register payload — see README.
"""

import json
import logging
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import paho.mqtt.client as mqtt

from apns import APNsClient
from detector import SpaAlertDetector

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("pushd")

# category -> notification preference key (faultCleared shares the "fault" toggle)
_PREF_KEY = {
    "reachedTarget": "reachedTarget", "freeze": "freeze", "fault": "fault",
    "faultCleared": "fault", "highTemp": "highTemp", "lowTemp": "lowTemp",
    "sensorFault": "sensorFault", "offline": "offline",
}
_FAULT_LABEL = {1: "No Flow", 2: "High Limit", 3: "Over-Temp", 4: "E-Stop"}
_FAULT_DESC = {
    1: "No water flow detected.", 2: "High-limit temperature cutoff tripped.",
    3: "Water over-temperature.", 4: "Emergency stop engaged.",
}


def format_alert(category, ctx):
    """(title, body) for a category — mirrors the app's NotificationManager copy."""
    if category == "reachedTarget":
        return "✅ Target Temperature Reached", f"The spa is now at {ctx.get('temp')}°F."
    if category == "freeze":
        return "❄️ Freeze Protection Active", ("Freezing conditions detected — the spa is "
                                               "heating to protect against freeze damage.")
    if category == "fault":
        c = ctx.get("code", 0)
        return f"⚠️ Spa Fault — {_FAULT_LABEL.get(c, f'Code {c}')}", _FAULT_DESC.get(c, f"Fault code {c}.")
    if category == "highTemp":
        c = ctx.get("code", 0)
        return "🌡️ High-Temperature Alarm", _FAULT_DESC.get(c, "High temperature.") + " The heater has been shut off."
    if category == "lowTemp":
        return "🥶 Low-Temperature Alarm", ("The spa has been heating for over 30 minutes without "
                                            "raising the water temperature. Check the heater or cover.")
    if category == "sensorFault":
        return "🛑 Water-Sensor Fault", (f"The water-temperature reading ({ctx.get('temp')}°F) is out of "
                                         "range. Heating is disabled until it's resolved.")
    if category == "offline":
        return "📴 Spa Offline", "The spa hasn't reported in for 30 minutes. It may have lost power or Wi-Fi."
    if category == "faultCleared":
        return "✅ Spa Fault Cleared", "The spa is operating normally again."
    return "Spa Alert", category


class TokenStore:
    """Persistent map: token -> {prefs, platform, device, updated}."""

    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        self.data = {}
        try:
            with open(path) as f:
                self.data = json.load(f)
        except Exception:
            self.data = {}

    def _save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.data, f)
        os.replace(tmp, self.path)

    def upsert(self, token, prefs, platform, device):
        with self.lock:
            entry = self.data.get(token, {})
            if prefs is not None:
                entry["prefs"] = prefs
            entry.setdefault("prefs", {})
            entry["platform"] = platform or entry.get("platform", "ios")
            entry["device"] = device or entry.get("device", "spa")
            entry["updated"] = int(time.time())
            self.data[token] = entry
            self._save()

    def remove(self, token):
        with self.lock:
            if token in self.data:
                del self.data[token]
                self._save()

    def recipients(self, device, pref_key):
        """Tokens subscribed to `device` (or any) with `pref_key` enabled."""
        with self.lock:
            out = []
            for token, e in self.data.items():
                dev = e.get("device", "spa")
                if dev not in (device, "any", "spa"):
                    continue
                if e.get("prefs", {}).get(pref_key, True):
                    out.append(token)
            return out


class PushService:
    def __init__(self, cfg):
        self.cfg = cfg
        self.store = TokenStore(cfg.get("token_store", "tokens.json"))
        a = cfg["apns"]
        self.apns = APNsClient(a["key_path"], a["key_id"], a["team_id"],
                               a["bundle_id"], a.get("env", "sandbox"))
        self.detectors = {}
        self.last_seen = {}
        self.offline_notified = {}
        self.offline_seconds = cfg.get("offline_seconds", 1800)
        self._lock = threading.Lock()

    # ── detection wiring ─────────────────────────────────────────────────────
    def _detector(self, device):
        d = self.detectors.get(device)
        if d is None:
            d = SpaAlertDetector(emit=lambda cat, ctx, dev=device: self.on_alert(dev, cat, ctx))
            self.detectors[device] = d
        return d

    def on_alert(self, device, category, ctx):
        title, body = format_alert(category, ctx)
        pref_key = _PREF_KEY.get(category, category)
        tokens = self.store.recipients(device, pref_key)
        log.info("ALERT %s/%s -> %d recipient(s): %s", device, category, len(tokens), title)
        for token in tokens:
            ok, status, reason = self.apns.send(token, title, body, category)
            if not ok and status in (400, 410) and reason in ("BadDeviceToken", "Unregistered"):
                log.info("dropping dead token %s… (%s)", token[:12], reason)
                self.store.remove(token)
            elif not ok:
                log.warning("push failed %s… status=%s reason=%s", token[:12], status, reason)

    # ── mqtt ─────────────────────────────────────────────────────────────────
    def on_message(self, client, userdata, msg):
        try:
            status = json.loads(msg.payload.decode())
        except Exception:
            return
        parts = msg.topic.split("/")
        device = parts[1] if len(parts) >= 3 else parts[0]   # spa/<id>/status | spa/status
        with self._lock:
            self.last_seen[device] = time.time()
            self.offline_notified[device] = False
        self._detector(device).process(status)

    def offline_loop(self):
        while True:
            time.sleep(60)
            now = time.time()
            with self._lock:
                items = list(self.last_seen.items())
            for device, seen in items:
                if now - seen > self.offline_seconds and not self.offline_notified.get(device):
                    self.offline_notified[device] = True
                    d = self.detectors.get(device)
                    if d:
                        d.reset()   # stale stream — re-baseline so we don't replay on return
                    self.on_alert(device, "offline", {})

    def run(self):
        m = self.cfg["mqtt"]
        cid = "spacontrol-push-" + str(int(time.time()))
        cl = mqtt.Client(client_id=cid, protocol=mqtt.MQTTv311)
        if m.get("tls", True):
            cl.tls_set()
        if m.get("user"):
            cl.username_pw_set(m["user"], m.get("password", ""))
        cl.on_connect = lambda c, u, f, rc, p=None: (
            log.info("mqtt connected rc=%s, subscribing %s", rc, m.get("topic", "spa/status")),
            c.subscribe(m.get("topic", "spa/status"), qos=1))
        cl.on_message = self.on_message
        # connect_async + auto-reconnect so a broker outage never kills the
        # service (and the register endpoint stays up regardless of MQTT).
        cl.reconnect_delay_set(min_delay=1, max_delay=60)
        cl.connect_async(m["host"], int(m.get("port", 8883)), 60)
        cl.loop_start()

        threading.Thread(target=self.offline_loop, daemon=True).start()
        self._serve_http()

    # ── register endpoint ────────────────────────────────────────────────────
    def _serve_http(self):
        h = self.cfg.get("http", {})
        api_token = h.get("api_token", "")
        store = self.store

        class Handler(BaseHTTPRequestHandler):
            def _send(self, code, body=b"ok"):
                self.send_response(code)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(body if isinstance(body, bytes) else body.encode())

            def log_message(self, *a):
                pass  # quiet default logging

            def do_GET(self):
                self._send(200, "ok") if self.path == "/health" else self._send(404, "not found")

            def do_POST(self):
                if api_token and self.headers.get("Authorization") != f"Bearer {api_token}":
                    return self._send(401, "unauthorized")
                length = int(self.headers.get("Content-Length", 0))
                try:
                    payload = json.loads(self.rfile.read(length) or b"{}")
                    token = payload["token"]
                except Exception:
                    return self._send(400, "bad request")
                if self.path == "/register":
                    store.upsert(token, payload.get("prefs"), payload.get("platform"), payload.get("device"))
                    log.info("registered token %s… (%d total)", token[:12], len(store.data))
                    return self._send(200, "registered")
                if self.path == "/unregister":
                    store.remove(token)
                    return self._send(200, "unregistered")
                return self._send(404, "not found")

        host, port = h.get("host", "127.0.0.1"), int(h.get("port", 8080))
        srv = ThreadingHTTPServer((host, port), Handler)
        log.info("register endpoint on http://%s:%d  (dry_run=%s)", host, port, self.apns.dry_run)
        srv.serve_forever()


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("PUSHD_CONFIG", "config.json")
    with open(path) as f:
        cfg = json.load(f)
    PushService(cfg).run()


if __name__ == "__main__":
    main()
