//
//  BLEConnectionManager.swift
//  muse
//
//  Direct CoreBluetooth connection manager for Ring
//  Handles scanning and connection directly, bypassing SDK overhead
//  Delegates to SDK for audio/HID features after connection
//
//  Based on analysis of official Ring app behavior:
//  - Instant reconnect on disconnect (~42ms)
//  - No delays after connection before sending commands
//  - Uses write-without-response for speed
//
//  BLE UUIDs:
//  - Service: BAE80001-4F05-4503-8E65-3AF1F7329D1F
//  - Write:   BAE80010-4F05-4503-8E65-3AF1F7329D1F
//  - Notify:  BAE80011-4F05-4503-8E65-3AF1F7329D1F
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE Constants

enum BLEConstants {
    static let bclServiceUUID = CBUUID(string: "BAE80001-4F05-4503-8E65-3AF1F7329D1F")
    static let writeCharacteristicUUID = CBUUID(string: "BAE80010-4F05-4503-8E65-3AF1F7329D1F")
    static let notifyCharacteristicUUID = CBUUID(string: "BAE80011-4F05-4503-8E65-3AF1F7329D1F")

    // Ring name prefixes to filter during scan
    static let ringNamePrefixes = ["BCL", "Ring"]

    // Reconnect timing
    static let instantReconnectDelay: TimeInterval = 0.05  // 50ms like official app
    static let scanTimeout: TimeInterval = 10.0
    static let connectionTimeout: TimeInterval = 5.0
}

// MARK: - Discovered Ring

struct DiscoveredRing: Identifiable, Equatable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let macAddress: String?
    let rssi: Int
    let advertisementData: [String: Any]

    static func == (lhs: DiscoveredRing, rhs: DiscoveredRing) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Connection State

enum BLEConnectionState: Equatable {
    case poweredOff
    case ready
    case scanning
    case connecting(UUID)
    case connected(UUID)
    case disconnected

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Connection Event

enum BLEConnectionEvent {
    case stateChanged(BLEConnectionState)
    case ringDiscovered(DiscoveredRing)
    case connectionReady(CBPeripheral, String?)  // Peripheral + MAC address
    case disconnected(Error?)
    case characteristicsReady(write: CBCharacteristic, notify: CBCharacteristic)
}

// MARK: - BLE Connection Manager

final class BLEConnectionManager: NSObject {

    // MARK: - Singleton

    static let shared = BLEConnectionManager()

    // MARK: - Publishers

    let eventPublisher = PassthroughSubject<BLEConnectionEvent, Never>()

    // MARK: - State

    private(set) var state: BLEConnectionState = .poweredOff {
        didSet {
            eventPublisher.send(.stateChanged(state))
        }
    }

    private(set) var discoveredRings: [DiscoveredRing] = []
    private(set) var connectedPeripheral: CBPeripheral?
    private(set) var connectedMacAddress: String?

    // Characteristics (exposed for SDK handoff)
    private(set) var writeCharacteristic: CBCharacteristic?
    private(set) var notifyCharacteristic: CBCharacteristic?

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var pendingPeripheral: CBPeripheral?
    private var savedPeripheralUUID: UUID?
    private var savedMacAddress: String?

    // Auto-reconnect
    private var shouldAutoReconnect = false
    private var reconnectTimer: Timer?

    // Timeouts
    private var scanTimer: Timer?
    private var connectionTimer: Timer?

