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
    case dark = "dark"          // Dark background, light text
    case minimal = "minimal"    // Light background, dark text
    case terminal = "terminal"  // Hacker/CRT terminal aesthetic
    case brutalist = "brutalist" // Bold, stark, editorial
    case cosmic = "cosmic"      // Night sky, contemplative

    var displayName: String {
        switch self {
        case .dark: return "dark"
        case .minimal: return "light"
        case .terminal: return "terminal"
        case .brutalist: return "brutal"
        case .cosmic: return "cosmic"
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
        case .terminal:
            terminalStyleView
        case .brutalist:
            brutalistStyleView
        case .cosmic:
            cosmicStyleView
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
                    .padding(.horizontal, format == .story ? 60 : 76)
                    .padding(.top, format == .story ? 100 : 80)
                }

                Spacer()

                // Large text - no card, just text (mirrors minimal)
                darkContentView
                    .padding(.horizontal, format == .story ? 60 : 76)

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
        .padding(.horizontal, format == .story ? 64 : 80)
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
                    .padding(.horizontal, format == .story ? 64 : 80)
                    .padding(.top, format == .story ? 100 : 80)
                }

                Spacer()

                // Large bold text - no card, just text
                minimalContentView
                    .padding(.horizontal, format == .story ? 64 : 80)

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
        .padding(.horizontal, format == .story ? 64 : 80)
    }

    // MARK: - Terminal Style (Hacker CRT aesthetic)

    private var terminalStyleView: some View {
        ZStack {
            // Pure black
            Color(hex: "0A0A0A")

            // Subtle scanline effect (simulated with gradient)
            VStack(spacing: 0) {
                ForEach(0..<100, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.02))
                        .frame(height: 1)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: format == .story ? 18 : 10)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                // Header - terminal style
                HStack {
                    Text("~/muse")
                        .font(.system(size: format == .story ? 28 : 32, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(hex: "4AF626"))

                    Spacer()

                    if let location = locationString {
                        Text("[\(location)]")
                            .font(.system(size: format == .story ? 24 : 28, weight: .regular, design: .monospaced))
                            .foregroundColor(Color(hex: "4AF626").opacity(0.6))
                    }
                }
                .padding(.horizontal, format == .story ? 60 : 76)
                .padding(.top, format == .story ? 100 : 80)

                Spacer()

                // Content
                VStack(alignment: .leading, spacing: format == .story ? 20 : 16) {
                    Text("> \(transcription)")
                        .font(.system(size: terminalTextSize, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(hex: "4AF626"))
                        .lineSpacing(terminalLineSpacing)
                        .multilineTextAlignment(.leading)

                    // Blinking cursor (static for image)
                    Text("█")
                        .font(.system(size: terminalTextSize * 0.8, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(hex: "4AF626"))
                }
                .padding(.horizontal, format == .story ? 60 : 76)

                Spacer()

                // Footer
                HStack {
                    Text("[\(terminalTimestamp)]")
                        .font(.system(size: format == .story ? 26 : 30, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(hex: "4AF626").opacity(0.7))

                    Spacer()

                    Text("muse v1.0")
                        .font(.system(size: format == .story ? 24 : 28, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(hex: "4AF626").opacity(0.4))
                }
                .padding(.horizontal, format == .story ? 60 : 76)
                .padding(.bottom, format == .story ? 100 : 80)
            }
        }
        .frame(width: format.size.width, height: format.size.height)
    }

    private var terminalTextSize: CGFloat {
        let charCount = transcription.count
        if format == .story {
            if charCount < 20 { return 72 }
            else if charCount < 50 { return 52 }
            else if charCount < 100 { return 40 }
            else if charCount < 180 { return 32 }
            else { return 26 }
        } else {
            if charCount < 20 { return 60 }
            else if charCount < 50 { return 44 }
            else if charCount < 100 { return 34 }
            else if charCount < 180 { return 28 }
            else { return 24 }
        }
    }

    private var terminalLineSpacing: CGFloat {
        let charCount = transcription.count
        if charCount < 50 { return 12 }
        else if charCount < 150 { return 16 }
        else { return 20 }
    }

    private var terminalTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd.yy // HH:mm"
        return formatter.string(from: timestamp)
    }

    // MARK: - Brutalist Style (Bold, stark, editorial)

    private var brutalistStyleView: some View {
        ZStack {
            // Pure white
            Color.white

            VStack(spacing: 0) {
                Spacer()

                // Massive bold text - the entire point
                Text(transcription.uppercased())
                    .font(.system(size: brutalistTextSize, weight: .black, design: .default))
                    .foregroundColor(Color(hex: "0A0A0A"))
                    .lineSpacing(brutalistLineSpacing)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, format == .story ? 56 : 72)

                Spacer()

                // Minimal footer - tiny, bottom left
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(brutalistDate)
                            .font(.system(size: format == .story ? 20 : 24, weight: .medium, design: .monospaced))
                        if let location = locationString {
                            Text(location.uppercased())
                                .font(.system(size: format == .story ? 18 : 22, weight: .medium, design: .monospaced))
                        }
                    }
                    .foregroundColor(Color(hex: "0A0A0A").opacity(0.4))

                    Spacer()

                    Text("MUSE")
                        .font(.system(size: format == .story ? 18 : 22, weight: .black, design: .default))
                        .foregroundColor(Color(hex: "0A0A0A").opacity(0.2))
                }
                .padding(.horizontal, format == .story ? 56 : 72)
                .padding(.bottom, format == .story ? 80 : 64)
            }
        }
        .frame(width: format.size.width, height: format.size.height)
    }

    private var brutalistTextSize: CGFloat {
        let charCount = transcription.count
        if format == .story {
            if charCount < 8 { return 200 }
            else if charCount < 15 { return 140 }
            else if charCount < 30 { return 100 }
            else if charCount < 50 { return 76 }
            else if charCount < 80 { return 60 }
            else if charCount < 120 { return 48 }
            else if charCount < 180 { return 40 }
            else if charCount < 240 { return 36 }
            else if charCount < 300 { return 32 }
            else if charCount < 360 { return 24 }
            else if charCount < 420 { return 20 }
            else if charCount < 480 { return 18 }
            else if charCount < 540 { return 16 }
            else if charCount < 600 { return 14 }
            else if charCount < 660 { return 12 }
            else if charCount < 720 { return 10 }
            else { return 8 }
        } else {
            if charCount < 8 { return 160 }
            else if charCount < 15 { return 120 }
            else if charCount < 30 { return 88 }
            else if charCount < 50 { return 68 }
            else if charCount < 80 { return 52 }
            else if charCount < 120 { return 42 }
            else { return 34 }
        }
    }

    private var brutalistLineSpacing: CGFloat {
        let charCount = transcription.count
        if charCount < 30 { return -4 }  // Tight for impact
        else if charCount < 80 { return 0 }
        else { return 4 }
    }

    private var brutalistDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter.string(from: timestamp)
    }

    // MARK: - Cosmic Style (Night sky, contemplative)

    private var cosmicStyleView: some View {
        ZStack {
            // Deep navy gradient
            LinearGradient(
                colors: [
                    Color(hex: "0D1321"),  // Deep navy
                    Color(hex: "1D2D44"),  // Midnight blue
                    Color(hex: "0D1321")   // Back to deep
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Scattered stars (static dots)
            cosmicStars

            VStack(spacing: 0) {
                // Location header
                if let location = locationString {
                    HStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "mappin")
                                .font(.system(size: format == .story ? 22 : 26))
                            Text(location)
                                .font(.system(size: format == .story ? 26 : 30, weight: .light, design: .serif))
                        }
                        .foregroundColor(Color(hex: "C9B97A").opacity(0.7))
                    }
                    .padding(.horizontal, format == .story ? 60 : 76)
                    .padding(.top, format == .story ? 100 : 80)
                }

                Spacer()

                // Content - soft cream/gold text
                VStack(alignment: .leading, spacing: format == .story ? 28 : 24) {
                    Text("\u{201C}")
                        .font(.system(size: cosmicQuoteSize, weight: .ultraLight, design: .serif))
                        .foregroundColor(Color(hex: "C9B97A").opacity(0.3))
                        .offset(x: -8, y: 12)

                    Text(transcription)
                        .font(.system(size: cosmicTextSize, weight: .light, design: .serif))
                        .foregroundColor(Color(hex: "F0E6D2"))
                        .lineSpacing(cosmicLineSpacing)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, format == .story ? 64 : 80)

                Spacer()

                // Footer
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(formattedTime)
                            .font(.system(size: format == .story ? 30 : 36, weight: .light, design: .monospaced))
                        Text(formattedDate)
                            .font(.system(size: format == .story ? 30 : 36, weight: .light, design: .monospaced))
                    }
                    .foregroundColor(Color(hex: "C9B97A").opacity(0.8))

                    Spacer()

                    Text("muse")
                        .font(.system(size: format == .story ? 28 : 34, weight: .light, design: .serif))
                        .foregroundColor(Color(hex: "C9B97A").opacity(0.4))
                }
                .padding(.horizontal, format == .story ? 64 : 80)
                .padding(.bottom, format == .story ? 100 : 80)
            }
        }
        .frame(width: format.size.width, height: format.size.height)
    }

    private var cosmicStars: some View {
        Canvas { context, size in
            // Generate deterministic "random" stars based on transcription hash
            let seed = transcription.hashValue
            var generator = SeededRandomGenerator(seed: seed)

            for _ in 0..<60 {
                let x = CGFloat.random(in: 0...size.width, using: &generator)
                let y = CGFloat.random(in: 0...size.height, using: &generator)
                let radius = CGFloat.random(in: 1...3, using: &generator)
                let opacity = Double.random(in: 0.2...0.6, using: &generator)

                let rect = CGRect(x: x, y: y, width: radius, height: radius)
                context.fill(Circle().path(in: rect), with: .color(Color.white.opacity(opacity)))
            }
        }
    }

    private var cosmicTextSize: CGFloat {
        let charCount = transcription.count
        if format == .story {
            if charCount < 15 { return 100 }
            else if charCount < 40 { return 72 }
            else if charCount < 80 { return 56 }
            else if charCount < 140 { return 44 }
            else { return 36 }
        } else {
            if charCount < 15 { return 88 }
            else if charCount < 40 { return 64 }
            else if charCount < 80 { return 48 }
            else if charCount < 140 { return 38 }
            else { return 32 }
        }
    }

    private var cosmicQuoteSize: CGFloat {
        let charCount = transcription.count
        if format == .story {
            if charCount < 30 { return 160 }
            else if charCount < 80 { return 120 }
            else { return 90 }
        } else {
            if charCount < 30 { return 140 }
            else if charCount < 80 { return 100 }
            else { return 80 }
        }
    }

    private var cosmicLineSpacing: CGFloat {
        let charCount = transcription.count
        if charCount < 50 { return 10 }
        else if charCount < 120 { return 16 }
        else { return 20 }
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

// MARK: - Seeded Random Generator (for deterministic star placement)

struct SeededRandomGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: Int) {
        self.state = UInt64(bitPattern: Int64(seed))
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
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
