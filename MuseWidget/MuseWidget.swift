//
//  MuseWidget.swift
//  MuseWidget
//
//  Status display widget showing ring battery, mode, and connection status
//

import WidgetKit
import SwiftUI

// MARK: - App Group for Widget Communication

enum MuseWidgetAppGroup {
    static let identifier = "group.-ff.com.muse"

    // Keys for shared data
    static let modeKey = "museGestureMode"
    static let batteryKey = "museRingBattery"
    static let isConnectedKey = "museRingConnected"
    static let isChargingKey = "museRingCharging"
    static let lastSyncKey = "museLastSync"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    // Getters
    static func getMode() -> String {
        sharedDefaults?.string(forKey: modeKey) ?? "voice"
    }

    static func getBattery() -> Int {
        sharedDefaults?.integer(forKey: batteryKey) ?? 0
    }

    static func isConnected() -> Bool {
        sharedDefaults?.bool(forKey: isConnectedKey) ?? false
    }

    static func isCharging() -> Bool {
        sharedDefaults?.bool(forKey: isChargingKey) ?? false
    }

    static func getLastSync() -> Date? {
        sharedDefaults?.object(forKey: lastSyncKey) as? Date
    }

    // Setters (called from main app)
    static func setMode(_ mode: String) {
        sharedDefaults?.set(mode, forKey: modeKey)
    }

    static func setBattery(_ level: Int) {
        sharedDefaults?.set(level, forKey: batteryKey)
    }

    static func setConnected(_ connected: Bool) {
        sharedDefaults?.set(connected, forKey: isConnectedKey)
    }

    static func setCharging(_ charging: Bool) {
        sharedDefaults?.set(charging, forKey: isChargingKey)
    }

    static func setLastSync(_ date: Date) {
        sharedDefaults?.set(date, forKey: lastSyncKey)
    }
}

// MARK: - Timeline Entry

struct MuseWidgetEntry: TimelineEntry {
    let date: Date
    let currentMode: String
    let batteryLevel: Int
    let isConnected: Bool
    let isCharging: Bool
    let lastSync: Date?
}

// MARK: - Timeline Provider

struct MuseWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MuseWidgetEntry {
        MuseWidgetEntry(
            date: Date(),
            currentMode: "voice",
            batteryLevel: 75,
            isConnected: true,
            isCharging: false,
            lastSync: Date()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MuseWidgetEntry) -> Void) {
        let entry = MuseWidgetEntry(
            date: Date(),
            currentMode: MuseWidgetAppGroup.getMode(),
            batteryLevel: MuseWidgetAppGroup.getBattery(),
            isConnected: MuseWidgetAppGroup.isConnected(),
            isCharging: MuseWidgetAppGroup.isCharging(),
            lastSync: MuseWidgetAppGroup.getLastSync()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MuseWidgetEntry>) -> Void) {
        let entry = MuseWidgetEntry(
            date: Date(),
            currentMode: MuseWidgetAppGroup.getMode(),
            batteryLevel: MuseWidgetAppGroup.getBattery(),
            isConnected: MuseWidgetAppGroup.isConnected(),
            isCharging: MuseWidgetAppGroup.isCharging(),
            lastSync: MuseWidgetAppGroup.getLastSync()
        )
        // Refresh every 15 minutes
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
        completion(timeline)
    }
}

// MARK: - Color Palette (matching muse app Theme.swift)

extension Color {
    static let widgetBackground = Color(red: 0.98, green: 0.97, blue: 0.96)           // #FAF8F5
    static let widgetBackgroundSecondary = Color(red: 0.96, green: 0.95, blue: 0.93)  // #F5F2ED
    static let widgetText = Color(red: 0.18, green: 0.16, blue: 0.15)                 // #2D2A26
    static let widgetTextSecondary = Color(red: 0.42, green: 0.40, blue: 0.38)        // #6B6560
    static let widgetTextTertiary = Color(red: 0.60, green: 0.58, blue: 0.56)         // #9A9590
    static let widgetAccent = Color(red: 0.24, green: 0.22, blue: 0.20)               // #3D3833
    static let widgetBorder = Color(red: 0.90, green: 0.88, blue: 0.85)               // #E5E0D9
    static let widgetSuccess = Color(red: 0.29, green: 0.40, blue: 0.25)              // #4A6741 (sage)
}

// MARK: - Battery Icon Helper

struct BatteryView: View {
    let level: Int
    let isCharging: Bool
    let size: CGFloat

    var batteryColor: Color {
        if isCharging { return .widgetSuccess }
        if level <= 20 { return .red.opacity(0.8) }
        if level <= 40 { return .orange.opacity(0.8) }
        return .widgetSuccess
    }

    var body: some View {
        HStack(spacing: 2) {
            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.7, weight: .medium))
                    .foregroundColor(batteryColor)
            }

            // Battery outline
            ZStack(alignment: .leading) {
                // Outer shell
                RoundedRectangle(cornerRadius: size * 0.15)
                    .stroke(Color.widgetTextSecondary, lineWidth: 1)
                    .frame(width: size * 1.8, height: size)

                // Fill
                RoundedRectangle(cornerRadius: size * 0.1)
                    .fill(batteryColor)
                    .frame(width: max(0, (size * 1.6) * CGFloat(level) / 100), height: size * 0.7)
                    .padding(.leading, size * 0.1)

                // Cap
                RoundedRectangle(cornerRadius: size * 0.1)
                    .fill(Color.widgetTextSecondary)
                    .frame(width: size * 0.15, height: size * 0.4)
                    .offset(x: size * 1.8)
            }
        }
    }
}