    // MARK: - Init

    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "muse.ble.central"
        ])
        print("[BLE] Manager initialized")
    }

    // MARK: - Scanning

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[BLE] Cannot scan - Bluetooth not powered on")
            return
        }

        guard state == .ready || state == .disconnected else {
            print("[BLE] Cannot scan - state is \(state)")
            return
        }

        print("[BLE] Starting scan...")
        discoveredRings = []
        state = .scanning

        // Scan for ALL devices (rings don't advertise service UUID, only name)
        // We filter by name prefix in didDiscover callback
        centralManager.scanForPeripherals(
            withServices: nil,  // Scan all - filter by name
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Set scan timeout
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.scanTimeout, repeats: false) { [weak self] _ in
            self?.stopScanning()
        }
    }

    func stopScanning() {
        centralManager.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil

        if state == .scanning {
            state = .ready
        }
        print("[BLE] Scan stopped")
    }

    // MARK: - Connection

    func connect(to ring: DiscoveredRing, autoReconnect: Bool = true) {
        stopScanning()

        print("[BLE] Connecting to \(ring.name)...")
        state = .connecting(ring.id)
        pendingPeripheral = ring.peripheral
        shouldAutoReconnect = autoReconnect

        // Save for reconnection
        savedPeripheralUUID = ring.id
        savedMacAddress = ring.macAddress

        // Connect with options matching official app
        centralManager.connect(ring.peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])

        // Set connection timeout
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.connectionTimeout, repeats: false) { [weak self] _ in
            self?.handleConnectionTimeout()
        }
    }

    func connect(peripheralUUID: UUID, macAddress: String?, autoReconnect: Bool = true) {
        guard centralManager.state == .poweredOn else {
            print("[BLE] Cannot connect - Bluetooth not powered on")
            return
        }

        // Try to retrieve known peripheral
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [peripheralUUID])

        if let peripheral = peripherals.first {
            print("[BLE] Reconnecting to known peripheral: \(peripheralUUID)")

            let ring = DiscoveredRing(
                id: peripheralUUID,
                peripheral: peripheral,
                name: peripheral.name ?? "Ring",
                macAddress: macAddress,
                rssi: 0,
                advertisementData: [:]
            )
            connect(to: ring, autoReconnect: autoReconnect)
        } else {
            // Peripheral not in system cache - need to scan
            print("[BLE] Peripheral not cached, starting scan for reconnect...")
            savedPeripheralUUID = peripheralUUID
            savedMacAddress = macAddress
            shouldAutoReconnect = autoReconnect
            startScanForReconnect()
        }
    }

    private func startScanForReconnect() {
        guard centralManager.state == .poweredOn else { return }

        print("[BLE] Scanning for saved device...")
        state = .scanning

        // Scan all devices - filter by name in didDiscover
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Longer timeout for reconnect scan
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            print("[BLE] Reconnect scan timed out")
            self?.stopScanning()
            self?.state = .disconnected
        }
    }

    // MARK: - Disconnection

    func disconnect() {
        shouldAutoReconnect = false
        reconnectTimer?.invalidate()
        connectionTimer?.invalidate()

        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        cleanup()
        state = .disconnected
        print("[BLE] Disconnected (user initiated)")
    }

    private func cleanup() {
        connectedPeripheral = nil
        connectedMacAddress = nil
        pendingPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
    }

    // MARK: - Auto Reconnect

    private func scheduleReconnect() {
        guard shouldAutoReconnect else { return }
        guard let uuid = savedPeripheralUUID else { return }

        print("[BLE] Scheduling instant reconnect in \(BLEConstants.instantReconnectDelay * 1000)ms...")

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.instantReconnectDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("[BLE] Attempting instant reconnect...")
            self.connect(peripheralUUID: uuid, macAddress: self.savedMacAddress, autoReconnect: true)
        }
    }

    // MARK: - Timeout Handling

    private func handleConnectionTimeout() {
        print("[BLE] Connection timed out")

        if let peripheral = pendingPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        pendingPeripheral = nil
        state = .disconnected

        // Try reconnect if enabled
        scheduleReconnect()
    }

    // MARK: - MAC Address Extraction

    private func extractMacAddress(from advertisementData: [String: Any]) -> String? {
        // Try manufacturer data first (ring includes MAC in advertisement)
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           manufacturerData.count >= 8 {
            // Format: company ID (2 bytes) + MAC (6 bytes)
            let macBytes = manufacturerData.suffix(6)
            let macString = macBytes.map { String(format: "%02X", $0) }.joined(separator: ":")
            return macString
        }

        // Try local name parsing (some rings encode MAC in name like "BCL6031D77")
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           localName.hasPrefix("BCL") {
            let suffix = String(localName.dropFirst(3))
            if suffix.count >= 6 {
                // Convert to MAC format if it looks like hex
                let formatted = suffix.enumerated().compactMap { index, char -> String? in
                    if index > 0 && index % 2 == 0 { return ":\(char)" }
                    return String(char)
                }.joined()
                return formatted.uppercased()
            }
        }

        return nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEConnectionManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("[BLE] Central state: \(central.state.rawValue)")

        switch central.state {
        case .poweredOn:
            state = .ready

            // If we have a saved device and should reconnect, do it now
            if shouldAutoReconnect, let uuid = savedPeripheralUUID {
                connect(peripheralUUID: uuid, macAddress: savedMacAddress, autoReconnect: true)
            }

        case .poweredOff:
            state = .poweredOff
            cleanup()

        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        print("[BLE] Restoring state...")

        // Restore connected peripherals
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let peripheral = peripherals.first {
            print("[BLE] Restored peripheral: \(peripheral.identifier)")
            connectedPeripheral = peripheral
            peripheral.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {

        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"

        // Filter to rings by name prefix
        let isRing = BLEConstants.ringNamePrefixes.contains { name.hasPrefix($0) }
        guard isRing else { return }

        let macAddress = extractMacAddress(from: advertisementData)

        let ring = DiscoveredRing(
            id: peripheral.identifier,
            peripheral: peripheral,
            name: name,
            macAddress: macAddress,
            rssi: RSSI.intValue,
            advertisementData: advertisementData
        )

        print("[BLE] Discovered: \(name) (RSSI: \(RSSI), MAC: \(macAddress ?? "unknown"))")

        // Check if this is our saved device for reconnect
        if let savedUUID = savedPeripheralUUID, peripheral.identifier == savedUUID {
            print("[BLE] Found saved device, connecting...")
            connect(to: ring, autoReconnect: shouldAutoReconnect)
            return
        }

        // Check by MAC address
        if let savedMAC = savedMacAddress, let foundMAC = macAddress,
           savedMAC.replacingOccurrences(of: ":", with: "").uppercased() ==
           foundMAC.replacingOccurrences(of: ":", with: "").uppercased() {
            print("[BLE] Found device by MAC, connecting...")
            connect(to: ring, autoReconnect: shouldAutoReconnect)
            return
        }

        // Add to discovered list
        if !discoveredRings.contains(where: { $0.id == ring.id }) {
            discoveredRings.append(ring)
            eventPublisher.send(.ringDiscovered(ring))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BLE] Connected to \(peripheral.name ?? "ring") in \(connectionTimer != nil ? "fast" : "unknown") time")

        connectionTimer?.invalidate()
        connectionTimer = nil

        connectedPeripheral = peripheral
        connectedMacAddress = savedMacAddress
        pendingPeripheral = nil

        peripheral.delegate = self

        // Discover services immediately (no delay like official app)
        peripheral.discoverServices([BLEConstants.bclServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[BLE] Failed to connect: \(error?.localizedDescription ?? "unknown")")

        connectionTimer?.invalidate()
        pendingPeripheral = nil
        state = .disconnected

        eventPublisher.send(.disconnected(error))
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BLE] Disconnected: \(error?.localizedDescription ?? "clean")")

        let wasConnected = connectedPeripheral != nil
        cleanup()
        state = .disconnected

        eventPublisher.send(.disconnected(error))

        // Instant reconnect if enabled and was connected
        if wasConnected && shouldAutoReconnect {
            scheduleReconnect()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEConnectionManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("[BLE] Service discovery error: \(error)")
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            if service.uuid == BLEConstants.bclServiceUUID {
                print("[BLE] Found ring service, discovering characteristics...")
                peripheral.discoverCharacteristics(
                    [BLEConstants.writeCharacteristicUUID, BLEConstants.notifyCharacteristicUUID],
                    for: service
                )
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("[BLE] Characteristic discovery error: \(error)")
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.uuid == BLEConstants.writeCharacteristicUUID {
                writeCharacteristic = characteristic
                print("[BLE] Found write characteristic")
            } else if characteristic.uuid == BLEConstants.notifyCharacteristicUUID {
                notifyCharacteristic = characteristic
                print("[BLE] Found notify characteristic")

                // Subscribe to notifications immediately (like official app)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        // If we have both characteristics, we're ready
        if let write = writeCharacteristic, let notify = notifyCharacteristic {
            print("[BLE] Connection ready - characteristics discovered")
            state = .connected(peripheral.identifier)

            eventPublisher.send(.characteristicsReady(write: write, notify: notify))
            eventPublisher.send(.connectionReady(peripheral, connectedMacAddress))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[BLE] Notification state error: \(error)")
            return
        }

        print("[BLE] Notifications \(characteristic.isNotifying ? "enabled" : "disabled") for \(characteristic.uuid)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Note: We don't handle value updates here - the SDK handles protocol parsing
        // This is just for debugging
        if let data = characteristic.value {
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("[BLE] Received: \(hex)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[BLE] Write error: \(error)")
        }
    }
}
