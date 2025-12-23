//
//  RingManager.swift
//  muse
//
//  Ring connection, reconnection, and audio management
//  Uses MuseSDK
//
//  Connection Strategy (v3.2 - Always Configure HID):
//  - CRITICAL: 300ms spacing between consecutive commands
//  - First connection: appEventBindRing() - clears ring data
//  - Reconnection: appEventBindRing() - fire and forget, always configure HID
//  - Rings have mics - always assume mic=true
//
//  Reconnection Strategy:
//  - Save MAC address and UUID on successful connection
//  - Track hasCompletedInitialBind to use correct command on reconnect
//  - Auto-reconnect on app launch if device was previously connected
//  - Use MAC address first (more reliable), fallback to UUID
//
//  Audio Recording:
//  - HID touch gesture triggers recording (tap-hold on ring)
//  - ADPCM packets collected with sequence numbers
//  - On release, complete audio session published for transcription
//

import Foundation
import MuseSDK
import Combine
import CoreBluetooth

// MARK: - Atomic Helper (Swift 6 safe)

/// Thread-safe boolean for continuation protection
private final class Atomic: @unchecked Sendable {
    private var _value: Bool
    private let lock = NSLock()

    init(_ value: Bool) {
        _value = value
    }

    /// Atomically sets to true if currently false. Returns true if successful.
    func setTrueIfFalse() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !_value {
            _value = true
            return true
        }
        return false
    }
}

// MARK: - Connection Mode

/// Toggle between direct BLE and SDK-based connection
/// Set to .directBLE for faster, more reliable connections (like official app)
/// Set to .sdk to use original SDK connection flow
enum RingConnectionMode {
    case directBLE   // Use BLEConnectionManager (recommended)
    case sdk         // Use SDK (fallback)
}

// MARK: - Ring Connection State

enum RingConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case reconnecting
    case binding
    case configuring  // HID setup in progress - block UI commands
    case connected

    var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .reconnecting: return "Reconnecting..."
        case .binding: return "Setting up..."
        case .configuring: return "Configuring..."
        case .connected: return "Connected"
        }
    }

    var isActive: Bool {
        switch self {
        case .scanning, .connecting, .reconnecting, .binding, .configuring:
            return true
        default:
            return false
        }
    }
}

// MARK: - Audio Packet (for streaming)

struct AudioPacket {
    let dataLength: Int
    let seq: Int
    let audioData: [Int]
    let isEnd: Bool
}

// MARK: - Complete Audio Session (after recording ends)

struct AudioSession {
    let packets: [(length: Int, seq: Int, audioData: [Int])]
    let startTime: Date
    let endTime: Date

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// Get sorted audio data as [Int] samples
    var sortedSamples: [Int] {
        packets.sorted { $0.seq < $1.seq }
            .flatMap { $0.audioData }
    }
}

// MARK: - UserDefaults Keys

private enum StorageKeys {
    static let savedMacAddress = "muse_ring_mac"
    static let savedUUID = "muse_ring_uuid"
    static let savedDeviceName = "muse_ring_name"
    static let customMuseName = "muse_custom_name"  // User-defined name for their ring
    static let lastBatteryLevel = "muse_last_battery"
    static let hasCompletedInitialBind = "muse_ring_bound"  // Track if ring has been bound before
}

// MARK: - SDK Timing Constants
// From SDK documentation: commandsguide.md

private enum SDKTiming {
    /// Wait 3 seconds after BLE connection before sending any commands
    /// "After a successful Bluetooth connection, it is recommended to wait 3 seconds
    /// before sending commands to prevent the device from being unprepared and the command from timing out."
    static let postConnectionDelay: UInt64 = 3_000_000_000  // 3 seconds in nanoseconds

    /// Spacing between consecutive commands (minimum 300ms)
    /// "Each instruction should be executed approximately 300ms apart"
    static let interCommandDelay: UInt64 = 300_000_000  // 300ms in nanoseconds

    /// Timeout for waiting for command responses
    static let commandTimeout: TimeInterval = 10.0
}

// MARK: - Ring Manager

@MainActor
@Observable
final class RingManager {

    // Singleton
    static let shared = RingManager()

    // MARK: - Connection Mode Configuration

    /// Switch between direct BLE (faster) and SDK connection (fallback)
    /// NOTE: Direct BLE doesn't work because SDK has its own CBCentralManager
    /// that doesn't see our connected peripheral. Must use SDK mode.
    private let connectionMode: RingConnectionMode = .sdk

    // MARK: - Published State

    var state: RingConnectionState = .disconnected
    var scannedDevices: [BCLDeviceInfoModel] = []
    var batteryLevel: Int = 0
    var deviceName: String?
    var firmwareVersion: String?
    var macAddress: String?

    // Audio
    var isRecording = false
    var isMicrophoneSupported = false

    // Charging State
    var isCharging = false
    var chargingState: String = ""  // "Charging", "Charged", or ""

    // HID Mode (voice vs music control)
    var isMusicControlMode = false

    // Snap photo gesture mode (finger snap triggers camera shutter)
    var isSnapPhotoEnabled = false

    // Ring capabilities (from bind response)
    var isGestureMusicControlSupported = false

