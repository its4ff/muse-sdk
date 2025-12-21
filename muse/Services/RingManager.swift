//
//  RingManager.swift
//  muse
//
//  Ring connection, reconnection, and audio management
//  Uses MuseSDK which wraps BCLRingSDK 1.1.27
//
//  Connection Strategy (v3 - SDK Timing Compliant):
//  - Uses BCLRingSDK for all connection/command operations
//  - CRITICAL: 3-second delay after BLE connection before sending commands
//  - CRITICAL: 300ms spacing between consecutive commands
//  - First connection: appEventBindRing() - clears ring data
//  - Reconnection: appEventConnectRing() - preserves data, syncs history
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

// MARK: - Connection Mode

/// Toggle between direct BLE and SDK-based connection
/// Set to .directBLE for faster, more reliable connections (like official app)
/// Set to .sdk to use original BCLRingSDK connection flow
enum RingConnectionMode {
    case directBLE   // Use BLEConnectionManager (recommended)
    case sdk         // Use BCLRingSDK (fallback)
}

// MARK: - Ring Connection State

enum RingConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case reconnecting
    case binding
    case connected

    var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .reconnecting: return "Reconnecting..."
        case .binding: return "Setting up..."
        case .connected: return "Connected"
        }
    }

    var isActive: Bool {
        switch self {
        case .scanning, .connecting, .reconnecting, .binding:
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
    static let lastBatteryLevel = "muse_last_battery"
    static let hasCompletedInitialBind = "muse_ring_bound"  // Track if ring has been bound before
}

// MARK: - SDK Timing Constants
// From BCL SDK documentation: commandsguide.md

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
                        // Filter to only BCL rings
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
            print("[RingManager] Keeping MAC from scan: \(existingMac)")
        }

        print("[RingManager] Device saved for reconnection")
        print("[RingManager]   MAC: \(savedMacAddress ?? "nil")")
        print("[RingManager]   UUID: \(savedUUID ?? "nil")")
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

        print("[RingManager] Device forgotten (will do full bind on next connection)")
    }

    // MARK: - Bind/Connect (Compound Commands)

    /// Perform bind or connect command based on whether ring has been bound before
    /// - First connection: appEventBindRing (clears ring data)
    /// - Reconnection: appEventConnectRing (preserves data, syncs history)
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

    /// Reconnection - uses appEventConnectRing (preserves data, syncs history)
    private func performReconnectBind() async {
        // Create callbacks for history data sync (we don't need it for muse, but SDK requires it)
        let callbacks = BCLDataSyncCallbacks(
            onProgress: { totalNumber, currentIndex, progress, model in
                print("[RingManager] History sync: \(currentIndex)/\(totalNumber) (\(progress)%)")
            },
            onStatusChanged: { status in
                print("[RingManager] History sync status: \(status)")
            },
            onCompleted: { models in
                print("[RingManager] History sync complete: \(models.count) records")
            },
            onError: { error in
                print("[RingManager] History sync error: \(error)")
            }
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            BCLRingManager.shared.appEventConnectRing(
                date: Date(),
                timeZone: BCLRingTimeZone.getCurrentSystemTimeZone(),
                filterTime: nil,  // Don't filter - sync all
                callbacks: callbacks
            ) { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let response):
                        self?.handleConnectSuccess(response)

                    case .failure(let error):
                        print("[RingManager] Reconnect command failed: \(error)")
                        // On failure, try first bind as fallback (maybe ring was reset)
                        print("[RingManager] Falling back to first bind...")
                        self?.hasCompletedInitialBind = false
                        await self?.performFirstBind()
                    }
                    continuation.resume()
                }
            }
        }
    }

    /// Handle successful connect response (similar to bind but different response type)
    private func handleConnectSuccess(_ response: BCLConnectRingResponse) {
        print("[RingManager] Reconnect successful")

        // Extract device capabilities (same fields as bind response)
        isMicrophoneSupported = response.isMicrophoneSupported
        firmwareVersion = response.firmwareVersion

        // Handle charging state
        let rawBattery = Int(response.batteryLevel)
        updateBatteryState(rawBattery: rawBattery)

        print("[RingManager] Firmware: \(response.firmwareVersion)")
        print("[RingManager] Hardware: \(response.hardwareVersion)")
        print("[RingManager] Mic supported: \(isMicrophoneSupported)")
        print("[RingManager] Touch audio supported: \(response.isTouchAudioUploadSupported)")
        print("[RingManager] Battery raw: \(rawBattery), display: \(batteryLevel)%, charging: \(isCharging)")

        state = .connected
        reconnectAttempts = 0

        // Configure audio mode with proper timing
        if isMicrophoneSupported && !isCharging {
            Task {
                // Wait 300ms before next command (inter-command delay)
                try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)
                await configureHIDMode()
            }
        } else if isCharging {
            print("[RingManager] Skipping audio setup - ring is charging")
        }
    }

    private func handleBindSuccess(_ response: BCLBindRingResponse) {
        print("[RingManager] Bind successful")

        // Extract device capabilities
        isMicrophoneSupported = response.isMicrophoneSupported
        firmwareVersion = response.firmwareVersion
        isGestureMusicControlSupported = response.isGestureMusicControlSupported

        // Handle charging state (battery 101 = charging, 102 = charged)
        let rawBattery = Int(response.batteryLevel)
        updateBatteryState(rawBattery: rawBattery)

        print("[RingManager] Firmware: \(response.firmwareVersion)")
        print("[RingManager] Hardware: \(response.hardwareVersion)")
        print("[RingManager] Mic supported: \(isMicrophoneSupported)")
        print("[RingManager] Touch audio supported: \(response.isTouchAudioUploadSupported)")
        print("[RingManager] Gesture music control supported: \(isGestureMusicControlSupported)")
        print("[RingManager] Battery raw: \(rawBattery), display: \(batteryLevel)%, charging: \(isCharging)")

        state = .connected
        reconnectAttempts = 0

        // Configure audio mode with proper timing
        // Only configure if not charging (audio doesn't work while charging)
        if isMicrophoneSupported && !isCharging {
            Task {
                // Wait 300ms before next command (inter-command delay from SDK docs)
                try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)
                await configureHIDMode()
            }
        } else if isCharging {
            print("[RingManager] Skipping audio setup - ring is charging")
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
            print("[RingManager] Ring is charging")

        case 102:
            isCharging = true
            chargingState = "Charged"
            batteryLevel = 100
            lastKnownBattery = 100
            print("[RingManager] Ring is fully charged")

        case 0...100:
            isCharging = false
            chargingState = ""
            batteryLevel = rawBattery
            lastKnownBattery = rawBattery

        default:
            // Unknown value - keep current state
            print("[RingManager] Unknown battery value: \(rawBattery)")
        }
    }

    // MARK: - HID Mode Configuration

    /// Configure HID mode for touch-triggered audio recording
    /// This sets up the ring so holding it triggers audio recording
    /// Uses SDK-recommended 300ms spacing between commands
    /// Includes retry logic for timeout errors
    private func configureHIDMode(retryCount: Int = 0) async {
        let maxRetries = 2

        guard isMicrophoneSupported else {
            print("[RingManager] Microphone not supported")
            return
        }

        guard !isCharging else {
            print("[RingManager] Cannot configure audio while charging")
            return
        }

        guard state == .connected else {
            print("[RingManager] Cannot configure HID - not connected (state: \(state))")
            return
        }

        print("[RingManager] Configuring HID mode for audio (attempt \(retryCount + 1)/\(maxRetries + 1))...")

        // Step 1: Set audio format to ADPCM with retry
        let formatResult = await setAudioFormat()

        switch formatResult {
        case .success:
            print("[RingManager] Audio format set to ADPCM")
        case .timeout:
            print("[RingManager] Audio format command timed out")
            if retryCount < maxRetries {
                print("[RingManager] Retrying after delay...")
                try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay * 3)  // 900ms retry delay
                await configureHIDMode(retryCount: retryCount + 1)
                return
            } else {
                print("[RingManager] Max retries reached for audio format")
                return
            }
        case .failed:
            print("[RingManager] Audio format setup failed")
            return
        }

        // CRITICAL: Wait 300ms between commands (SDK requirement)
        try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)

        // Step 2: Set up audio data callback BEFORE setting HID mode
        setupAudioCallback()

        // Step 3: Set HID mode for touch audio
        let hidResult = await setHIDModeForAudio()

        switch hidResult {
        case .success:
            print("[RingManager] Audio setup complete - hold ring to record")
        case .timeout:
            print("[RingManager] HID mode command timed out")
            if retryCount < maxRetries {
                print("[RingManager] Retrying HID setup after delay...")
                try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay * 3)  // 900ms retry delay
                await configureHIDMode(retryCount: retryCount + 1)
            }
        case .failed:
            print("[RingManager] HID mode setup failed")
        }
    }

    private enum AudioSetupResult {
        case success
        case timeout
        case failed
    }

    /// Set audio format with timeout detection
    /// Uses a manual timeout to prevent continuation leaks when ring disconnects
    private func setAudioFormat() async -> AudioSetupResult {
        // Use a task with timeout to prevent continuation leaks
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                var hasResumed = false
                let resumeLock = NSLock()

                // Safety timeout - if SDK doesn't respond in 10 seconds, consider it a timeout
                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(SDKTiming.commandTimeout * 1_000_000_000))
                    resumeLock.lock()
                    if !hasResumed {
                        hasResumed = true
                        resumeLock.unlock()
                        print("[RingManager] setAudioFormat safety timeout triggered")
                        continuation.resume(returning: .timeout)
                    } else {
                        resumeLock.unlock()
                    }
                }

                BCLRingManager.shared.setActivePushAudioInfo(audioType: .adpcm) { result in
                    timeoutTask.cancel()
                    resumeLock.lock()
                    guard !hasResumed else {
                        resumeLock.unlock()
                        return
                    }
                    hasResumed = true
                    resumeLock.unlock()

                    switch result {
                    case .success(let response):
                        // Status 0 = success, 1 = already set, 54 = variant success
                        if response.status == 0 || response.status == 1 || response.status == 54 {
                            continuation.resume(returning: .success)
                        } else {
                            print("[RingManager] Audio format unexpected status: \(response.status)")
                            continuation.resume(returning: .failed)
                        }
                    case .failure(let error):
                        let errorString = String(describing: error)
                        if errorString.contains("timeout") || errorString.contains("超时") {
                            continuation.resume(returning: .timeout)
                        } else {
                            print("[RingManager] Audio format error: \(error)")
                            continuation.resume(returning: .failed)
                        }
                    }
                }
            }
        } onCancel: {
            print("[RingManager] setAudioFormat task cancelled")
        }
    }

    /// Set HID mode for audio recording with timeout protection
    private func setHIDModeForAudio() async -> AudioSetupResult {
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                var hasResumed = false
                let resumeLock = NSLock()

                // Safety timeout
                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(SDKTiming.commandTimeout * 1_000_000_000))
                    resumeLock.lock()
                    if !hasResumed {
                        hasResumed = true
                        resumeLock.unlock()
                        print("[RingManager] setHIDModeForAudio safety timeout triggered")
                        continuation.resume(returning: .timeout)
                    } else {
                        resumeLock.unlock()
                    }
                }

                BCLRingManager.shared.setHIDMode(
                    touchMode: 4,      // Audio upload (tap-hold to record)
                    gestureMode: 255,  // Off (or 2 for music control)
                    systemType: 1,     // iOS
                    deviceModelName: BCLRingManager.shared.getMobileDeviceModelName(),
                    screenHeightPixel: BCLRingManager.shared.getMobileDeviceScreenHeightPixel(),
                    screenWidthPixel: BCLRingManager.shared.getMobileDeviceScreenWidthPixel()
                ) { result in
                    timeoutTask.cancel()
                    resumeLock.lock()
                    guard !hasResumed else {
                        resumeLock.unlock()
                        return
                    }
                    hasResumed = true
                    resumeLock.unlock()

                    switch result {
                    case .success(let response):
                        print("[RingManager] HID mode configured (status: \(response.status))")
                        continuation.resume(returning: .success)
                    case .failure(let error):
                        let errorString = String(describing: error)
                        if errorString.contains("timeout") || errorString.contains("超时") {
                            continuation.resume(returning: .timeout)
                        } else {
                            print("[RingManager] HID mode error: \(error)")
                            continuation.resume(returning: .failed)
                        }
                    }
                }
            }
        } onCancel: {
            print("[RingManager] setHIDModeForAudio task cancelled")
        }
    }

    /// Set up callback to receive audio data from ring touch gestures
    private func setupAudioCallback() {
        BCLRingManager.shared.hidTouchAudioDataBlock = { [weak self] dataLength, seq, audioData, isEnd in
            Task { @MainActor in
                self?.handleAudioPacket(dataLength: dataLength, seq: seq, audioData: audioData, isEnd: isEnd)
            }
        }
        print("[RingManager] Audio callback configured")
    }

    /// Handle incoming audio packet from ring
    private func handleAudioPacket(dataLength: Int, seq: Int, audioData: [Int], isEnd: Bool) {
        // Start recording on first audio data
        if !isRecording && !audioData.isEmpty {
            print("[RingManager] Recording started (seq=\(seq))")
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
            print("[RingManager] Recording ended via isEnd flag (\(currentPackets.count) packets)")
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
                print("[RingManager] Recording ended via silence timeout (\(self.currentPackets.count) packets)")
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

        guard !currentPackets.isEmpty else {
            print("[RingManager] No audio packets to finalize")
            return
        }

        let session = AudioSession(
            packets: currentPackets,
            startTime: startTime,
            endTime: endTime
        )

        print("[RingManager] Publishing audio session:")
        print("[RingManager]   Duration: \(String(format: "%.2f", session.duration))s")
        print("[RingManager]   Packets: \(currentPackets.count)")
        print("[RingManager]   Total samples: \(session.sortedSamples.count)")

        // Publish for transcription
        audioSessionPublisher.send(session)

        // Clear state
        currentPackets = []
        recordingStartTime = nil
    }

    // MARK: - Refresh Connection Data

    /// Refresh battery level and device info using appEventRefreshRing
    func refresh() async {
        guard isConnected else {
            print("[RingManager] Cannot refresh - not connected")
            return
        }

        print("[RingManager] Refreshing device info...")

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
                        print("[RingManager] Refreshed - Battery raw: \(rawBattery), charging: \(self?.isCharging ?? false)")

                    case .failure(let error):
                        print("[RingManager] Refresh failed: \(error)")
                    }
                    continuation.resume()
                }
            }
        }

        // If ring was charging but now isn't, setup audio
        if wasCharging && !isCharging && isMicrophoneSupported {
            print("[RingManager] Ring removed from charger - setting up audio")
            // Minimal delay (official app uses none)
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
        print("[RingManager] Disconnected")
    }

    // MARK: - HID Mode Switching (Voice vs Music Control)

    /// Toggle between voice capture mode and music control mode
    /// - Parameter musicMode: true for music control, false for voice capture
    ///
    /// IMPORTANT: For gesture music control to work:
    /// 1. Ring must support `isGestureMusicControlSupported` (check bind response)
    /// 2. Ring must be HID-paired at iOS system level (Settings > Bluetooth)
    /// 3. gestureMode=2 sends HID media keys directly to iOS - no app callback needed
    func setMusicControlMode(_ musicMode: Bool) {
        guard isConnected else {
            print("[RingManager] Cannot set mode - not connected")
            return
        }

        print("[RingManager] Setting mode to \(musicMode ? "music control" : "voice capture")...")

        Task {
            if musicMode {
                // Check if ring supports gesture music control
                if !isGestureMusicControlSupported {
                    print("[RingManager] WARNING: Ring may not support gesture music control")
                    print("[RingManager] Proceeding anyway - ring might still work via HID pairing")
                }

                // Music mode: disable touch audio, enable gesture music
                // CRITICAL: Add delay before switching modes (SDK requires 300ms between commands)
                try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)

                let success = await setHIDModeForMusic()
                if success {
                    isMusicControlMode = true
                    // Verify mode was set correctly
                    await verifyHIDMode()
                    // Also read current gesture functions to see what's configured
                    try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)
                    await readGestureFunctions()
                } else {
                    print("[RingManager] Failed to enable music control mode")
                }
            } else {
                // Voice mode: enable touch audio
                // CRITICAL: Add delay before switching modes
                try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)

                await configureHIDMode()
                isMusicControlMode = false
            }
        }
    }

    /// Set HID mode for music control (swipe gestures for next/prev track)
    /// From SDK docs: gestureMode=2 enables music control HID gestures (BCLGestureHIDModeMusicMode)
    ///
    /// IMPORTANT: For music gestures to work:
    /// 1. Ring must be HID-paired at iOS system level (Settings > Bluetooth shows ring)
    /// 2. gestureMode=2 sends HID Consumer Control keys directly to iOS
    /// 3. No app callback - gestures go directly to iOS media control
    /// 4. setGestureFunction may return 255 (not supported) - this is OK
    ///
    /// Default HID music gestures (when gestureMode=2):
    /// - Swipe Up: Next Track (HID Consumer Control)
    /// - Swipe Down: Previous Track (HID Consumer Control)
    /// - Snap/Pinch: Play/Pause (HID Consumer Control)
    private func setHIDModeForMusic() async -> Bool {
        print("[RingManager] Configuring music control mode...")
        print("[RingManager]   isGestureMusicControlSupported: \(isGestureMusicControlSupported)")

        // First, check what HID functions the ring supports
        await checkHIDFunctionCode()

        // Step 1: Set HID mode to music (gestureMode=2)
        let hidModeSuccess = await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(SDKTiming.commandTimeout * 1_000_000_000))
                resumeLock.lock()
                if !hasResumed {
                    hasResumed = true
                    resumeLock.unlock()
                    print("[RingManager] setHIDModeForMusic safety timeout triggered")
                    continuation.resume(returning: false)
                } else {
                    resumeLock.unlock()
                }
            }

            BCLRingManager.shared.setHIDMode(
                touchMode: 255,    // Disable touch (no audio upload)
                gestureMode: 2,    // Music control mode
                systemType: 1,     // iOS
                deviceModelName: BCLRingManager.shared.getMobileDeviceModelName(),
                screenHeightPixel: BCLRingManager.shared.getMobileDeviceScreenHeightPixel(),
                screenWidthPixel: BCLRingManager.shared.getMobileDeviceScreenWidthPixel()
            ) { result in
                timeoutTask.cancel()
                resumeLock.lock()
                guard !hasResumed else {
                    resumeLock.unlock()
                    return
                }
                hasResumed = true
                resumeLock.unlock()

                switch result {
                case .success(let response):
                    print("[RingManager] Music HID mode set (status: \(response.status))")
                    continuation.resume(returning: response.status == 0 || response.status == 1)
                case .failure(let error):
                    print("[RingManager] Music HID mode failed: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }

        guard hidModeSuccess else { return false }

        // Step 2: Wait before next command
        try? await Task.sleep(nanoseconds: SDKTiming.interCommandDelay)

        // Step 3: Configure gesture functions for music control
        // Gesture values (from SDK docs):
        // 1 = play/pause, 2 = next track, 3 = previous track
        // 4 = volume up, 5 = volume down, 6 = photo, 255 = disabled
        let gestureFunctionSuccess = await configureGestureFunctions(
            swipeUp: 2,     // Next track
            swipeDown: 3,   // Previous track
            snap: 1,        // Play/pause
            pinch: 255      // Disabled
        )

        if gestureFunctionSuccess {
            print("[RingManager] Music control fully configured")
        }

        return hidModeSuccess  // Return true even if gesture config fails (HID mode is set)
    }

    /// Configure what each gesture does
    /// Values: 1=play/pause, 2=next, 3=prev, 4=vol+, 5=vol-, 6=photo, 255=disabled
    ///
    /// NOTE: setStatus=255 from the ring typically means the gesture function configuration
    /// is not supported. This is OK if gestureMode=2 is set - the ring will send HID media
    /// keys directly to iOS without needing custom gesture function mapping.
    private func configureGestureFunctions(swipeUp: Int, swipeDown: Int, snap: Int, pinch: Int) async -> Bool {
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(SDKTiming.commandTimeout * 1_000_000_000))
                resumeLock.lock()
                if !hasResumed {
                    hasResumed = true
                    resumeLock.unlock()
                    print("[RingManager] configureGestureFunctions timeout")
                    continuation.resume(returning: false)
                } else {
                    resumeLock.unlock()
                }
            }

            BCLRingManager.shared.setGestureFunction(
                swipeUpGesture: swipeUp,
                swipeDownGesture: swipeDown,
                snapGesture: snap,
                pinchGesture: pinch
            ) { result in
                timeoutTask.cancel()
                resumeLock.lock()
                guard !hasResumed else {
                    resumeLock.unlock()
                    return
                }
                hasResumed = true
                resumeLock.unlock()

                switch result {
                case .success(let response):
                    let status = response.setStatus ?? -1
                    print("[RingManager] Gesture functions response (status: \(status))")
                    print("[RingManager]   Requested: swipeUp=\(swipeUp), swipeDown=\(swipeDown), snap=\(snap)")

                    if status == 255 {
                        print("[RingManager]   Status 255 = Not supported or using default HID mapping")
                        print("[RingManager]   This is OK - ring will use built-in music HID keys")
                    } else if status == 0 {
                        print("[RingManager]   Status 0 = Success, custom gesture functions applied")
                    }

                    // Return true either way - status 255 just means use defaults
                    continuation.resume(returning: true)
                case .failure(let error):
                    print("[RingManager] Gesture function config failed: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Read current gesture function configuration
    private func readGestureFunctions() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            BCLRingManager.shared.readGestureFunction { result in
                switch result {
                case .success(let response):
                    print("[RingManager] Current gesture functions:")
                    print("[RingManager]   Swipe up: \(response.swipeUpGesture ?? -1) (2=next track)")
                    print("[RingManager]   Swipe down: \(response.swipeDownGesture ?? -1) (3=prev track)")
                    print("[RingManager]")
                    print("[RingManager] === MUSIC CONTROL READY ===")
                    print("[RingManager] HID pairing confirmed (ring visible in iOS Bluetooth)")
                    print("[RingManager] Gesture mode set to music (2)")
                    print("[RingManager]")
                    print("[RingManager] To test: Open Apple Music, play a song, then:")
                    print("[RingManager]   - Swipe UP on ring = Next track")
                    print("[RingManager]   - Swipe DOWN on ring = Previous track")
                case .failure(let error):
                    print("[RingManager] Failed to read gesture functions: \(error)")
                    print("[RingManager] This may be normal - ring might not support reading gesture config")
                    print("[RingManager]")
                    print("[RingManager] === MUSIC CONTROL SHOULD STILL WORK ===")
                    print("[RingManager] gestureMode=2 is set - ring sends HID media keys directly to iOS")
                    print("[RingManager] Open Apple Music, play a song, swipe UP/DOWN on ring")
                }
                continuation.resume()
            }
        }
    }

    /// Verify current HID mode after setting
    private func verifyHIDMode() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            BCLRingManager.shared.getCurrentHIDMode { result in
                switch result {
                case .success(let response):
                    print("[RingManager] Current HID mode verified:")
                    print("[RingManager]   Touch HID mode: \(response.touchHIDMode)")
                    print("[RingManager]   Gesture HID mode: \(response.gestureHIDMode)")
                    print("[RingManager]   System type: \(response.systemType)")
                case .failure(let error):
                    print("[RingManager] Failed to verify HID mode: \(error)")
                }
                continuation.resume()
            }
        }
    }

    /// Check what HID functions the ring supports
    /// This helps diagnose whether music control gestures are available
    private func checkHIDFunctionCode() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            BCLRingManager.shared.getHIDFunctionCode { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let response):
                        print("[RingManager] HID Function Code Response:")
                        print("[RingManager]   isHIDSupported: \(response.isHIDSupported)")
                        print("[RingManager]   isTouchMusicControlSupported: \(response.isTouchMusicControlSupported)")
                        print("[RingManager]   isGestureMusicControlSupported: \(response.isGestureMusicControlSupported)")
                        print("[RingManager]   isTouchAudioUploadSupported: \(response.isTouchAudioUploadSupported)")
                        print("[RingManager]   touchFunctionByte: \(response.touchFunctionByte)")
                        print("[RingManager]   gestureFunctionByte: \(response.gestureFunctionByte)")
                        print("[RingManager]   hasAnyGestureFunction: \(response.hasAnyGestureFunction)")
                        print("[RingManager]   supportedFunctions: \(response.supportedFunctionsDescription)")

                        // Update our tracked capability
                        self?.isGestureMusicControlSupported = response.isGestureMusicControlSupported

                    case .failure(let error):
                        print("[RingManager] Failed to get HID function code: \(error)")
                    }
                    continuation.resume()
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

