import Foundation
import CocoaMQTT

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

class SpaViewModel: NSObject, ObservableObject {
    @Published var status: SpaStatus?
    @Published var connectionState: ConnectionState = .disconnected

    private var mqttClient: CocoaMQTT?
    private var intentionalDisconnect = false

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

        let clientID = "SpaControl-\(UUID().uuidString.prefix(8))"
        let client   = CocoaMQTT(clientID: clientID, host: host, port: UInt16(port))
        client.username  = username.isEmpty ? nil : username
        client.password  = password.isEmpty ? nil : password
        client.enableSSL = (port == 8883)
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
        guard let data = try? Self.encoder.encode(command),
              let json = String(data: data, encoding: .utf8) else { return }
        mqttClient?.publish("spa/commands", withString: json, qos: .qos1)
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
        DispatchQueue.main.async { self.status = parsed }
    }

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        DispatchQueue.main.async {
            self.connectionState = .disconnected
            self.status = nil
            guard !self.intentionalDisconnect else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.connect() }
        }
    }

    // Required stubs
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
}
