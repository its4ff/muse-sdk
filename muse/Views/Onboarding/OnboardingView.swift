//
//  OnboardingView.swift
//  muse
//
//  Simple onboarding flow for ring connection
//

import SwiftUI
import MuseSDK

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ringManager = RingManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.museBackground
                    .ignoresSafeArea()

                VStack(spacing: Spacing.xl) {
                    Spacer()

                    // Icon
                    ZStack {
                        Circle()
                            .stroke(Color.museBorder, lineWidth: 1)
                            .frame(width: 100, height: 100)

                        Image(systemName: "circle.circle")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(.museTextSecondary)
                    }

                    // Title
                    VStack(spacing: Spacing.sm) {
                        Text("connect your muse")
                            .font(.museTitle2)
                            .foregroundColor(.museText)

                        Text("scan for nearby devices to get started")
                            .font(.museCaption)
                            .foregroundColor(.museTextSecondary)
                    }

                    Spacer()

                    // Device list or scanning state
                    deviceList

                    Spacer()

                    // Scan button
                    Button {
                        if ringManager.isScanning {
                            ringManager.stopScanning()
                        } else {
                            ringManager.startScanning()
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            if ringManager.isScanning {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }

                            Text(ringManager.isScanning ? "scanning..." : "scan for devices")
                        }
                    }
                    .buttonStyle(.musePrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        ringManager.stopScanning()
                        dismiss()
                    }
                    .foregroundColor(.museTextSecondary)
                }
            }
        }
        .onChange(of: ringManager.isConnected) { _, connected in
            if connected {
                // Auto dismiss when connected
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Device List

    @ViewBuilder
    private var deviceList: some View {
        // Use discoveredRings which works for both BLE and SDK modes
        let rings = ringManager.discoveredRings

        if rings.isEmpty {
            if ringManager.isScanning {
                VStack(spacing: Spacing.sm) {
                    ProgressView()
                        .tint(.museTextTertiary)

                    Text("looking for devices...")
                        .font(.museCaption)
                        .foregroundColor(.museTextTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxl)
            } else {
                Text("no devices found")
                    .font(.museCaption)
                    .foregroundColor(.museTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xxl)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(rings) { ring in
                        DiscoveredRingRow(ring: ring) {
                            ringManager.connect(to: ring)
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
            .frame(maxHeight: 300)
        }
    }
}

// MARK: - Discovered Ring Row (for BLE mode)

struct DiscoveredRingRow: View {
    let ring: DiscoveredRing
    let onTap: () -> Void
    @State private var ringManager = RingManager.shared

    private var signalStrength: SignalStrength {
        SignalStrength.from(rssi: ring.rssi)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                // Ring icon with signal indicator
                ZStack {
                    Circle()
                        .fill(signalStrength.backgroundColor)
                        .frame(width: 44, height: 44)

                    Image(systemName: "circle.circle")
                        .font(.system(size: 18))
                        .foregroundColor(signalStrength.color)
                }

                // Name and info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text(ring.name)
                            .font(.museBodyMedium)
                            .foregroundColor(.museText)

                        // Signal quality badge
                        Text(signalStrength.label)
                            .font(.museMicro)
                            .foregroundColor(signalStrength.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(signalStrength.color.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: Spacing.sm) {
                        if let mac = ring.macAddress {
                            Text(mac.suffix(8).uppercased())
                                .font(.museMono)
                                .foregroundColor(.museTextTertiary)
                        }

                        // RSSI value
                        Text("\(ring.rssi) dBm")
                            .font(.museMono)
                            .foregroundColor(.museTextTertiary)
                    }
                }

                Spacer()

                // Signal bars + connection state
                HStack(spacing: Spacing.sm) {
                    SignalBars(rssi: ring.rssi)

                    if ringManager.state == .connecting || ringManager.state == .binding {
                        ProgressView()
                            .tint(.museTextTertiary)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.museTextTertiary)
                    }
                }
            }
            .padding(Spacing.md)
            .background(Color.museCard)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .stroke(Color.museBorder.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(ringManager.state == .connecting || ringManager.state == .binding)
    }
}

// MARK: - Device Row (legacy, for SDK mode)

struct DeviceRow: View {
    let device: DeviceInfo
    let onTap: () -> Void
    @State private var ringManager = RingManager.shared

    private var rssiValue: Int {
        device.rssi?.intValue ?? -100
    }

    private var signalStrength: SignalStrength {
        SignalStrength.from(rssi: rssiValue)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                // Ring icon with signal indicator
                ZStack {
                    Circle()
                        .fill(signalStrength.backgroundColor)
                        .frame(width: 44, height: 44)

                    Image(systemName: "circle.circle")
                        .font(.system(size: 18))
                        .foregroundColor(signalStrength.color)
                }

                // Name and info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text(device.localName ?? "Unknown Device")
                            .font(.museBodyMedium)
                            .foregroundColor(.museText)

                        // Signal quality badge
                        Text(signalStrength.label)
                            .font(.museMicro)
                            .foregroundColor(signalStrength.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(signalStrength.color.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    HStack(spacing: Spacing.sm) {
                        if let mac = device.macAddress {
                            Text(mac.suffix(8).uppercased())
                                .font(.museMono)
                                .foregroundColor(.museTextTertiary)
                        }

                        // RSSI value
                        Text("\(rssiValue) dBm")
                            .font(.museMono)
                            .foregroundColor(.museTextTertiary)
                    }
                }

                Spacer()

                // Signal bars + connection state
                HStack(spacing: Spacing.sm) {
                    SignalBars(rssi: rssiValue)

                    if ringManager.state == .connecting || ringManager.state == .binding {
                        ProgressView()
                            .tint(.museTextTertiary)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.museTextTertiary)
                    }
                }
            }
            .padding(Spacing.md)
            .background(Color.museCard)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .stroke(Color.museBorder.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(ringManager.state == .connecting || ringManager.state == .binding)
    }
}

// MARK: - Signal Strength

enum SignalStrength {
    case excellent
    case good
    case fair
    case weak
    case poor

    static func from(rssi: Int) -> SignalStrength {
        switch rssi {
        case -50...0: return .excellent
        case -60..<(-50): return .good
        case -70..<(-60): return .fair
        case -80..<(-70): return .weak
        default: return .poor
        }
    }

    var label: String {
        switch self {
        case .excellent: return "excellent"
        case .good: return "good"
        case .fair: return "fair"
        case .weak: return "weak"
        case .poor: return "poor"
        }
    }

    var color: Color {
        switch self {
        case .excellent: return .museConnected
        case .good: return .museConnected
        case .fair: return .museWarning
        case .weak: return .museWarning
        case .poor: return .museError
        }
    }

    var backgroundColor: Color {
        switch self {
        case .excellent, .good: return Color.museConnected.opacity(0.1)
        case .fair, .weak: return Color.museWarning.opacity(0.1)
        case .poor: return Color.museError.opacity(0.1)
        }
    }

    var filledBars: Int {
        switch self {
        case .excellent: return 4
        case .good: return 3
        case .fair: return 2
        case .weak: return 1
        case .poor: return 0
        }
    }
}

// MARK: - Signal Bars

struct SignalBars: View {
    let rssi: Int

    private var strength: SignalStrength {
        SignalStrength.from(rssi: rssi)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < strength.filledBars ? strength.color : Color.museBorder)
                    .frame(width: 3, height: CGFloat(6 + i * 3))
            }
        }
        .alignmentGuide(.bottom) { d in d[.bottom] }
    }
}

#Preview {
    OnboardingView()
}
