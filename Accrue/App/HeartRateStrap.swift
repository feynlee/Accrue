import AccrueKit
@preconcurrency import CoreBluetooth
import Foundation
import Observation

/// A Bluetooth heart-rate strap or armband (Polar, Garmin, Wahoo and others), for people
/// without an Apple Watch. Pair it once in You; during a workout the phone connects to it and
/// feeds its heart rate to the run card's zones.
@Observable
@MainActor
final class HeartRateStrap: NSObject {
    enum Status: Equatable { case off, bluetoothOff, searching, connecting, connected }

    struct Found: Identifiable, Equatable {
        var id: UUID
        var name: String
    }

    private(set) var status: Status = .off
    private(set) var found: [Found] = []
    private(set) var bpm: Int?
    private(set) var savedID: UUID? = UserDefaults.standard.string(forKey: Keys.id).flatMap(UUID.init(uuidString:))
    private(set) var savedName: String? = UserDefaults.standard.string(forKey: Keys.name)

    /// Each reading, about once a second.
    @ObservationIgnored var onReading: ((Int) -> Void)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var seen: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var wantsConnection = false

    private enum Keys {
        static let id = "strapID"
        static let name = "strapName"
    }

    nonisolated(unsafe) private static let heartRateService = CBUUID(string: "180D")
    nonisolated(unsafe) private static let measurement = CBUUID(string: "2A37")

    /// Made-up strap for screenshots.
    func showDemo() {
        savedID = UUID()
        savedName = "Polar H10 A1B2C3D4"
        status = .connected
        bpm = 128
    }

    // MARK: Pairing (You)

    func startSearching() {
        found = []
        wantsScan = true
        status = .searching
        // Creating the manager asks for Bluetooth permission the first time.
        if let central { scanIfReady(central) } else { central = CBCentralManager(delegate: self, queue: .main) }
    }

    func stopSearching() {
        wantsScan = false
        central?.stopScan()
        if status == .searching { status = .off }
    }

    func pair(_ device: Found) {
        stopSearching()
        savedID = device.id
        savedName = device.name
        UserDefaults.standard.set(device.id.uuidString, forKey: Keys.id)
        UserDefaults.standard.set(device.name, forKey: Keys.name)
    }

    func forget() {
        disconnect()
        savedID = nil
        savedName = nil
        UserDefaults.standard.removeObject(forKey: Keys.id)
        UserDefaults.standard.removeObject(forKey: Keys.name)
    }

    // MARK: During a workout

    /// Connects to the paired strap and keeps reconnecting until `disconnect`.
    func connect() {
        guard savedID != nil, !wantsConnection else { return }
        wantsConnection = true
        status = .connecting
        if let central { connectIfReady(central) } else { central = CBCentralManager(delegate: self, queue: .main) }
    }

    func disconnect() {
        wantsConnection = false
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        bpm = nil
        if status != .searching { status = .off }
    }

    private func scanIfReady(_ central: CBCentralManager) {
        guard wantsScan, central.state == .poweredOn else { return }
        // Straps already connected to this phone (by another app) don't advertise.
        for device in central.retrieveConnectedPeripherals(withServices: [Self.heartRateService]) {
            add(device, advertisedName: nil)
        }
        central.scanForPeripherals(withServices: [Self.heartRateService])
    }

    private func connectIfReady(_ central: CBCentralManager) {
        guard wantsConnection, central.state == .poweredOn, let savedID else { return }
        guard let device = central.retrievePeripherals(withIdentifiers: [savedID]).first else { return }
        peripheral = device
        device.delegate = self
        central.connect(device)
    }

    private func add(_ device: CBPeripheral, advertisedName: String?) {
        seen[device.identifier] = device
        guard !found.contains(where: { $0.id == device.identifier }) else { return }
        found.append(Found(id: device.identifier, name: device.name ?? advertisedName ?? "Heart rate monitor"))
    }

    private func stateChanged(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            if wantsScan || wantsConnection { status = .bluetoothOff }
            return
        }
        if wantsScan { status = .searching }
        if wantsConnection { status = .connecting }
        scanIfReady(central)
        connectIfReady(central)
    }

    private func lost(_ device: CBPeripheral) {
        bpm = nil
        guard wantsConnection, device.identifier == peripheral?.identifier else { return }
        // Out of range or the strap slept: a pending connect has no timeout, so it comes back by itself.
        status = .connecting
        central?.connect(device)
    }

    private func received(_ bytes: [UInt8]) {
        guard let value = HeartRateMeasurement.bpm(from: bytes) else { return }
        bpm = value
        status = .connected
        onReading?(value)
    }
}

extension HeartRateStrap: CBCentralManagerDelegate {
    // The manager runs on the main queue, so its callbacks arrive on the main actor.
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { stateChanged(central) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        MainActor.assumeIsolated { add(peripheral, advertisedName: name) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            status = .connected
            peripheral.discoverServices([Self.heartRateService])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        MainActor.assumeIsolated { lost(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: (any Error)?) {
        MainActor.assumeIsolated { lost(peripheral) }
    }
}

extension HeartRateStrap: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        for service in peripheral.services ?? [] where service.uuid == Self.heartRateService {
            peripheral.discoverCharacteristics([Self.measurement], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.measurement {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        MainActor.assumeIsolated { received(bytes) }
    }
}