// MARK: - Small Widget View (Battery + Opens App)

struct MuseWidgetSmallView: View {
    let entry: MuseWidgetEntry

    var body: some View {
        VStack(spacing: 8) {
            // Title
            Text("muse")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundColor(.widgetText)

            Spacer()

            // Battery display
            if entry.isConnected || entry.batteryLevel > 0 {
                VStack(spacing: 6) {
                    BatteryView(level: entry.batteryLevel, isCharging: entry.isCharging, size: 14)

                    Text("\(entry.batteryLevel)%")
                        .font(.system(size: 24, weight: .light, design: .rounded))
                        .foregroundColor(.widgetText)
                }
            } else {
                // Not connected / no data
                VStack(spacing: 4) {
                    Image(systemName: "ring.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.widgetTextTertiary)

                    Text("open app")
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .foregroundColor(.widgetTextTertiary)
                }
            }

            Spacer()

            // Connection status dot
            HStack(spacing: 4) {
                Circle()
                    .fill(entry.isConnected ? Color.widgetSuccess : Color.widgetTextTertiary.opacity(0.5))
                    .frame(width: 6, height: 6)

                Text(entry.isConnected ? "connected" : "disconnected")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundColor(.widgetTextTertiary)
            }
        }
        .padding(14)
    }
}

// MARK: - Medium Widget View (Full Status Display)

struct MuseWidgetMediumView: View {
    let entry: MuseWidgetEntry

    var timeAgo: String {
        guard let lastSync = entry.lastSync else { return "—" }
        let interval = Date().timeIntervalSince(lastSync)

        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    var body: some View {
        HStack(spacing: 16) {
            // Left side - Battery & branding
            VStack(alignment: .leading, spacing: 8) {
                Text("muse")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundColor(.widgetText)

                Spacer()

                // Battery
                if entry.isConnected || entry.batteryLevel > 0 {
                    HStack(spacing: 8) {
                        BatteryView(level: entry.batteryLevel, isCharging: entry.isCharging, size: 12)

                        Text("\(entry.batteryLevel)%")
                            .font(.system(size: 20, weight: .light, design: .rounded))
                            .foregroundColor(.widgetText)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 20, weight: .light, design: .rounded))
                        .foregroundColor(.widgetTextTertiary)
                }

                Spacer()

                // Last sync
                Text("synced \(timeAgo)")
                    .font(.system(size: 9, weight: .regular, design: .serif))
                    .foregroundColor(.widgetTextTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right side - Status cards
            VStack(spacing: 8) {
                // Connection status
                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.isConnected ? Color.widgetSuccess : Color.widgetTextTertiary.opacity(0.5))
                        .frame(width: 6, height: 6)

                    Text(entry.isConnected ? "connected" : "disconnected")
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .foregroundColor(entry.isConnected ? .widgetText : .widgetTextTertiary)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.widgetBackgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Current mode
                HStack(spacing: 6) {
                    Image(systemName: entry.currentMode == "voice" ? "waveform" : "music.note")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.widgetTextSecondary)

                    Text(entry.currentMode)
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .foregroundColor(.widgetText)

                    Spacer()

                    Text("mode")
                        .font(.system(size: 9, weight: .regular, design: .serif))
                        .foregroundColor(.widgetTextTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.widgetBackgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Charging indicator (if charging)
                if entry.isCharging {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.widgetSuccess)

                        Text("charging")
                            .font(.system(size: 10, weight: .medium, design: .serif))
                            .foregroundColor(.widgetSuccess)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.widgetSuccess.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(width: 120)
        }
        .padding(14)
    }
}

// MARK: - Widget Entry View

struct MuseWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: MuseWidgetProvider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            MuseWidgetSmallView(entry: entry)
        case .systemMedium:
            MuseWidgetMediumView(entry: entry)
        default:
            MuseWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct MuseWidget: Widget {
    let kind: String = "MuseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MuseWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                MuseWidgetEntryView(entry: entry)
                    .containerBackground(Color.widgetBackground, for: .widget)
            } else {
                MuseWidgetEntryView(entry: entry)
                    .background(Color.widgetBackground)
            }
        }
        .configurationDisplayName("muse")
        .description("Ring status and battery level")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    MuseWidget()
} timeline: {
    MuseWidgetEntry(date: .now, currentMode: "voice", batteryLevel: 75, isConnected: true, isCharging: false, lastSync: Date())
    MuseWidgetEntry(date: .now, currentMode: "music", batteryLevel: 25, isConnected: true, isCharging: true, lastSync: Date().addingTimeInterval(-3600))
    MuseWidgetEntry(date: .now, currentMode: "voice", batteryLevel: 0, isConnected: false, isCharging: false, lastSync: nil)
}

#Preview(as: .systemMedium) {
    MuseWidget()
} timeline: {
    MuseWidgetEntry(date: .now, currentMode: "voice", batteryLevel: 75, isConnected: true, isCharging: false, lastSync: Date())
    MuseWidgetEntry(date: .now, currentMode: "music", batteryLevel: 100, isConnected: true, isCharging: true, lastSync: Date().addingTimeInterval(-300))
    MuseWidgetEntry(date: .now, currentMode: "voice", batteryLevel: 15, isConnected: false, isCharging: false, lastSync: Date().addingTimeInterval(-86400))
}
