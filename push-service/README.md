# SpaControl Push Service

Always-on bridge that turns the spa's MQTT status stream into **Apple Push
Notifications**, so alerts arrive even when the app is closed:

```
ESP32  ──MQTT──▶  broker  ──▶  pushd.py (detect)  ──HTTP/2──▶  APNs  ──▶  iPhone
                                     ▲
                          iPhone registers its APNs token
                          + notification prefs  ──HTTP──▶  /register
```

It runs the **same detection logic as the app** (`detector.py` is a port of the
app's `SpaAlertMonitor`), so behaviour is identical: reached-target, freeze,
faults, high/low-temp, water-sensor fault, and offline-30min. "Software update"
stays app-side.

The service is host-agnostic; below is a walk-through for the **Oracle Cloud
Always-Free VM**, but a Raspberry Pi or any $5 VM works the same.

---

## 1. Apple setup (one time)

You need the paid Apple Developer Program.

1. **Enable Push for the App ID.** Developer portal → Certificates, IDs & Profiles
   → Identifiers → your app ID (`com.spacontrol.SpaControl`) → check
   **Push Notifications** → Save. (With automatic signing, Xcode also does this
   when it sees the `aps-environment` entitlement.)
2. **Create an APNs Auth Key (.p8).** Keys → **+** → check **Apple Push
   Notifications service (APNs)** → Register → **Download the `.p8` once**
   (you can't re-download it). Note the **Key ID** (10 chars).
3. **Find your Team ID** (10 chars): top-right of the developer portal / Membership.
4. Fill `config.json` → `apns`: `key_path` (the .p8), `key_id`, `team_id`,
   `bundle_id`, and `env`:
   - `sandbox` — for app builds installed from **Xcode** onto a device (dev).
   - `production` — for **TestFlight / App Store** builds.
   (The sender auto-retries the other environment on `BadDeviceToken`, so a mismatch
   degrades gracefully, but set it correctly to avoid the extra round-trip.)

> Push does **not** work in the iOS Simulator over real APNs. Test on a physical
> device, or use `xcrun simctl push` to verify the app's display path locally.

## 2. Oracle Cloud VM

1. Create an **Always Free** VM (Ampere A1, Ubuntu). Open an inbound rule for
   **tcp/443** (and 80 for cert issuance) in the VCN security list; keep 8080
   (the register endpoint) **closed** to the internet — Caddy proxies to it locally.
2. SSH in and:

```bash
sudo mkdir -p /opt/spacontrol-push && sudo chown $USER /opt/spacontrol-push
cd /opt/spacontrol-push
# copy pushd.py detector.py apns.py config.example.json requirements.txt here,
# plus your AuthKey_XXXX.p8
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
cp config.example.json config.json    # then edit config.json
```

3. **TLS + the register endpoint.** The phone registers over HTTPS, so put
   [Caddy](https://caddyserver.com) in front (automatic Let's Encrypt):

```
# /etc/caddy/Caddyfile
push.yourdomain.com {
    reverse_proxy 127.0.0.1:8080
}
```

You need a domain pointing at the VM's public IP (~$12/yr). No domain yet? For
early testing you can skip Caddy and register over the LAN / a Tailscale IP
directly to `http://<vm>:8080` (open 8080 to just your network).

4. **Run it** as a service:

```bash
sudo cp spacontrol-push.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now spacontrol-push
journalctl -u spacontrol-push -f      # watch it
```

On start you'll see `register endpoint on http://127.0.0.1:8080 (dry_run=False)`.
`dry_run=True` means the .p8 or httpx isn't loaded — fix `config.json` /
`pip install`.

## 3. Point the app at it

In the app: **Settings → Notifications → Push service** — enter the base URL
(`https://push.yourdomain.com`) and the `api_token` from `config.json`. The app
registers its APNs token + current toggles; thereafter the **server** sends the
pushes and the app stops posting local notifications (no duplicates). Clear the
URL to fall back to local, foreground-only alerts.

## Endpoints

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | `/register` | `{token, prefs, platform, device?}` | `Authorization: Bearer <api_token>` |
| POST | `/unregister` | `{token}` | same auth |
| GET | `/health` | — | returns `ok` |

## Config reference

See `config.example.json`. `token_store` is a JSON file of registered devices
(created automatically). `offline_seconds` (default 1800) is the no-report
window before an offline push.

## Scaling to many spas later

Detection/offline state is already keyed per device parsed from the topic. To go
multi-spa: have each controller publish to `spa/<id>/status`, set the service
`topic` to `spa/+/status`, and include that `<id>` as `device` in the app's
register payload. One `pushd` instance handles thousands of devices (it's
I/O-light); no code change needed beyond the topic/id wiring.
