import Foundation
import CocoaMQTT
import CocoaMQTTWebSocket

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

class SpaViewModel: NSObject, ObservableObject {
    @Published var status: SpaStatus?
    @Published var connectionState: ConnectionState = .disconnected

    /// Timestamp of the most recent *live* `spa/status`. Stays nil while the only
    /// status we hold is the broker's retained copy, whose age is unknowable —
    /// see `ingest(_:retained:)` — unless a retained `online` of true dates it,
    /// see `vouchForRetainedStatus()`.
    @Published private(set) var lastStatusDate: Date?
    /// True when connected but no fresh status has arrived within `staleThreshold`,
    /// or when all we have is a retained snapshot of unknown age.
    @Published private(set) var isStale: Bool = false

    /// What the broker says about the tub itself, from the retained `spa/online`
    /// topic: true while the controller holds its connection, false once its last
    /// will fires, and **nil when we simply do not know**.
    ///
    /// nil is a real and common answer, not a placeholder. Firmware older than
    /// the last-will change never publishes this topic, so absence has to mean
    /// "this tub cannot tell me" and fall back to judging freshness. Treating it
    /// as offline would strand every v2.0 spa behind a permanent error.
    @Published private(set) var spaOnline: Bool?

    /// The broker is reachable but the tub is not. This is the case the app used
    /// to show as a healthy green "Connected": the router at the spa goes down,
    /// the controller stops publishing, and the retained `status` keeps handing
    /// every app that opens a complete picture of a running tub.
    var isSpaOffline: Bool { connectionState == .connected && spaOnline == false }

    /// The board publishes `spa/status` every ~30 s; flag stale after 3 missed
    /// cycles. This stays above the ~30 s gap of the weekly planned reboot, so a
    /// scheduled reset does not trip a false stale warning.
    static let staleThreshold: TimeInterval = 90

    /// Rolling in-memory history of temperature samples for the chart.
    @Published private(set) var tempHistory: [TempSample] = []

    private static let historyWindow: TimeInterval = 3 * 60 * 60  // keep last 3 hours
    private static let historyMaxCount = 720                       // hard cap (~6 h @ 30 s)

    private var mqttClient: CocoaMQTT?
    private var intentionalDisconnect = false
    /// Guards against stacking multiple pending 5 s reconnect timers.
    private var reconnectPending = false
    private var stalenessTimer: Timer?

    /// Edge-detects spa conditions from the status stream and raises the
    /// notifications. Re-baselined on disconnect so reconnects don't replay alerts.
    private let alertMonitor = SpaAlertMonitor()
    /// Guards the update check to once per connection.
    private var updateCheckedThisConnection = false

