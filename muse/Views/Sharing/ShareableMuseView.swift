//
//  ShareableMuseView.swift
//  muse
//
//  Shareable card view for exporting muses as images
//  Two styles: Dark (dark bg, light text) and Minimal (light bg, dark text)
//

import SwiftUI

// MARK: - Share Card Format

enum ShareMuseFormat {
    case story  // 9:16 (1080x1920) - Instagram Story, TikTok
    case feed   // 4:3 (1440x1080) - Twitter, general feeds

    var size: CGSize {
        switch self {
        case .story: return CGSize(width: 1080, height: 1920)
        case .feed: return CGSize(width: 1440, height: 1080)
        }
    }

    var aspectRatio: CGFloat {
        size.width / size.height
    }
}

// MARK: - Share Card Style

enum ShareMuseStyle: String, CaseIterable {
    case dark = "dark"      // Dark background, light text
    case minimal = "minimal" // Light background, dark text

    var displayName: String {
        switch self {
        case .dark: return "dark"
        case .minimal: return "light"
        }
    }
}

// MARK: - Shareable Muse View

struct ShareableMuseView: View {
    let transcription: String
    let timestamp: Date
    let duration: TimeInterval
    let format: ShareMuseFormat
    let style: ShareMuseStyle
    let locationString: String?

    var body: some View {
        switch style {
        case .dark:
            darkStyleView
        case .minimal:
            minimalStyleView
        }
    }

    // MARK: - Dark Style (Dark background, light text - mirrors minimal)

    private var darkStyleView: some View {
        ZStack {
            // Deep warm black background
            Color(hex: "0F0E0D")

            VStack(spacing: 0) {
                // Location header (top right)
                if let location = locationString {
                    HStack {
                        Spacer()
                        locationView(location: location, isDark: true)
                    }
                    .padding(.horizontal, format == .story ? 48 : 60)
                    .padding(.top, format == .story ? 100 : 80)
                }

                Spacer()

                // Large text - no card, just text (mirrors minimal)
                darkContentView
                    .padding(.horizontal, format == .story ? 48 : 60)

                Spacer()

                // Footer
                darkFooterView
                    .padding(.bottom, format == .story ? 100 : 80)
            }
        }
        .frame(width: format.size.width, height: format.size.height)
    }

