import CoreBluetooth
import Foundation
import UIKit

// MARK: - NUS UUIDs

enum NUS {
    static let service     = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rxChar      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")  // desktop writes here
    static let txChar      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")  // we notify here
}

// MARK: - BLE Peripheral Manager

@MainActor
class BLEPeripheralManager: NSObject, ObservableObject {

    // Public state
    @Published var isAdvertising = false
    @Published var isConnected = false
    @Published var centralName: String? = nil
    @Published var connectionError: String? = nil

    let model = BuddyModel()

    // CoreBluetooth
    private var peripheralManager: CBPeripheralManager!
    private var rxCharacteristic: CBMutableCharacteristic?
    private var txCharacteristic: CBMutableCharacteristic?
    private var subscribedCentral: CBCentral?

    // Line buffer for reassembling fragmented packets
    private var incomingBuffer = Data()

    // Encoder / decoder
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Keepalive watchdog
    private var watchdogTask: Task<Void, Never>?
    private var lastHeartbeat: Date = .now

    // Device name — advertised as "Claude <hostname>"
    private var deviceName: String {
        let host = UIDevice.current.name
        return "Claude \(host)"
    }

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil,
            options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - Public API

    func startAdvertising() {
        guard peripheralManager.state == .poweredOn else { return }
        guard !isAdvertising else { return }
        setupServices()
    }