    // MARK: - Audio Publishers

    /// Real-time audio packets (for waveform visualization)
    let audioPacketPublisher = PassthroughSubject<AudioPacket, Never>()

    /// Complete audio session when recording ends (for transcription)
    let audioSessionPublisher = PassthroughSubject<AudioSession, Never>()

    // MARK: - Private Audio State

    private var currentPackets: [(length: Int, seq: Int, audioData: [Int])] = []
    private var recordingStartTime: Date?
    private var silenceTimer: Timer?

    // MARK: - BLE Connection Manager (for direct BLE mode)

    private var bleManager: BLEConnectionManager { BLEConnectionManager.shared }
    private var bleSubscription: AnyCancellable?

    /// Discovered rings from BLE scan (published for UI updates)
    var discoveredBLERings: [DiscoveredRing] = []

    // MARK: - Computed Properties

    var isConnected: Bool {
        state == .connected
    }

    var isScanning: Bool {
        state == .scanning
    }

    /// Whether we have a previously saved device to reconnect to
    var hasSavedDevice: Bool {
        savedMacAddress != nil || savedUUID != nil
    }

    /// Current recording duration (if recording)
    var recordingDuration: TimeInterval {
        guard isRecording, let start = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Saved Device Info (UserDefaults)

    private var savedMacAddress: String? {
        get { UserDefaults.standard.string(forKey: StorageKeys.savedMacAddress) }
        set { UserDefaults.standard.set(newValue, forKey: StorageKeys.savedMacAddress) }
    }

    private var savedUUID: String? {
        get { UserDefaults.standard.string(forKey: StorageKeys.savedUUID) }
        set { UserDefaults.standard.set(newValue, forKey: StorageKeys.savedUUID) }
    }

    private var savedDeviceName: String? {
        get { UserDefaults.standard.string(forKey: StorageKeys.savedDeviceName) }
        set { UserDefaults.standard.set(newValue, forKey: StorageKeys.savedDeviceName) }
    }

    /// User-defined custom name for their ring (public so it can be edited from UI)
    var customMuseName: String? {
        get { UserDefaults.standard.string(forKey: StorageKeys.customMuseName) }
        set { UserDefaults.standard.set(newValue, forKey: StorageKeys.customMuseName) }
    }

    /// Display name: custom name if set, otherwise device name
    var displayName: String? {
        customMuseName ?? deviceName
    }

    private var lastKnownBattery: Int {
        get { UserDefaults.standard.integer(forKey: StorageKeys.lastBatteryLevel) }
        set { UserDefaults.standard.set(newValue, forKey: StorageKeys.lastBatteryLevel) }
    }

    /// Track if we've completed initial bind (determines bind vs connect command)
    private var hasCompletedInitialBind: Bool {
        get { UserDefaults.standard.bool(forKey: StorageKeys.hasCompletedInitialBind) }
        set { UserDefaults.standard.set(newValue, forKey: StorageKeys.hasCompletedInitialBind) }
    }

    // MARK: - Private

    private var currentDevice: BCLDeviceInfoModel?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3

    private init() {
        print("[RingManager] Initialized (mode: \(connectionMode))")

        // Restore last known device name for UI
        if let name = savedDeviceName {
            deviceName = name
        }

        // Subscribe to BLE events if using direct BLE mode
        if connectionMode == .directBLE {
            setupBLESubscription()
        }
    }

    // MARK: - BLE Event Subscription

    private func setupBLESubscription() {
        bleSubscription = bleManager.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    self?.handleBLEEvent(event)
                }
            }
    }

    private func handleBLEEvent(_ event: BLEConnectionEvent) {
        switch event {
        case .stateChanged(let bleState):
            handleBLEStateChange(bleState)

        case .ringDiscovered(let ring):
            handleBLERingDiscovered(ring)

        case .connectionReady(let peripheral, let mac):
            handleBLEConnectionReady(peripheral: peripheral, macAddress: mac)

        case .disconnected(let error):
            handleBLEDisconnected(error: error)

        case .characteristicsReady:
            // Characteristics ready - we can now use SDK commands
            print("[RingManager] BLE characteristics ready")
        }
    }

    private func handleBLEStateChange(_ bleState: BLEConnectionState) {
        switch bleState {
        case .scanning:
            state = .scanning
        case .connecting:
            state = .connecting
        case .connected:
            state = .binding  // Will become .connected after bind
        case .disconnected, .ready, .poweredOff:
            if state != .disconnected {
                state = .disconnected
            }
        }
    }

    private func handleBLERingDiscovered(_ ring: DiscoveredRing) {
        // Convert to SDK model for UI compatibility
        // Note: We keep both for now during transition
        if !discoveredBLERings.contains(where: { $0.id == ring.id }) {
            discoveredBLERings.append(ring)
            print("[RingManager] BLE discovered: \(ring.name)")
        }
    }

    private func handleBLEConnectionReady(peripheral: CBPeripheral, macAddress: String?) {
        print("[RingManager] BLE connection ready, performing bind...")

        // Save device info
        savedUUID = peripheral.identifier.uuidString
        if let mac = macAddress {
            savedMacAddress = mac
            self.macAddress = mac
        }
        deviceName = peripheral.name ?? savedDeviceName

        // Now perform SDK bind to get device info and configure audio
        // The SDK will use the already-connected peripheral
        performBindAfterBLEConnect()
    }

    private func handleBLEDisconnected(error: Error?) {
        if let error = error {
            print("[RingManager] BLE disconnected with error: \(error.localizedDescription)")
        }

        // BLEConnectionManager handles auto-reconnect
        // We just update our state
        if state == .connected {
            state = .reconnecting
        }
    }

    /// Perform bind using SDK after BLE connection is established
    private func performBindAfterBLEConnect() {
        state = .binding

        // Note: No delay needed - official app sends immediately after characteristics ready
        BCLRingManager.shared.appEventBindRing(
            date: Date(),
            timeZone: BCLRingTimeZone.getCurrentSystemTimeZone()
        ) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let response):
                    self?.handleBindSuccess(response)

                case .failure(let error):
                    print("[RingManager] Bind failed after BLE connect: \(error)")
                    // Try with small delay as fallback
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                    self?.performBindWithRetry()
                }
            }
        }
    }

    private func performBindWithRetry() {
        BCLRingManager.shared.appEventBindRing(
            date: Date(),
            timeZone: BCLRingTimeZone.getCurrentSystemTimeZone()
        ) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let response):
                    self?.handleBindSuccess(response)
                case .failure(let error):
                    print("[RingManager] Bind retry failed: \(error)")
                    self?.state = .disconnected
                }
            }
        }
    }

    // MARK: - Scanning

    func startScanning() {
        guard state == .disconnected else {
            print("[RingManager] Cannot scan - state is \(state)")
            return
        }

        print("[RingManager] Starting scan (mode: \(connectionMode))...")
        state = .scanning
        scannedDevices = []
        discoveredBLERings = []

        if connectionMode == .directBLE {
            // Use direct BLE scanning (faster discovery)
            bleManager.startScanning()
        } else {
            // Use SDK scanning
            BCLRingManager.shared.startScan { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let devices):
                        // Filter to only rings
                        let rings = devices.filter { device in
                            device.localName?.hasPrefix("BCL") == true ||
                            device.localName?.hasPrefix("Ring") == true
                        }
                        self?.scannedDevices = rings
                        print("[RingManager] Found \(rings.count) ring(s)")

                    case .failure(let error):
                        print("[RingManager] Scan error: \(error)")
                    }
                }
            }
        }
    }

    func stopScanning() {
        if connectionMode == .directBLE {
            bleManager.stopScanning()
        } else {
            BCLRingManager.shared.stopScan()
        }

        if state == .scanning {
            state = .disconnected
        }
        print("[RingManager] Stopped scanning")
    }

    /// Get discovered rings (works for both BLE and SDK modes)
    var discoveredRings: [DiscoveredRing] {
        if connectionMode == .directBLE {
            return discoveredBLERings
        } else {
            // Convert SDK devices to DiscoveredRing for UI compatibility
            return scannedDevices.map { device in
                DiscoveredRing(
                    id: device.peripheral.identifier,
                    peripheral: device.peripheral,
                    name: device.localName ?? "Ring",
                    macAddress: device.macAddress,
                    rssi: Int(truncating: device.rssi ?? 0),
                    advertisementData: [:]
                )
            }
        }
    }

    // MARK: - Connection

    /// Connect to a discovered ring (BLE mode)
    func connect(to ring: DiscoveredRing) {
        guard state == .disconnected || state == .scanning else {
            print("[RingManager] Cannot connect - state is \(state)")
            return
        }

        stopScanning()
        reconnectAttempts = 0

        // Store device info for UI
        deviceName = ring.name
        if let mac = ring.macAddress, !mac.isEmpty {
            macAddress = mac
            savedMacAddress = mac
            print("[RingManager] Saved MAC from scan: \(mac)")
        }

        print("[RingManager] Connecting to \(ring.name) (mode: \(connectionMode))...")

        if connectionMode == .directBLE {
            // Direct BLE connection (instant, like official app)
            bleManager.connect(to: ring, autoReconnect: true)
        } else {
            // Fallback: Convert to SDK model and use SDK connect
            // This path is for compatibility if direct BLE doesn't work
            startSDKScanAndConnect(targetUUID: ring.id, targetMAC: ring.macAddress)
        }
    }

    /// Connect to SDK device model (legacy support)
    func connect(to device: BCLDeviceInfoModel) {
        guard state == .disconnected || state == .scanning else {
            print("[RingManager] Cannot connect - state is \(state)")
            return
        }

        stopScanning()
        state = .connecting
        currentDevice = device
        reconnectAttempts = 0
        print("[RingManager] Connecting to \(device.localName ?? "ring") via SDK...")

        // Store device info for UI immediately (MAC comes from scan advertisement)
        deviceName = device.localName
        if let mac = device.macAddress, !mac.isEmpty {
            macAddress = mac
            // Save MAC address immediately during scan/connect (before bind)
            savedMacAddress = mac
            print("[RingManager] Saved MAC from scan: \(mac)")
        }

        if connectionMode == .directBLE {
            // Convert SDK device to BLE ring and use direct connection
            let ring = DiscoveredRing(
                id: device.peripheral.identifier,
                peripheral: device.peripheral,
                name: device.localName ?? "Ring",
                macAddress: device.macAddress,
                rssi: Int(truncating: device.rssi ?? 0),
                advertisementData: [:]
            )
            bleManager.connect(to: ring, autoReconnect: true)
        } else {
            // Connect with auto-reconnect enabled (SDK handles reconnection)
            BCLRingManager.shared.startConnect(
                device: device,
                isAutoReconnect: true,
                autoReconnectTimeLimit: 600,  // 10 minutes
                autoReconnectMaxAttempts: 20
            ) { [weak self] result in
                Task { @MainActor in
                    self?.handleConnectionResult(result)
                }
            }
        }
    }

    /// Start SDK scan to find and connect to a specific device
    private func startSDKScanAndConnect(targetUUID: UUID, targetMAC: String?) {
        state = .connecting

        BCLRingManager.shared.startScan { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let devices):
                    // Find matching device
                    let match = devices.first { device in
                        device.peripheral.identifier == targetUUID ||
                        (targetMAC != nil && device.macAddress == targetMAC)
                    }

                    if let device = match {
                        self?.currentDevice = device
                        BCLRingManager.shared.stopScan()

                        BCLRingManager.shared.startConnect(
                            device: device,
                            isAutoReconnect: true,
                            autoReconnectTimeLimit: 600,
                            autoReconnectMaxAttempts: 20
                        ) { result in
                            Task { @MainActor in
                                self?.handleConnectionResult(result)
                            }
                        }
                    }

                case .failure(let error):
                    print("[RingManager] SDK scan failed: \(error)")
                    self?.state = .disconnected
                }
            }
        }
    }

    private func handleConnectionResult(_ result: Result<BCLDeviceInfoModel, BCLError>) {
        switch result {
        case .success(let deviceInfo):
            print("[RingManager] Connected to \(deviceInfo.localName ?? "ring")")
            state = .binding
            deviceName = deviceInfo.localName

            // Save device info for reconnection
            saveDeviceForReconnection(deviceInfo)

            // After connection, run the bind command
            performBind()

        case .failure(let error):
            print("[RingManager] Connection failed: \(error)")
            state = .disconnected
        }
    }

    // MARK: - Reconnection

    /// Attempt to reconnect to the last saved device
    func reconnectLastDevice() {
        guard hasSavedDevice else {
            print("[RingManager] No saved device to reconnect")
            return
        }

        guard state == .disconnected else {
            print("[RingManager] Cannot reconnect - state is \(state)")
            return
        }

        state = .reconnecting
        reconnectAttempts += 1
        print("[RingManager] Reconnecting to last device (attempt \(reconnectAttempts), mode: \(connectionMode))...")

        if connectionMode == .directBLE {
            // Use direct BLE reconnection (instant, like official app)
            if let uuidString = savedUUID, let uuid = UUID(uuidString: uuidString) {
                bleManager.connect(peripheralUUID: uuid, macAddress: savedMacAddress, autoReconnect: true)
            } else if let mac = savedMacAddress {
                // Start scan to find by MAC
                print("[RingManager] No UUID saved, scanning for MAC: \(mac.suffix(8))")
                bleManager.startScanning()
            }
        } else {
            // Use SDK reconnection
            // Try MAC address first (more reliable), then UUID
            if let mac = savedMacAddress {
                reconnectByMAC(mac)
            } else if let uuid = savedUUID {
                reconnectByUUID(uuid)
            }
        }
    }

    private func reconnectByMAC(_ mac: String) {
        print("[RingManager] Reconnecting by MAC: \(mac.suffix(8))")

        BCLRingManager.shared.startConnect(
            macAddress: mac,
            isAutoReconnect: true,
            autoReconnectTimeLimit: 600,
            autoReconnectMaxAttempts: 20
        ) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let deviceInfo):
                    print("[RingManager] MAC reconnect succeeded")
                    self?.handleConnectionResult(.success(deviceInfo))

                case .failure(let error):
                    print("[RingManager] MAC reconnect failed: \(error)")
                    // Fallback to UUID if MAC fails
                    if let uuid = self?.savedUUID {
                        self?.reconnectByUUID(uuid)
                    } else {
                        self?.handleReconnectFailure()
                    }
                }
            }
        }
    }

    private func reconnectByUUID(_ uuid: String) {
        print("[RingManager] Reconnecting by UUID: \(uuid.prefix(8))...")

        BCLRingManager.shared.startConnect(
            uuidString: uuid,
            isAutoReconnect: true,
            autoReconnectTimeLimit: 600,
            autoReconnectMaxAttempts: 20
        ) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let deviceInfo):
                    print("[RingManager] UUID reconnect succeeded")
                    self?.handleConnectionResult(.success(deviceInfo))

                case .failure(let error):
                    print("[RingManager] UUID reconnect failed: \(error)")
                    self?.handleReconnectFailure()
                }
            }
        }
    }

    private func handleReconnectFailure() {
        // In direct BLE mode, BLEConnectionManager handles retries
        if connectionMode == .directBLE {
            print("[RingManager] BLE reconnect will retry automatically")
            return
        }

        if reconnectAttempts < maxReconnectAttempts {
            print("[RingManager] Retrying reconnect...")
            // Delay before retry
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                reconnectLastDevice()
            }
        } else {
            print("[RingManager] Max reconnect attempts reached")
            state = .disconnected
            reconnectAttempts = 0
        }
    }

    // MARK: - Device Persistence

    private func saveDeviceForReconnection(_ device: BCLDeviceInfoModel) {
        savedUUID = device.peripheral.identifier.uuidString
        savedDeviceName = device.localName

        // MAC address may have been saved during connect() from scan data
        // Only update if device has a MAC and we don't have one saved
        if let mac = device.macAddress, !mac.isEmpty {
            savedMacAddress = mac
            macAddress = mac
        } else if let existingMac = savedMacAddress, !existingMac.isEmpty {
            // Keep existing MAC (was saved from scan data)
            macAddress = existingMac
        }
    }

    /// Forget the saved device (user wants to connect a new ring)
    func forgetDevice() {
        savedMacAddress = nil
        savedUUID = nil
        savedDeviceName = nil
        lastKnownBattery = 0
        hasCompletedInitialBind = false  // Reset so next connection does full bind

        deviceName = nil
        macAddress = nil
        currentDevice = nil
    }

    // MARK: - Bind/Connect (Compound Commands)

    /// Perform bind command
    /// - First connection: appEventBindRing (clears ring data)
    /// - Reconnection: appEventBindRing (simpler, no history sync - avoids data sync errors)
    private func performBind() {
        let isFirstBind = !hasCompletedInitialBind

        if isFirstBind {
            print("[RingManager] Performing FIRST BIND (will clear ring data)...")
        } else {
            print("[RingManager] Performing RECONNECT (preserving ring data)...")
        }

        Task {
            // CRITICAL: Wait 3 seconds after BLE connection before sending commands
            // From SDK docs: "After a successful Bluetooth connection, it is recommended to wait 3 seconds"
            print("[RingManager] Waiting 3 seconds for device readiness...")
            try? await Task.sleep(nanoseconds: SDKTiming.postConnectionDelay)

            if isFirstBind {
                await performFirstBind()
            } else {
                await performReconnectBind()
            }
        }
    }

    /// First time binding - uses appEventBindRing (clears ring data)
    private func performFirstBind() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            BCLRingManager.shared.appEventBindRing(
                date: Date(),
                timeZone: BCLRingTimeZone.getCurrentSystemTimeZone()
            ) { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let response):
                        self?.hasCompletedInitialBind = true  // Mark as bound
                        self?.handleBindSuccess(response)

                    case .failure(let error):
                        print("[RingManager] First bind failed: \(error)")
                        self?.state = .disconnected
                    }
                    continuation.resume()
                }
            }
        }
    }

    /// Reconnection - uses appEventBindRing (simpler, no history sync)
    /// Stage 1 fix: Avoid data sync errors that can destabilize the ring
    /// Always configures HID mode after, regardless of SDK response quality
    private func performReconnectBind() async {
        // Set configuring state - blocks UI commands until HID setup complete
        state = .configuring
        isMicrophoneSupported = true
        isGestureMusicControlSupported = true
        reconnectAttempts = 0

        // Fire off the bind command (don't wait for perfect response)
        BCLRingManager.shared.appEventBindRing(
            date: Date(),
            timeZone: BCLRingTimeZone.getCurrentSystemTimeZone()
        ) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let response):
                    // Try to extract info, but we'll configure HID regardless
                    if !response.firmwareVersion.isEmpty {
                        self?.firmwareVersion = response.firmwareVersion
                    }
                    let rawBattery = Int(response.batteryLevel)
                    if rawBattery > 0 {
                        self?.updateBatteryState(rawBattery: rawBattery)
                    }
                    print("[RingManager] Reconnect bind response received")

                case .failure(let error):
                    print("[RingManager] Reconnect bind error (continuing anyway): \(error)")
                }
            }
        }

        print("[RingManager] Reconnect: configuring HID mode...")

        // Wait for bind command to process, then configure HID
        try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay * 2)
        await configureHIDMode()

        // Only mark connected AFTER HID setup completes
        // This prevents UI from sending commands during setup
        state = .connected
        print("[RingManager] Reconnect complete - now accepting commands")
    }

    /// Handle successful connect response (similar to bind but different response type)
    private func handleConnectSuccess(_ response: BCLConnectRingResponse) {
        // Extract device capabilities (same fields as bind response)
        isMicrophoneSupported = response.isMicrophoneSupported
        firmwareVersion = response.firmwareVersion

        // Handle charging state
        let rawBattery = Int(response.batteryLevel)
        updateBatteryState(rawBattery: rawBattery)

        print("[RingManager] Reconnected (FW: \(response.firmwareVersion), battery: \(batteryLevel)%\(isCharging ? " charging" : ""))")

        state = .connected
        reconnectAttempts = 0

        // Configure audio mode with proper timing
        if isMicrophoneSupported && !isCharging {
            Task {
                try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)
                await configureHIDMode()
            }
        }
    }

    private func handleBindSuccess(_ response: BCLBindRingResponse) {
        // Extract device capabilities
        // Rings have microphones - always assume true for this hardware
        isMicrophoneSupported = true
        isGestureMusicControlSupported = true

        // Extract firmware version if available
        if !response.firmwareVersion.isEmpty {
            firmwareVersion = response.firmwareVersion
        }

        // Handle charging state (battery 101 = charging, 102 = charged)
        let rawBattery = Int(response.batteryLevel)
        updateBatteryState(rawBattery: rawBattery)

        let fwDisplay = firmwareVersion ?? "unknown"
        print("[RingManager] Bind success (FW: \(fwDisplay), battery: \(batteryLevel)%\(isCharging ? " charging" : ""))")

        reconnectAttempts = 0

        // Configure audio mode with proper timing
        // Only configure if not charging (audio doesn't work while charging)
        if isMicrophoneSupported && !isCharging {
            // Stay in configuring state until HID setup completes
            state = .configuring
            Task {
                try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)
                await configureHIDMode()
                state = .connected
                print("[RingManager] First bind complete - now accepting commands")
            }
        } else {
            // If charging, go directly to connected (no HID setup needed)
            state = .connected
            print("[RingManager] Connected (charging - skipping HID setup)")
        }
    }

    // MARK: - Battery State Handling

    /// Update battery state handling special values:
    /// - 0-100: Normal battery percentage
    /// - 101: Charging in progress
    /// - 102: Charging complete (fully charged)
    private func updateBatteryState(rawBattery: Int) {
        switch rawBattery {
        case 101:
            isCharging = true
            chargingState = "Charging"
            // Keep last known battery or show 0
            if lastKnownBattery > 0 && lastKnownBattery <= 100 {
                batteryLevel = lastKnownBattery
            } else {
                batteryLevel = 0
            }

        case 102:
            isCharging = true
            chargingState = "Charged"
            batteryLevel = 100
            lastKnownBattery = 100

        case 0...100:
            isCharging = false
            chargingState = ""
            batteryLevel = rawBattery
            lastKnownBattery = rawBattery

        default:
            break // Unknown value - keep current state
        }

    }

    // MARK: - HID Mode Configuration

    /// Configure HID mode for touch-triggered audio recording
    /// This sets up the ring so holding it triggers audio recording
    /// Uses SDK-recommended 300ms spacing between commands
    /// Includes retry logic for timeout errors
    private func configureHIDMode(retryCount: Int = 0) async {
        let maxRetries = 2

        // Allow during configuring (initial setup) or connected (mode switch)
        guard isMicrophoneSupported, !isCharging,
              state == .connected || state == .configuring else { return }

        // Step 1: Set audio format to ADPCM with retry
        let formatResult = await setAudioFormat()

        switch formatResult {
        case .success:
            break
        case .timeout:
            if retryCount < maxRetries {
                try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay * 3)
                await configureHIDMode(retryCount: retryCount + 1)
                return
            } else {
                return
            }
        case .failed:
            return
        }

        // Wait 300ms between commands (SDK requirement)
        try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)

        // Step 2: Set up audio data callback BEFORE setting HID mode
        setupAudioCallback()

        // Step 3: Set HID mode for touch audio
        let hidResult = await setHIDModeForAudio()

        switch hidResult {
        case .success:
            print("[RingManager] Voice mode ready")
        case .timeout:
            if retryCount < maxRetries {
                try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay * 3)
                await configureHIDMode(retryCount: retryCount + 1)
            }
        case .failed:
            break
        }
    }

    private enum AudioSetupResult {
        case success
        case timeout
        case failed
    }

    /// Set audio format with timeout detection
    private func setAudioFormat() async -> AudioSetupResult {
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let hasResumed = Atomic(false)

                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(SDKTiming.commandTimeout * 1_000_000_000))
                    if hasResumed.setTrueIfFalse() {
                        continuation.resume(returning: .timeout)
                    }
                }

                BCLRingManager.shared.setActivePushAudioInfo(audioType: .adpcm) { result in
                    timeoutTask.cancel()
                    guard hasResumed.setTrueIfFalse() else { return }

                    switch result {
                    case .success(let response):
                        // Status 0 = success, 1 = already set, 54 = variant success
                        if response.status == 0 || response.status == 1 || response.status == 54 {
                            continuation.resume(returning: .success)
                        } else {
                            continuation.resume(returning: .failed)
                        }
                    case .failure(let error):
                        let errorString = String(describing: error)
                        if errorString.contains("timeout") || errorString.contains("超时") {
                            continuation.resume(returning: .timeout)
                        } else {
                            continuation.resume(returning: .failed)
                        }
                    }
                }
            }
        } onCancel: { }
    }

    /// Set HID mode for audio recording with timeout protection
    private func setHIDModeForAudio() async -> AudioSetupResult {
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let hasResumed = Atomic(false)

                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(SDKTiming.commandTimeout * 1_000_000_000))
                    if hasResumed.setTrueIfFalse() {
                        continuation.resume(returning: .timeout)
                    }
                }

                BCLRingManager.shared.setHIDMode(
                    touchMode: 4,      // Audio upload (tap-hold to record)
                    gestureMode: 255,  // Off
                    systemType: 1,     // iOS
                    deviceModelName: BCLRingManager.shared.getMobileDeviceModelName(),
                    screenHeightPixel: BCLRingManager.shared.getMobileDeviceScreenHeightPixel(),
                    screenWidthPixel: BCLRingManager.shared.getMobileDeviceScreenWidthPixel()
                ) { result in
                    timeoutTask.cancel()
                    guard hasResumed.setTrueIfFalse() else { return }

                    switch result {
                    case .success:
                        continuation.resume(returning: .success)
                    case .failure(let error):
                        let errorString = String(describing: error)
                        if errorString.contains("timeout") || errorString.contains("超时") {
                            continuation.resume(returning: .timeout)
                        } else {
                            continuation.resume(returning: .failed)
                        }
                    }
                }
            }
        } onCancel: { }
    }

    /// Set up callback to receive audio data from ring touch gestures
    private func setupAudioCallback() {
        BCLRingManager.shared.hidTouchAudioDataBlock = { [weak self] dataLength, seq, audioData, isEnd in
            Task { @MainActor in
                self?.handleAudioPacket(dataLength: dataLength, seq: seq, audioData: audioData, isEnd: isEnd)
            }
        }
    }

    /// Handle incoming audio packet from ring
    private func handleAudioPacket(dataLength: Int, seq: Int, audioData: [Int], isEnd: Bool) {
        // Start recording on first audio data
        if !isRecording && !audioData.isEmpty {
            isRecording = true
            currentPackets = []
            recordingStartTime = Date()
        }

        // Collect packet if not empty
        if !audioData.isEmpty {
            currentPackets.append((length: dataLength, seq: seq, audioData: audioData))

            // Publish real-time packet for visualization
            let packet = AudioPacket(dataLength: dataLength, seq: seq, audioData: audioData, isEnd: isEnd)
            audioPacketPublisher.send(packet)
        }

        // Reset silence timer
        resetSilenceTimer()

        // Handle end signal
        if isEnd && isRecording {
            finalizeRecording()
        }
    }

    // MARK: - Silence Timer

    /// Reset silence timer (finalizes recording if no data for 1 second)
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRecording, !self.currentPackets.isEmpty else { return }
                self.finalizeRecording()
            }
        }
    }

    /// Finalize recording and publish audio session
    private func finalizeRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        guard isRecording else { return }
        isRecording = false

        let endTime = Date()
        let startTime = recordingStartTime ?? endTime

        guard !currentPackets.isEmpty else { return }

        let session = AudioSession(
            packets: currentPackets,
            startTime: startTime,
            endTime: endTime
        )

        print("[RingManager] Recording: \(String(format: "%.1f", session.duration))s, \(currentPackets.count) packets")

        // Publish for transcription
        audioSessionPublisher.send(session)

        // Clear state
        currentPackets = []
        recordingStartTime = nil
    }

    // MARK: - Refresh Connection Data

    /// Refresh battery level and device info using appEventRefreshRing
    func refresh() async {
        guard state == .connected else { return }

        let wasCharging = isCharging

        // Create callbacks (we don't need history sync for refresh, but SDK requires it)
        let callbacks = BCLDataSyncCallbacks(
            onProgress: { _, _, _, _ in },
            onStatusChanged: { _ in },
            onCompleted: { _ in },
            onError: { _ in }
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            BCLRingManager.shared.appEventRefreshRing(
                date: Date(),
                timeZone: BCLRingTimeZone.getCurrentSystemTimeZone(),
                filterTime: nil,
                callbacks: callbacks
            ) { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let response):
                        let rawBattery = Int(response.batteryLevel)
                        self?.updateBatteryState(rawBattery: rawBattery)
                        self?.firmwareVersion = response.firmwareVersion
                    case .failure:
                        break
                    }
                    continuation.resume()
                }
            }
        }

        // If ring was charging but now isn't, setup audio
        if wasCharging && !isCharging && isMicrophoneSupported {
            let delay: UInt64 = connectionMode == .sdk ? 500_000_000 : 100_000_000
            try? await Task.sleep(nanoseconds: delay)
            await configureHIDMode()
        }
    }

    // MARK: - Disconnection

    func disconnect() {
        silenceTimer?.invalidate()

        if connectionMode == .directBLE {
            bleManager.disconnect()
        } else {
            BCLRingManager.shared.disconnect()
        }

        handleDisconnection()
    }

    private func handleDisconnection() {
        state = .disconnected
        isRecording = false
        currentDevice = nil
        currentPackets = []
        recordingStartTime = nil
    }

    // MARK: - HID Mode Switching (Voice vs Music Control)

    /// Toggle between voice capture mode and music control mode
    /// - Parameter musicMode: true for music control, false for voice capture
    ///
    /// Music control mode:
    /// - touchMode=2: Tap ring = play/pause
    /// - gestureMode=2: Swipe in air = next/prev track
    /// Ring must be HID-paired at iOS system level (Settings > Bluetooth shows ring)
    func setMusicControlMode(_ musicMode: Bool) {
        guard state == .connected else {
            print("[RingManager] Cannot set mode - state is \(state) (must be connected)")
            return
        }

        print("[RingManager] Switching to \(musicMode ? "music" : "voice") mode")

        Task {
            // Add delay before switching modes (SDK requires 300ms between commands)
            try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)

            if musicMode {
                let success = await setHIDModeForMusic()
                isMusicControlMode = success
                isSnapPhotoEnabled = false  // Music mode uses gesture mode, disable snap photo
                if !success {
                    print("[RingManager] Failed to enable music mode")
                }
            } else {
                await configureHIDMode()
                isMusicControlMode = false
                isSnapPhotoEnabled = false  // Voice mode disables gesture mode
            }
        }
    }

    /// Set HID mode for music control
    /// From SDK docs:
    /// - touchMode=2: Music control via touch (tap = play/pause)
    ///
    /// Ring sends HID Consumer Control keys directly to iOS - no app callback needed.
    /// Ring must be HID-paired at iOS system level (Settings > Bluetooth shows ring).
    private func setHIDModeForMusic() async -> Bool {
        print("[RingManager] Setting music control mode (touch=2, gesture=off)...")

        return await withCheckedContinuation { continuation in
            let hasResumed = Atomic(false)

            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(SDKTiming.commandTimeout * 1_000_000_000))
                if hasResumed.setTrueIfFalse() {
                    print("[RingManager] setHIDMode timeout")
                    continuation.resume(returning: false)
                }
            }

            // Touch only for music control (no air gestures)
            // touchMode=2: Tap ring surface = play/pause
            // gestureMode=255: Off (not using air gestures for music)
            BCLRingManager.shared.setHIDMode(
                touchMode: 2,      // Music control via touch
                gestureMode: 255,  // Off
                systemType: 1,     // iOS
                deviceModelName: BCLRingManager.shared.getMobileDeviceModelName(),
                screenHeightPixel: BCLRingManager.shared.getMobileDeviceScreenHeightPixel(),
                screenWidthPixel: BCLRingManager.shared.getMobileDeviceScreenWidthPixel()
            ) { result in
                timeoutTask.cancel()
                guard hasResumed.setTrueIfFalse() else { return }

                switch result {
                case .success(let response):
                    print("[RingManager] Music mode set (status: \(response.status))")
                    continuation.resume(returning: response.status == 0 || response.status == 1)
                case .failure(let error):
                    print("[RingManager] Music mode failed: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Snap Photo Gesture Mode

    /// Toggle snap-to-photo gesture mode
    /// When enabled: Finger snap gesture triggers camera shutter (HID volume up key)
    /// Works with iOS Camera app and most camera apps
    func setSnapPhotoEnabled(_ enabled: Bool) {
        guard state == .connected else {
            print("[RingManager] Cannot set snap photo - state is \(state) (must be connected)")
            return
        }

        // Can't use snap photo while in music mode (conflicts with gesture mode)
        if enabled && isMusicControlMode {
            print("[RingManager] Disable music mode first before enabling snap photo")
            return
        }

        print("[RingManager] Setting snap photo: \(enabled)")

        Task {
            try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)

            if enabled {
                let success = await setHIDModeForSnapPhoto()
                isSnapPhotoEnabled = success
            } else {
                // Return to voice mode (disables gesture mode)
                await configureHIDMode()
                isSnapPhotoEnabled = false
            }
        }
    }

    /// Set HID mode for snap-to-photo gesture
    /// gestureMode=4 is Snap (photo) mode - finger snap triggers camera shutter
    private func setHIDModeForSnapPhoto() async -> Bool {
        print("[RingManager] Setting snap photo mode (touch=4, gesture=4)...")

        return await withCheckedContinuation { continuation in
            let hasResumed = Atomic(false)

            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(SDKTiming.commandTimeout * 1_000_000_000))
                if hasResumed.setTrueIfFalse() {
                    print("[RingManager] setHIDMode timeout for snap photo")
                    continuation.resume(returning: false)
                }
            }

            // touchMode=4: Audio upload (preserve voice recording)
            // gestureMode=4: Snap (photo) mode - finger snap triggers camera shutter
            BCLRingManager.shared.setHIDMode(
                touchMode: 4,      // Audio upload (voice recording still works)
                gestureMode: 4,    // Snap (photo) mode
                systemType: 1,     // iOS
                deviceModelName: BCLRingManager.shared.getMobileDeviceModelName(),
                screenHeightPixel: BCLRingManager.shared.getMobileDeviceScreenHeightPixel(),
                screenWidthPixel: BCLRingManager.shared.getMobileDeviceScreenWidthPixel()
            ) { result in
                timeoutTask.cancel()
                guard hasResumed.setTrueIfFalse() else { return }

                switch result {
                case .success(let response):
                    print("[RingManager] Snap photo mode set (status: \(response.status))")
                    continuation.resume(returning: response.status == 0 || response.status == 1)
                case .failure(let error):
                    print("[RingManager] Snap photo mode failed: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - ADPCM Conversion

    /// Convert ADPCM data to PCM using SDK's built-in converter
    func convertAdpcmToPcm(adpcmData: Data) -> Data? {
        return BCLRingManager.shared.convertAdpcmToPcm(adpcmData: adpcmData)
    }
}