    private var darkContentView: some View {
        VStack(alignment: .leading, spacing: format == .story ? 32 : 28) {
            // Large opening quote mark - scales with text
            Text("\u{201C}")
                .font(.system(size: minimalQuoteSize, weight: .ultraLight, design: .serif))
                .foregroundColor(Color(hex: "2A2825"))
                .offset(x: -12, y: 16)

            // Transcription - the hero of the design
            Text(transcription)
                .font(.system(size: minimalTextSize, weight: .regular, design: .serif))
                .foregroundColor(Color(hex: "FAF8F5"))  // Warm white
                .lineSpacing(minimalLineSpacing)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var darkFooterView: some View {
        HStack(alignment: .bottom) {
            // Timestamp - larger and more prominent
            VStack(alignment: .leading, spacing: 6) {
                Text(formattedTime)
                    .font(.system(size: format == .story ? 34 : 40, weight: .medium, design: .monospaced))
                Text(formattedDate)
                    .font(.system(size: format == .story ? 34 : 40, weight: .medium, design: .monospaced))
            }
            .foregroundColor(Color(hex: "FAF8F5"))

            Spacer()

            // Branding
            Text("muse")
                .font(.system(size: format == .story ? 32 : 38, weight: .regular, design: .serif))
                .foregroundColor(Color(hex: "5A5550"))
        }
        .padding(.horizontal, format == .story ? 48 : 60)
    }

    // MARK: - Minimal Style (Stark black text, pure background)

    private var minimalStyleView: some View {
        ZStack {
            // Pure warm cream background
            Color(hex: "FAF8F5")

            VStack(spacing: 0) {
                // Location header (top right)
                if let location = locationString {
                    HStack {
                        Spacer()
                        locationView(location: location, isDark: false)
                    }
                    .padding(.horizontal, format == .story ? 48 : 60)
                    .padding(.top, format == .story ? 100 : 80)
                }

                Spacer()

                // Large bold text - no card, just text
                minimalContentView
                    .padding(.horizontal, format == .story ? 48 : 60)

                Spacer()

                // Minimal footer
                minimalFooterView
                    .padding(.bottom, format == .story ? 100 : 80)
            }
        }
        .frame(width: format.size.width, height: format.size.height)
    }

    private var minimalContentView: some View {
        VStack(alignment: .leading, spacing: format == .story ? 32 : 28) {
            // Large opening quote mark - scales with text
            Text("\u{201C}")
                .font(.system(size: minimalQuoteSize, weight: .ultraLight, design: .serif))
                .foregroundColor(Color(hex: "E0DAD2"))
                .offset(x: -12, y: 16)

            // Transcription - the hero of the design
            Text(transcription)
                .font(.system(size: minimalTextSize, weight: .regular, design: .serif))
                .foregroundColor(Color(hex: "1A1816"))  // Near black
                .lineSpacing(minimalLineSpacing)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var minimalQuoteSize: CGFloat {
        // Quote mark scales proportionally with text
        let charCount = transcription.count
        if format == .story {
            if charCount < 20 { return 240 }
            else if charCount < 50 { return 200 }
            else if charCount < 100 { return 160 }
            else { return 120 }
        } else {
            if charCount < 20 { return 220 }
            else if charCount < 50 { return 180 }
            else if charCount < 100 { return 140 }
            else { return 120 }
        }
    }

    private var minimalLineSpacing: CGFloat {
        // Tighter line spacing for larger text
        let charCount = transcription.count
        if format == .story {
            if charCount < 50 { return 12 }
            else if charCount < 130 { return 16 }
            else { return 20 }
        } else {
            if charCount < 50 { return 10 }
            else if charCount < 130 { return 14 }
            else { return 18 }
        }
    }

    private var minimalFooterView: some View {
        HStack(alignment: .bottom) {
            // Timestamp - larger and more prominent
            VStack(alignment: .leading, spacing: 6) {
                Text(formattedTime)
                    .font(.system(size: format == .story ? 34 : 40, weight: .medium, design: .monospaced))
                Text(formattedDate)
                    .font(.system(size: format == .story ? 34 : 40, weight: .medium, design: .monospaced))
            }
            .foregroundColor(Color(hex: "1A1816"))

            Spacer()

            // Branding
            Text("muse")
                .font(.system(size: format == .story ? 32 : 38, weight: .regular, design: .serif))
                .foregroundColor(Color(hex: "9A9590"))
        }
        .padding(.horizontal, format == .story ? 48 : 60)
    }

    // MARK: - Dynamic Text Sizes

    private var minimalTextSize: CGFloat {
        let charCount = transcription.count

        // Text is the hero - make it dominate the design
        // Bigger sizes across the board for more impact
        if format == .story {
            if charCount < 10 { return 180 }       // "Yes." - massive statement
            else if charCount < 20 { return 140 }  // Few words - huge
            else if charCount < 40 { return 110 }  // Short phrase
            else if charCount < 70 { return 88 }   // One sentence
            else if charCount < 110 { return 72 }
            else if charCount < 160 { return 58 }
            else if charCount < 220 { return 48 }
            else if charCount < 300 { return 40 }
            else if charCount < 400 { return 34 }
            else { return 28 }
        } else {
            if charCount < 10 { return 160 }
            else if charCount < 20 { return 120 }
            else if charCount < 40 { return 96 }
            else if charCount < 70 { return 78 }
            else if charCount < 110 { return 64 }
            else if charCount < 160 { return 52 }
            else if charCount < 220 { return 44 }
            else if charCount < 300 { return 36 }
            else if charCount < 400 { return 30 }
            else { return 26 }
        }
    }

    // MARK: - Formatters

    private var formattedDate: String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: timestamp)
        let day = calendar.component(.day, from: timestamp)
        let year = calendar.component(.year, from: timestamp) % 100
        return String(format: "%02d.%02d.%02d", month, day, year)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: timestamp).uppercased()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Location View

    private func locationView(location: String, isDark: Bool) -> some View {
        HStack(spacing: format == .story ? 10 : 12) {
            Image(systemName: "mappin")
                .font(.system(size: format == .story ? 24 : 28, weight: .regular))
            Text(location)
                .font(.system(size: format == .story ? 28 : 32, weight: .regular, design: .serif))
        }
        .foregroundColor(Color(hex: isDark ? "5A5550" : "9A9590"))
    }
}

// MARK: - Convenience Initializer

extension ShareableMuseView {
    init(muse: Muse, format: ShareMuseFormat, style: ShareMuseStyle) {
        self.transcription = muse.transcription
        self.timestamp = muse.createdAt
        self.duration = muse.duration
        self.format = format
        self.style = style
        self.locationString = muse.locationString
    }
}

// MARK: - Previews

#Preview("Dark - With Location") {
    ShareableMuseView(
        transcription: "Sometimes the quiet moments speak the loudest.",
        timestamp: Date(),
        duration: 5.2,
        format: .story,
        style: .dark,
        locationString: "shenzhen, china"
    )
    .frame(width: 360, height: 640)
}

#Preview("Dark - No Location") {
    ShareableMuseView(
        transcription: "Hello.",
        timestamp: Date(),
        duration: 1.2,
        format: .story,
        style: .dark,
        locationString: nil
    )
    .frame(width: 360, height: 640)
}

#Preview("Light - With Location") {
    ShareableMuseView(
        transcription: "Sometimes the quiet moments speak the loudest.",
        timestamp: Date(),
        duration: 5.2,
        format: .story,
        style: .minimal,
        locationString: "san francisco, usa"
    )
    .frame(width: 360, height: 640)
}

#Preview("Light - No Location") {
    ShareableMuseView(
        transcription: "Yes.",
        timestamp: Date(),
        duration: 0.8,
        format: .story,
        style: .minimal,
        locationString: nil
    )
    .frame(width: 360, height: 640)
}