    func stopAdvertising() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
    }

    func sendPermissionDecision(id: String, approve: Bool) {
        let decision = PermissionDecision(id: id, decision: approve ? "once" : "deny")
        sendJSON(decision)
    }

    // MARK: - Services setup

    private func setupServices() {
        // TX characteristic — notify only (device → desktop)
        let tx = CBMutableCharacteristic(
            type: NUS.txChar,
            properties: [.notify],
            value: nil,
            permissions: []
        )
        txCharacteristic = tx

        // RX characteristic — write without response (desktop → device)
        let rx = CBMutableCharacteristic(
            type: NUS.rxChar,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        rxCharacteristic = rx

        let service = CBMutableService(type: NUS.service, primary: true)
        service.characteristics = [tx, rx]

        peripheralManager.removeAllServices()
        peripheralManager.add(service)
    }

    private func beginAdvertising() {
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [NUS.service],
            CBAdvertisementDataLocalNameKey: deviceName
        ])
        isAdvertising = true
    }

    // MARK: - Outgoing data

    func sendJSON<T: Encodable>(_ value: T) {
        guard let central = subscribedCentral,
              let tx = txCharacteristic else { return }
        do {
            var data = try encoder.encode(value)
            data.append(UInt8(ascii: "\n"))
            // Fragment across MTU
            let mtu = central.maximumUpdateValueLength
            var offset = 0
            while offset < data.count {
                let chunk = data.subdata(in: offset..<min(offset + mtu, data.count))
                peripheralManager.updateValue(chunk, for: tx, onSubscribedCentrals: [central])
                offset += mtu
            }
        } catch {
            print("BLE encode error: \(error)")
        }
    }

    private func sendRawLine(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let central = subscribedCentral,
              let tx = txCharacteristic else { return }
        var line = data
        line.append(UInt8(ascii: "\n"))
        peripheralManager.updateValue(line, for: tx, onSubscribedCentrals: [central])
    }

    // MARK: - Incoming data parsing

    private func receivedData(_ data: Data) {
        incomingBuffer.append(data)
        // Process all complete lines
        while let newlineIdx = incomingBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = incomingBuffer[..<newlineIdx]
            incomingBuffer = incomingBuffer[incomingBuffer.index(after: newlineIdx)...]
            handleLine(lineData)
        }
    }

    private func handleLine(_ data: Data) {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // Dispatch on message shape
        if let evt = json["evt"] as? String, evt == "turn" {
            if let turn = try? decoder.decode(TurnEvent.self, from: data) {
                Task { @MainActor in model.apply(turnEvent: turn) }
            }
            return
        }

        if let cmd = json["cmd"] as? String {
            handleCommand(cmd, json: json, raw: data)
            return
        }

        // Heartbeat snapshot (no cmd/evt field)
        if json["total"] != nil || json["running"] != nil || json["msg"] != nil {
            lastHeartbeat = .now
            if let snapshot = try? decoder.decode(HeartbeatSnapshot.self, from: data) {
                Task { @MainActor in model.apply(snapshot: snapshot) }
            }
            return
        }

        // Time sync
        if let timeArr = json["time"] as? [Int] {
            print("Time sync: epoch=\(timeArr[0]) tzOffset=\(timeArr.count > 1 ? timeArr[1] : 0)")
            return
        }
    }

    private func handleCommand(_ cmd: String, json: [String: Any], raw: Data) {
        switch cmd {
        case "owner":
            let name = (json["name"] as? String) ?? "Claude"
            Task { @MainActor in model.ownerName = name }
            sendJSON(AckResponse(ack: "owner"))

        case "name":
            // Desktop is setting our display name — we can store it
            sendJSON(AckResponse(ack: "name"))

        case "status":
            let response = StatusResponse(data: StatusData(
                name: deviceName,
                sec: false,  // no encryption in this implementation
                sys: StatusData.SysInfo(up: model.appUptime, heap: 0)
            ))
            sendJSON(response)

        case "unpair":
            sendJSON(AckResponse(ack: "unpair"))

        case "char_begin":
            // Don't support folder push — let it time out
            // (don't ack char_begin; desktop will timeout gracefully)
            break

        default:
            // Generic ack for anything unknown
            sendJSON(AckResponse(ack: cmd, ok: false, error: "unsupported"))
        }
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(35))
                let gap = Date.now.timeIntervalSince(lastHeartbeat)
                if gap > 30, isConnected {
                    await MainActor.run {
                        handleDisconnect()
                    }
                }
            }
        }
    }

    private func handleDisconnect() {
        isConnected = false
        centralName = nil
        subscribedCentral = nil
        model.markDisconnected()
        watchdogTask?.cancel()
        // Re-advertise
        if peripheralManager.state == .poweredOn {
            beginAdvertising()
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheralManager: CBPeripheralManagerDelegate {

    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        DispatchQueue.main.async {
            switch peripheral.state {
            case .poweredOn:
                self.setupServices()
            case .poweredOff:
                self.isAdvertising = false
                self.isConnected = false
                self.connectionError = "Bluetooth is off"
            case .unauthorized:
                self.connectionError = "Bluetooth permission denied"
            default:
                break
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.connectionError = "Service error: \(error.localizedDescription)"
                return
            }
            self.beginAdvertising()
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.connectionError = "Advertising error: \(error.localizedDescription)"
                self.isAdvertising = false
            } else {
                self.isAdvertising = true
                self.connectionError = nil
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager,
                                       central: CBCentral,
                                       didSubscribeTo characteristic: CBCharacteristic) {
        DispatchQueue.main.async {
            guard characteristic.uuid == NUS.txChar else { return }
            self.subscribedCentral = central
            self.isConnected = true
            self.isAdvertising = false
            self.lastHeartbeat = .now
            self.startWatchdog()
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager,
                                       central: CBCentral,
                                       didUnsubscribeFrom characteristic: CBCharacteristic) {
        DispatchQueue.main.async {
            guard characteristic.uuid == NUS.txChar else { return }
            self.handleDisconnect()
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager,
                                       didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            peripheral.respond(to: request, withResult: .success)
            if let data = request.value {
                DispatchQueue.main.async {
                    self.receivedData(data)
                }
            }
        }
    }

    // Write without response
    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager,
                                       didReceiveWriteWithoutResponse request: CBATTRequest) {
        if let data = request.value {
            DispatchQueue.main.async {
                self.receivedData(data)
            }
        }
    }
}
