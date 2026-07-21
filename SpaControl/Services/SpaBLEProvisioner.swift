import Foundation
import CoreBluetooth

enum BLEPhase: Equatable {
    case idle, unsupported, unauthorized, poweredOff
    case scanning, connecting, connected, disconnected
}

enum ProvisionPhase: Equatable {
    case idle
    case scanningNetworks
    case connecting
    case success(String)   // IP address
    case failed(String)    // reason
}

/// BLE client for the ESP32 spa controller's Nordic UART Service. Connects over
/// Bluetooth and drives the WiFi-provisioning protocol (scan / send credentials /
/// receive result). Used only by the WiFi setup wizard; normal operation is MQTT.
final class SpaBLEProvisioner: NSObject, ObservableObject {
    @Published private(set) var phase: BLEPhase = .idle
    @Published private(set) var networks: [WiFiNetwork] = []
    @Published private(set) var provision: ProvisionPhase = .idle
    @Published private(set) var deviceName: String?

    static let nus    = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rxUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")  // write
    static let txUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")  // notify
    static let deviceLocalName = "SpaControl"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxChar: CBCharacteristic?
    private var txChar: CBCharacteristic?

    private var wantScan = false
    private var rxBuffer = Data()
    private var collectingScan = false
    private var scanAccumulator: [WiFiNetwork] = []

    var isConnected: Bool { phase == .connected }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Intents

    /// Begin looking for the spa controller (starts once Bluetooth is powered on).
    func start() {
        networks = []
        provision = .idle
        wantScan = true
        updateForState()
    }

    /// Ask the controller to scan for nearby WiFi networks.
    func requestNetworkScan() {
        networks = []
        provision = .scanningNetworks
        send(["wifi_scan": 1])
    }

    /// Send WiFi credentials; the controller connects and reports the result.
    func provisionWiFi(ssid: String, password: String) {
        provision = .connecting
        send(["wifi_ssid": ssid, "wifi_pw": password])
    }

    /// Tear down the BLE session (call when the wizard closes).
    func stop() {
        if central.state == .poweredOn { central.stopScan() }
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil; rxChar = nil; txChar = nil
        wantScan = false
        phase = .idle; provision = .idle; networks = []
    }

    // MARK: - Internal

    private func updateForState() {
        switch central.state {
        case .poweredOn:    if wantScan && peripheral == nil { beginScan() }
        case .poweredOff:   phase = .poweredOff
        case .unauthorized: phase = .unauthorized
        case .unsupported:  phase = .unsupported
        default:            phase = .idle
        }
    }

    private func beginScan() {
        phase = .scanning
        // Firmware advertises only its name (no service UUID), so scan broadly
        // and match on the local name.
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    private func send(_ dict: [String: Any]) {
        guard let p = peripheral, let rx = rxChar,
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        p.writeValue(data, for: rx, type: .withResponse)
    }

    private func ingest(_ data: Data) {
        rxBuffer.append(data)
        while let range = nextJSONObjectRange() {
            let slice = rxBuffer.subdata(in: range)
            rxBuffer.removeSubrange(rxBuffer.startIndex..<range.upperBound)
            if let obj = try? JSONSerialization.jsonObject(with: slice) as? [String: Any] {
                handle(obj)
            }
        }
        if rxBuffer.count > 4096 { rxBuffer.removeAll() }   // drop garbage
    }

    /// Find the next complete top-level `{...}` object via brace counting — robust
    /// to notifications that fragment or coalesce JSON messages.
    private func nextJSONObjectRange() -> Range<Data.Index>? {
        guard let start = rxBuffer.firstIndex(of: UInt8(ascii: "{")) else { return nil }
        var depth = 0
        var i = start
        while i < rxBuffer.endIndex {
            switch rxBuffer[i] {
            case UInt8(ascii: "{"): depth += 1
            case UInt8(ascii: "}"):
                depth -= 1
                if depth == 0 { return start..<(i + 1) }
            default: break
            }
            i += 1
        }
        return nil
    }

    private func handle(_ obj: [String: Any]) {
        if let scan = obj["scan"] as? String {
            if scan == "begin" {
                collectingScan = true
                scanAccumulator = []
            } else if scan == "end" {
                collectingScan = false
                networks = dedupeSorted(scanAccumulator)
                if provision == .scanningNetworks { provision = .idle }
            }
            return
        }
        if let net = obj["net"] as? [String: Any], collectingScan {
            let ssid = net["s"] as? String ?? ""
            let rssi = (net["r"] as? NSNumber)?.intValue ?? -100
            let secured = ((net["sec"] as? NSNumber)?.intValue ?? 1) != 0
            if !ssid.isEmpty {
                scanAccumulator.append(WiFiNetwork(ssid: ssid, rssi: rssi, secured: secured))
            }
            return
        }
        if let wifi = obj["wifi"] as? String {
            switch wifi {
            case "connecting": provision = .connecting
            case "ok":         provision = .success(obj["ip"] as? String ?? "")
            case "fail":       provision = .failed(obj["err"] as? String ?? "unknown")
            default: break
            }
            return
        }
        // Anything else (e.g. status frames {"t":...}) is ignored here.
    }

    private func dedupeSorted(_ nets: [WiFiNetwork]) -> [WiFiNetwork] {
        var best: [String: WiFiNetwork] = [:]
        for n in nets where best[n.ssid] == nil || n.rssi > best[n.ssid]!.rssi {
            best[n.ssid] = n
        }
        return best.values.sorted { $0.rssi > $1.rssi }
    }
}

// MARK: - CoreBluetooth delegates

extension SpaBLEProvisioner: CBCentralManagerDelegate, CBPeripheralDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateForState()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard (advName ?? peripheral.name) == Self.deviceLocalName else { return }
        deviceName = advName ?? peripheral.name
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        wantScan = false
        phase = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.nus])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        phase = .disconnected
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        rxChar = nil; txChar = nil
        if phase != .idle { phase = .disconnected }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == Self.nus }) else {
            phase = .disconnected
            return
        }
        peripheral.discoverCharacteristics([Self.rxUUID, Self.txUUID], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] {
            if ch.uuid == Self.rxUUID { rxChar = ch }
            else if ch.uuid == Self.txUUID {
                txChar = ch
                peripheral.setNotifyValue(true, for: ch)
            }
        }
        if rxChar != nil && txChar != nil { phase = .connected }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.txUUID, let value = characteristic.value else { return }
        ingest(value)
    }
}
