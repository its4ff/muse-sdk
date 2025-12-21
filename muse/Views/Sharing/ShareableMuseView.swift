//
//  ShareableMuseView.swift
//  muse
//
//  Shareable card view for exporting muses as images
//  Two styles: Dark (espresso card) and Minimal (stark black text)
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
    case dark = "dark"      // Dark espresso card, cream text
    case minimal = "minimal" // Pure cream background, bold black text

    var displayName: String {
        switch self {
        case .dark: return "dark"
        case .minimal: return "minimal"
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

    var body: some View {
        switch style {
        case .dark:
            darkStyleView
        case .minimal:
            minimalStyleView
        }
    }

    // MARK: - Dark Style (Espresso card, cream text)

    private var darkStyleView: some View {
        ZStack {
            // Warm parchment gradient background
            LinearGradient(
                colors: [
                    Color(hex: "F5F2ED"),  // Soft cream
                    Color(hex: "EBE6DE"),  // Warm beige
                    Color(hex: "DDD6CA"),  // Deeper sand
                    Color(hex: "D0C7B8")   // Sand
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                Spacer()

                // Dark card
                darkContentCard
                    .padding(.horizontal, format == .story ? 44 : 56)

                // Timestamp below card
                darkTimestampView
                    .padding(.top, format == .story ? 28 : 24)

                Spacer()

                // Branding
                darkBrandingView
                    .padding(.bottom, format == .story ? 90 : 70)
            }
        }
        .frame(width: format.size.width, height: format.size.height)
    }

    private var darkContentCard: some View {
        VStack(alignment: .leading, spacing: format == .story ? 28 : 24) {
            // Transcription text - cream/white on dark
            Text(transcription)
                .font(.system(size: dynamicTextSize, weight: .regular, design: .serif))
                .foregroundColor(Color(hex: "FAF8F5"))  // Warm white
                .lineSpacing(format == .story ? 16 : 14)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // Duration badge
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: format == .story ? 16 : 18, weight: .medium))
                Text(formatDuration(duration))
                    .font(.system(size: format == .story ? 18 : 20, weight: .medium, design: .monospaced))
            }
            .foregroundColor(Color(hex: "A89F94"))  // Muted cream
            .padding(.top, 4)
        }
        .padding(format == .story ? 52 : 64)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: format == .story ? 28 : 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "3D3833"),  // Warm espresso
                            Color(hex: "2D2A26"),  // Deep charcoal
                            Color(hex: "1F1D1A")   // Near black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(
                    color: Color.black.opacity(0.4),
                    radius: 50,
                    x: 0,
                    y: 25
                )
        )
    }

    private var darkTimestampView: some View {
        HStack(spacing: 14) {
            Text(formattedTime)
                .font(.system(size: format == .story ? 26 : 30, weight: .medium, design: .monospaced))

            Text("·")
                .font(.system(size: format == .story ? 26 : 30, weight: .bold))

            Text(formattedDate)
                .font(.system(size: format == .story ? 26 : 30, weight: .medium, design: .monospaced))
        }
        .foregroundColor(Color(hex: "5C5650"))  // Darker warm gray
    }

    private var darkBrandingView: some View {
        HStack(spacing: 14) {
            Image(systemName: "circle.circle")
                .font(.system(size: format == .story ? 22 : 26, weight: .regular))

            Text("muse")
                .font(.system(size: format == .story ? 26 : 30, weight: .regular, design: .serif))
        }
        .foregroundColor(Color(hex: "6B6560"))
    }

    // MARK: - Minimal Style (Stark black text, pure background)

    private var minimalStyleView: some View {
        ZStack {
            // Pure warm cream background
            Color(hex: "FAF8F5")

            VStack(spacing: 0) {
                Spacer()

                // Large bold text - no card, just text
                minimalContentView
                    .padding(.horizontal, format == .story ? 56 : 72)

                Spacer()

                // Minimal footer
                minimalFooterView
                    .padding(.bottom, format == .story ? 100 : 80)
            }
        }
        .frame(width: format.size.width, height: format.size.height)
    }

    private var minimalContentView: some View {
        VStack(alignment: .leading, spacing: format == .story ? 40 : 36) {
            // Large opening quote mark
            Text("\u{201C}")
                .font(.system(size: format == .story ? 120 : 140, weight: .light, design: .serif))
                .foregroundColor(Color(hex: "E5E0D9"))
                .offset(x: -8, y: 20)

            // Transcription - bold black serif
            Text(transcription)
                .font(.system(size: minimalTextSize, weight: .regular, design: .serif))
                .foregroundColor(Color(hex: "1A1816"))  // Near black
                .lineSpacing(format == .story ? 18 : 16)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var minimalFooterView: some View {
        HStack {
            // Timestamp
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedTime)
                    .font(.system(size: format == .story ? 22 : 26, weight: .medium, design: .monospaced))
                Text(formattedDate)
                    .font(.system(size: format == .story ? 22 : 26, weight: .medium, design: .monospaced))
            }
            .foregroundColor(Color(hex: "3D3833"))

            Spacer()

            // Branding
            HStack(spacing: 12) {
                Image(systemName: "circle.circle")
                    .font(.system(size: format == .story ? 20 : 24, weight: .regular))

                Text("muse")
                    .font(.system(size: format == .story ? 24 : 28, weight: .regular, design: .serif))
            }
            .foregroundColor(Color(hex: "9A9590"))
        }
        .padding(.horizontal, format == .story ? 56 : 72)
    }

    // MARK: - Dynamic Text Sizes

    private var dynamicTextSize: CGFloat {
        let charCount = transcription.count

        if format == .story {
            if charCount < 50 { return 64 }
            else if charCount < 100 { return 52 }
            else if charCount < 160 { return 42 }
            else if charCount < 240 { return 34 }
            else if charCount < 340 { return 28 }
            else if charCount < 480 { return 24 }
            else { return 20 }
        } else {
            if charCount < 50 { return 56 }
            else if charCount < 100 { return 46 }
            else if charCount < 160 { return 38 }
            else if charCount < 240 { return 32 }
            else if charCount < 340 { return 26 }
            else if charCount < 480 { return 22 }
            else { return 18 }
        }
    }

    private var minimalTextSize: CGFloat {
        let charCount = transcription.count

        // Minimal style uses larger text since there's no card
        if format == .story {
            if charCount < 40 { return 80 }
            else if charCount < 80 { return 64 }
            else if charCount < 140 { return 52 }
            else if charCount < 220 { return 42 }
            else if charCount < 320 { return 34 }
            else if charCount < 450 { return 28 }
            else { return 24 }
        } else {
            if charCount < 40 { return 72 }
            else if charCount < 80 { return 58 }
            else if charCount < 140 { return 48 }
            else if charCount < 220 { return 38 }
            else if charCount < 320 { return 30 }
            else if charCount < 450 { return 26 }
            else { return 22 }
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
}

// MARK: - Convenience Initializer

extension ShareableMuseView {
    init(muse: Muse, format: ShareMuseFormat, style: ShareMuseStyle) {
        self.transcription = muse.transcription
        self.timestamp = muse.createdAt
        self.duration = muse.duration
        self.format = format
        self.style = style
    }
}

// MARK: - Previews

#Preview("Dark - Story") {
    ShareableMuseView(
        transcription: "Sometimes the quiet moments speak the loudest.",
        timestamp: Date(),
        duration: 5.2,
        format: .story,
        style: .dark
    )
    .frame(width: 360, height: 640)
}

#Preview("Dark - Feed") {
    ShareableMuseView(
        transcription: "I've been thinking about how we measure success. It's not about the destination, it's about who you become along the way.",
        timestamp: Date(),
        duration: 18.7,
        format: .feed,
        style: .dark
    )
    .frame(width: 480, height: 360)
}

#Preview("Minimal - Story") {
    ShareableMuseView(
        transcription: "Sometimes the quiet moments speak the loudest.",
        timestamp: Date(),
        duration: 5.2,
        format: .story,
        style: .minimal
    )
    .frame(width: 360, height: 640)
}

#Preview("Minimal - Feed") {
    ShareableMuseView(
        transcription: "I've been thinking about how we measure success. It's not about the destination, it's about who you become along the way.",
        timestamp: Date(),
        duration: 18.7,
        format: .feed,
        style: .minimal
    )
    .frame(width: 480, height: 360)
}
