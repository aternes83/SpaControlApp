"""
detector.py — server-side spa alert detection.

A direct port of the iOS app's SpaAlertMonitor so detection runs on the always-on
push service (delivering true background push) with identical behaviour. One
instance per spa; edge-triggered and re-baselined on reset(). Never raises on a
malformed status.

Emits (category, context) tuples via the `emit` callback. Categories match the
app's NotificationCategory rawValues:
    reachedTarget, freeze, fault, highTemp, lowTemp, sensorFault
(offline is handled by the daemon on a timer; updateAvailable stays app-side.)
"""

import time


class SpaAlertDetector:
    FREEZE_ON_F  = 40.0   # <= engage freeze protection
    FREEZE_OFF_F = 45.0   # >= clear (hysteresis)
    SENSOR_MIN_F = 20.0   # outside [min,max] => sensor fault
    SENSOR_MAX_F = 130.0
    STALL_SECONDS = 30 * 60
    STALL_RISE_F  = 1.0   # required rise to count as heating progress

    def __init__(self, emit, now=time.time):
        self.emit = emit          # emit(category:str, context:dict)
        self.now = now
        self.reset()

    def reset(self):
        self._was_below = None    # None = not yet baselined
        self._last_fault = None   # None = not yet baselined
        self._in_freeze = False
        self._sensor_faulted = False
        self._stall_anchor = None # (t, temp)
        self._stall_notified = False

    def process(self, s):
        """Process one status dict (parsed spa/status JSON)."""
        try:
            temp = float(s.get("temp_f"))
            setpoint = float(s.get("setpoint"))
        except (TypeError, ValueError):
            return
        heater = bool(s.get("heater"))
        fault = bool(s.get("fault"))
        fault_code = int(s.get("fault_code", 0) or 0)

        sensor_ok = self.SENSOR_MIN_F <= temp <= self.SENSOR_MAX_F
        self._handle_sensor(temp, sensor_ok)
        self._handle_fault(fault, fault_code, temp)

        if not sensor_ok:
            return
        self._handle_reached_target(temp, setpoint)
        self._handle_freeze(temp)
        self._handle_heat_stall(temp, setpoint, heater)

    # ── sensor plausibility ──────────────────────────────────────────────────
    def _handle_sensor(self, temp, ok):
        if not ok:
            if not self._sensor_faulted:
                self.emit("sensorFault", {"temp": round(temp)})
                self._sensor_faulted = True
        elif self._sensor_faulted:
            self._sensor_faulted = False

    # ── faults: temperature trips vs generic vs cleared ──────────────────────
    def _handle_fault(self, fault, code, temp):
        effective = code if fault else 0
        if self._last_fault is None:      # baseline: don't replay on connect
            self._last_fault = effective
            return
        if effective == self._last_fault:
            return
        self._last_fault = effective
        if effective == 0:
            self.emit("faultCleared", {})
        elif effective in (2, 3):         # high-limit / over-temp
            self.emit("highTemp", {"code": effective})
        elif effective == 5:              # water-temp sensor fault
            self.emit("sensorFault", {"temp": round(temp)})
        else:                             # no-flow / e-stop / other
            self.emit("fault", {"code": effective})

    # ── reached target ───────────────────────────────────────────────────────
    def _handle_reached_target(self, temp, setpoint):
        below = temp < setpoint - 0.5
        reached = temp >= setpoint - 0.05
        if self._was_below is None:
            self._was_below = below
            return
        if reached and self._was_below:
            self.emit("reachedTarget", {"temp": round(setpoint)})
            self._was_below = False
        elif below:
            self._was_below = True

    # ── freeze protection ────────────────────────────────────────────────────
    def _handle_freeze(self, temp):
        if temp <= self.FREEZE_ON_F:
            if not self._in_freeze:
                self.emit("freeze", {"temp": round(temp)})
                self._in_freeze = True
        elif temp >= self.FREEZE_OFF_F:
            self._in_freeze = False

    # ── low-temp / heating stall ─────────────────────────────────────────────
    def _handle_heat_stall(self, temp, setpoint, heating):
        if not (heating and temp < setpoint):
            self._stall_anchor = None
            self._stall_notified = False
            return
        if self._stall_anchor is None:
            self._stall_anchor = (self.now(), temp)
            return
        anchor_t, anchor_temp = self._stall_anchor
        if temp >= anchor_temp + self.STALL_RISE_F:
            self._stall_anchor = (self.now(), temp)     # progress
            self._stall_notified = False
        elif not self._stall_notified and self.now() - anchor_t >= self.STALL_SECONDS:
            self.emit("lowTemp", {})
            self._stall_notified = True