    override init() {
        super.init()
        // Re-evaluate staleness on a timer so the flag flips even when no new
        // message arrives (that's precisely the frozen-feed case we care about).
        stalenessTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshStaleness()
        }
    }

    deinit {
        stalenessTimer?.invalidate()
    }

    private func refreshStaleness() {
        guard connectionState == .connected else {
            if isStale { isStale = false }
            return
        }
        guard let last = lastStatusDate else {
            // Connected, and either nothing has arrived yet or the only thing
            // that has is retained. Holding a snapshot we cannot date is exactly
            // the situation to call stale, not one to call fresh.
            let stale = (status != nil)
            if stale != isStale { isStale = stale }
            return
        }
        let stale = Date().timeIntervalSince(last) > Self.staleThreshold
        if stale != isStale { isStale = stale }
    }

    /// A retained status *can* be dated when the broker also says the tub is
    /// online: a connected controller republishes `status` retained every 5 s,
    /// so the broker's copy is at most a heartbeat old — or, if the tub dropped
    /// in the last ~45 s and its will has not fired yet, at most that old. That
    /// is well inside `staleThreshold`, so it is stamped now and the ordinary
    /// timer takes over from there. Without this every cold open flashes "Stale"
    /// over a perfectly healthy spa until the next heartbeat lands.
    ///
    /// The two retained messages arrive in either order, so this is called from
    /// both sides. It still adds no history point and raises no alert.
    private func vouchForRetainedStatus() {
        guard spaOnline == true, status != nil, lastStatusDate == nil else { return }
        lastStatusDate = Date()
        isStale = false
    }

    /// Apply a decoded status: update state, freshness, history, and fault
    /// notifications. Always called on the main thread.
    ///
    /// `retained` marks the copy the broker replays to every new subscriber. It
    /// is the last thing the controller published, which may have been seconds
    /// or weeks ago — the protocol carries no timestamp, and the message is
    /// byte-for-byte what a live one looks like. So its *values* are shown, as
    /// the last thing known, but it is never allowed to pass as evidence that
    /// the tub is alive: no freshness stamp, no history point dated now, and no
    /// alert raised from a fault that may long since have cleared.
    ///
    /// The one exception is a retained `online` of true, see
    /// `vouchForRetainedStatus()`.
    private func ingest(_ parsed: SpaStatus, retained: Bool) {
        status = parsed
        guard !retained else {
            lastStatusDate = nil
            isStale = true
            vouchForRetainedStatus()
            return
        }
        lastStatusDate = Date()
        isStale = false
        appendHistory(parsed)
        // When a push service is configured the server does detection + delivery,
        // so skip local posting to avoid duplicate notifications.
        if !PushManager.shared.isActive {
            alertMonitor.process(parsed)   // faults, freeze, reached-target, stall, sensor, offline
        }
        if !updateCheckedThisConnection {
            updateCheckedThisConnection = true
            UpdateChecker.check(firmwareVersion: parsed.fw)
        }
    }

    private func appendHistory(_ parsed: SpaStatus) {
        tempHistory.append(TempSample(date: Date(), tempF: parsed.tempF, setpoint: parsed.setpoint))
        let cutoff = Date().addingTimeInterval(-Self.historyWindow)
        tempHistory.removeAll { $0.date < cutoff }
        if tempHistory.count > Self.historyMaxCount {
            tempHistory.removeFirst(tempHistory.count - Self.historyMaxCount)
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func connect() {
        let host     = BrokerSettings.host
        let port     = BrokerSettings.port
        let username = BrokerSettings.username
        let password = BrokerSettings.password

        guard !host.isEmpty else {
            connectionState = .error("No broker host configured")
            return
        }

        intentionalDisconnect = false
        reconnectPending = false          // this fresh connect supersedes any pending retry

        // Fully retire any previous client BEFORE building a new one. Clearing its
        // delegate first is essential: otherwise the old client's late
        // `mqttDidDisconnect` fires into `self`, sees intentionalDisconnect == false,
        // and schedules a phantom reconnect — stacking timers into a connect/
        // disconnect loop. Detach, then disconnect, then drop the reference.
        if let old = mqttClient {
            old.delegate = nil
            old.disconnect()
            mqttClient = nil
        }

        // NOTE: CocoaMQTT's GCDAsyncSocket TLS (MqttCocoaAsyncSocket) does not
        // establish TLS on recent iOS SDKs, so we use the WebSocket transport
        // (modern networking) over HiveMQ Cloud's WSS endpoint (port 8884).
        let clientID = "SpaControl-\(UUID().uuidString.prefix(8))"
        let useTLS = (port == 8883 || port == 8884)
        let wsPort: UInt16 = (port == 8883) ? 8884 : UInt16(port)
        let socket = CocoaMQTTWebSocket(uri: "/mqtt")
        socket.enableSSL = useTLS
        let client = CocoaMQTT(clientID: clientID, host: host, port: wsPort, socket: socket)
        client.username  = username.isEmpty ? nil : username
        client.password  = password.isEmpty ? nil : password
        client.keepAlive = 60
        client.delegate  = self

        mqttClient = client
        connectionState = .connecting
        _ = client.connect()
    }

    func disconnect() {
        intentionalDisconnect = true
        reconnectPending = false
        mqttClient?.disconnect()
    }

    func sendCommand(_ command: SpaCommand) {
        // Optimistically reflect the change in the UI immediately; the board's
        // next status publish reconciles it (rather than waiting up to one
        // publish interval for the echo).
        applyOptimistic(command)
        guard let data = try? Self.encoder.encode(command),
              let json = String(data: data, encoding: .utf8) else { return }
        mqttClient?.publish(BrokerSettings.commandTopic, withString: json, qos: .qos1)
    }

    /// Push the full schedule to the controller. Sent whenever the user edits it
    /// and once on every (re)connect, so the board's persisted copy stays in sync
    /// with the app. No optimistic state — the board echoes `schedule_on`/`_active`.
    func sendSchedule(_ dto: ScheduleDTO) {
        guard connectionState == .connected else { return }
        let cmd = SpaCommand(schedule: dto)
        guard let data = try? Self.encoder.encode(cmd),
              let json = String(data: data, encoding: .utf8) else { return }
        mqttClient?.publish(BrokerSettings.commandTopic, withString: json, qos: .qos1)
    }

    /// Push NTC calibration coefficients to the controller. The board applies them
    /// live and persists them, so this is fire-and-forget (the next status carries
    /// the corrected temperature). Returns false if not connected.
    @discardableResult
    func sendCalibration(_ cal: TempCalDTO) -> Bool {
        guard connectionState == .connected else { return false }
        let cmd = SpaCommand(setTempCal: cal)
        guard let data = try? Self.encoder.encode(cmd),
              let json = String(data: data, encoding: .utf8) else { return false }
        mqttClient?.publish(BrokerSettings.commandTopic, withString: json, qos: .qos1)
        return true
    }

    /// Tell the controller to install an available firmware version over OTA. The
    /// board fetches + verifies + applies + reboots (with automatic rollback if the
    /// new build won't run). Returns false if not connected.
    @discardableResult
    func sendOtaApply(_ version: String) -> Bool {
        guard connectionState == .connected else { return false }
        let cmd = SpaCommand(otaApply: version)
        guard let data = try? Self.encoder.encode(cmd),
              let json = String(data: data, encoding: .utf8) else { return false }
        mqttClient?.publish(BrokerSettings.commandTopic, withString: json, qos: .qos1)
        return true
    }

    private func applyOptimistic(_ cmd: SpaCommand) {
        guard var s = status else { return }
        if let v = cmd.setTemp { s.setpoint = v }
        if let v = cmd.pump1   { s.pump1 = v }
        if let v = cmd.pump2   { s.pump2 = v }
        if let v = cmd.pump3   { s.pump3 = v }
        if let v = cmd.light   { s.light = v }
        if let v = cmd.eco     { s.eco = v }
        if let v = cmd.maxJet  { s.maxJet = v }
        status = s
    }
}

// MARK: - CocoaMQTTDelegate
extension SpaViewModel: CocoaMQTTDelegate {

    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        DispatchQueue.main.async {
            guard mqtt === self.mqttClient else { return }   // ignore a retired client
            if ack == .accept {
                self.connectionState = .connected
                self.updateCheckedThisConnection = false
                mqtt.subscribe(BrokerSettings.statusTopic, qos: .qos1)
                mqtt.subscribe(BrokerSettings.onlineTopic, qos: .qos1)
            } else {
                self.connectionState = .error("Refused: \(ack)")
            }
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        guard let string = message.string else { return }
        let retained = message.retained

        if message.topic == BrokerSettings.onlineTopic {
            // "true"/"false" from the controller or its last will. Anything else
            // is left as nil rather than guessed at: an unparseable liveness flag
            // is not evidence either way.
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value: Bool? = (trimmed == "true")  ? true
                             : (trimmed == "false") ? false
                             : nil
            DispatchQueue.main.async {
                guard mqtt === self.mqttClient else { return }
                self.spaOnline = value
                if value == false {
                    // The tub is gone; whatever is on screen is a leftover.
                    self.lastStatusDate = nil
                    self.isStale = true
                } else {
                    self.vouchForRetainedStatus()
                }
            }
            return
        }

        guard message.topic == BrokerSettings.statusTopic,
              let data   = string.data(using: .utf8),
              let parsed = try? Self.decoder.decode(SpaStatus.self, from: data) else { return }
        DispatchQueue.main.async {
            guard mqtt === self.mqttClient else { return }   // ignore a retired client
            // A live status is proof the tub is talking, whatever the retained
            // online flag still says. The flag is only ever corrected by the
            // broker or the controller, and on reconnect the controller's "true"
            // can arrive after the first status.
            if !retained { self.spaOnline = true }
            self.ingest(parsed, retained: retained)
        }
    }

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        DispatchQueue.main.async {
            // Ignore disconnects from a client we've already retired (see connect()).
            // Without this, a superseded client's teardown schedules a phantom
            // reconnect and the app flaps between connected/disconnected.
            guard mqtt === self.mqttClient else { return }
            self.connectionState = .disconnected
            self.status = nil
            self.lastStatusDate = nil
            self.isStale = false
            // Unknown, not online: we have lost the broker, so we have lost our
            // only source of truth about the tub as well.
            self.spaOnline = nil
            self.alertMonitor.reset()   // re-baseline; don't re-notify on reconnect
            // Keep the pending 30-min offline alarm on an unexpected drop (the spa
            // may truly be down); only clear it when the user disconnects.
            if self.intentionalDisconnect {
                NotificationManager.shared.cancelOffline()
                return
            }
            // Single-flight the retry so overlapping disconnects can't stack timers.
            guard !self.reconnectPending else { return }
            self.reconnectPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self.reconnectPending = false
                if !self.intentionalDisconnect { self.connect() }
            }
        }
    }

    // (debug logging removed)

    // Answer the WebSocket transport's TLS auth challenge — without this the
    // handshake hangs forever (the library's default trust closure is a no-op).
    func mqttUrlSession(_ mqtt: CocoaMQTT, didReceiveTrust trust: SecTrust,
                        didReceiveChallenge challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    // Required stubs
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
}
