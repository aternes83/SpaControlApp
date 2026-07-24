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

    /// Timestamp of the most recent valid `spa/status`. nil until the first arrives.
    @Published private(set) var lastStatusDate: Date?
    /// True when connected but no fresh status has arrived within `staleThreshold`.
    @Published private(set) var isStale: Bool = false

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
    private var stalenessTimer: Timer?

    /// Last observed fault state, for edge-triggered notifications. nil until the
    /// first status after a (re)connect, so a persistent fault does not re-notify
    /// on every reconnect.
    private var previousFault: (faulted: Bool, code: Int)?

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
        guard connectionState == .connected, let last = lastStatusDate else {
            if isStale { isStale = false }
            return
        }
        let stale = Date().timeIntervalSince(last) > Self.staleThreshold
        if stale != isStale { isStale = stale }
    }

    /// Apply a freshly decoded status: update state, freshness, history, and
    /// fault notifications. Always called on the main thread.
    private func ingest(_ parsed: SpaStatus) {
        status = parsed
        lastStatusDate = Date()
        isStale = false
        appendHistory(parsed)
        checkFaultTransition(parsed)
    }

    private func appendHistory(_ parsed: SpaStatus) {
        tempHistory.append(TempSample(date: Date(), tempF: parsed.tempF, setpoint: parsed.setpoint))
        let cutoff = Date().addingTimeInterval(-Self.historyWindow)
        tempHistory.removeAll { $0.date < cutoff }
        if tempHistory.count > Self.historyMaxCount {
            tempHistory.removeFirst(tempHistory.count - Self.historyMaxCount)
        }
    }

    /// Fire a local notification only on fault edges: newly faulted, a changed
    /// fault code, or a fault clearing. The first status after connect just sets
    /// the baseline (previousFault == nil) so we never notify on reconnect.
    private func checkFaultTransition(_ parsed: SpaStatus) {
        let current = (faulted: parsed.fault, code: parsed.faultCode)
        if let prev = previousFault {
            if current.faulted && (!prev.faulted || prev.code != current.code) {
                NotificationManager.shared.postFault(code: current.code)
            } else if !current.faulted && prev.faulted {
                NotificationManager.shared.postFaultCleared()
            }
        }
        previousFault = current
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
        mqttClient?.disconnect()

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
        mqttClient?.disconnect()
    }

    func sendCommand(_ command: SpaCommand) {
        // Optimistically reflect the change in the UI immediately; the board's
        // next status publish reconciles it (rather than waiting up to one
        // publish interval for the echo).
        applyOptimistic(command)
        guard let data = try? Self.encoder.encode(command),
              let json = String(data: data, encoding: .utf8) else { return }
        mqttClient?.publish("spa/commands", withString: json, qos: .qos1)
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
            if ack == .accept {
                self.connectionState = .connected
                mqtt.subscribe("spa/status", qos: .qos1)
            } else {
                self.connectionState = .error("Refused: \(ack)")
            }
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        guard let string = message.string,
              let data   = string.data(using: .utf8),
              let parsed = try? Self.decoder.decode(SpaStatus.self, from: data) else { return }
        DispatchQueue.main.async { self.ingest(parsed) }
    }

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        DispatchQueue.main.async {
            self.connectionState = .disconnected
            self.status = nil
            self.lastStatusDate = nil
            self.isStale = false
            self.previousFault = nil   // re-baseline; don't re-notify on reconnect
            guard !self.intentionalDisconnect else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.connect() }
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
