//
//  Theme.swift
//  muse
//
//  Design System - Zen-inspired, warm beige minimalist aesthetic
//  Soft, calming palette with natural tones
//

import SwiftUI

// MARK: - Color Palette

extension Color {
    // Backgrounds - warm beige tones
    static let museBackground = Color(hex: "FAF8F5")      // Warm off-white
    static let museBackgroundSecondary = Color(hex: "F5F2ED")  // Soft beige
    static let museBackgroundTertiary = Color(hex: "EDE8E1")   // Deeper beige
    static let museBackgroundWarm = Color(hex: "F7F4EF")       // Cream

    // Cards & Surfaces - warm whites
    static let museCard = Color(hex: "FFFEFB")            // Warm white
    static let museCardHover = Color(hex: "FBF9F6")       // Soft hover

    // Text - warm charcoal and grays
    static let museText = Color(hex: "2D2A26")            // Warm charcoal
    static let museTextSecondary = Color(hex: "6B6560")   // Warm gray
    static let museTextTertiary = Color(hex: "9A9590")    // Muted warm gray
    static let museTextMuted = Color(hex: "C4BEB8")       // Light warm gray

    // Accent - soft black with warmth
    static let museAccent = Color(hex: "3D3833")          // Warm dark
    static let museAccentSoft = Color(hex: "5C5650")      // Soft accent
    static let museAccentLight = Color(hex: "F0EDE8")     // Light accent background

    // Status colors - muted earth tones
    static let museSuccess = Color(hex: "4A6741")         // Sage green
    static let museSuccessLight = Color(hex: "E8F0E5")    // Light sage
    static let museWarning = Color(hex: "A68B5B")         // Warm amber
    static let museError = Color(hex: "8B5A5A")           // Muted rose

    // Ring Status Colors - warm grayscale
    static let museConnected = Color(hex: "4A6741")       // Sage (connected)
    static let museConnecting = Color(hex: "A68B5B")      // Amber (connecting)
    static let museDisconnected = Color(hex: "C4BEB8")    // Muted (disconnected)

    // Borders - delicate warm tones
    static let museBorder = Color(hex: "E5E0D9")          // Warm border
    static let museBorderLight = Color(hex: "F0EBE4")     // Light border
    static let museBorderWarm = Color(hex: "DDD7CF")      // Deeper border

    // Special accents
    static let museSand = Color(hex: "D4C5B0")            // Sand beige
    static let museTerracotta = Color(hex: "C9A178")      // Soft terracotta
    static let museOlive = Color(hex: "7D8471")           // Muted olive
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography

extension Font {
    // Display - elegant, light
    static let museHero = Font.system(size: 42, weight: .light, design: .default)
    static let museTitle = Font.system(size: 28, weight: .regular, design: .default)
    static let museTitle2 = Font.system(size: 22, weight: .regular, design: .default)
    static let museTitle3 = Font.system(size: 18, weight: .medium, design: .default)

    // Body - clean and readable
    static let museBody = Font.system(size: 16, weight: .regular, design: .default)
    static let museBodyMedium = Font.system(size: 16, weight: .medium, design: .default)
    static let museBodySemibold = Font.system(size: 16, weight: .semibold, design: .default)

    // Serif - for transcriptions (elegant feel)
    static let museSerif = Font.system(size: 16, weight: .regular, design: .serif)
    static let museSerifLarge = Font.system(size: 18, weight: .regular, design: .serif)

    // Small - refined
    static let museCaption = Font.system(size: 13, weight: .regular, design: .default)
    static let museCaptionMedium = Font.system(size: 13, weight: .medium, design: .default)

    // Tiny - subtle
    static let museMicro = Font.system(size: 11, weight: .medium, design: .default)

    // Monospace - for timestamps
    static let museMono = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let museMonoMedium = Font.system(size: 11, weight: .medium, design: .monospaced)

    // Data display - light and airy for large numbers
    static let museData = Font.system(size: 48, weight: .light, design: .default)
    static let museDataLarge = Font.system(size: 42, weight: .light, design: .monospaced)
    static let museDataSmall = Font.system(size: 32, weight: .light, design: .default)
}

// MARK: - Spacing - Generous for breathing room

struct Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64
    static let huge: CGFloat = 80
}

// MARK: - Corner Radius

struct CornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let full: CGFloat = 100
}

// MARK: - Shadows - Soft and warm

extension View {
    func museShadowSmall() -> some View {
        self.shadow(color: Color(hex: "2D2A26").opacity(0.04), radius: 8, x: 0, y: 2)
    }

    func museShadowMedium() -> some View {
        self.shadow(color: Color(hex: "2D2A26").opacity(0.06), radius: 16, x: 0, y: 4)
    }

    func museShadowLarge() -> some View {
        self.shadow(color: Color(hex: "2D2A26").opacity(0.08), radius: 32, x: 0, y: 8)
    }

    func museShadowFloat() -> some View {
        self
            .shadow(color: Color(hex: "2D2A26").opacity(0.03), radius: 1, x: 0, y: 1)
            .shadow(color: Color(hex: "2D2A26").opacity(0.05), radius: 24, x: 0, y: 12)
    }
}

// MARK: - Card Styles

extension View {
    func museCard() -> some View {
        self
            .background(Color.museCard)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(Color.museBorder.opacity(0.5), lineWidth: 0.5)
            )
            .museShadowFloat()
    }

    func museSoftCard() -> some View {
        self
            .background(Color.museBackgroundWarm)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
    }

    func museZenCard() -> some View {
        self
            .background(Color.museCard)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
            .museShadowFloat()
    }
}

// MARK: - Button Styles

struct MusePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.museBodyMedium)
            .foregroundColor(Color(hex: "FAF8F5"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(Color.museAccent)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct MuseSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.museBodyMedium)
            .foregroundColor(.museText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(Color.museBackgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .stroke(Color.museBorder, lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct MuseGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.museBodyMedium)
            .foregroundColor(.museTextSecondary)
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .background(configuration.isPressed ? Color.museBackgroundSecondary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == MusePrimaryButtonStyle {
    static var musePrimary: MusePrimaryButtonStyle { MusePrimaryButtonStyle() }
}

extension ButtonStyle where Self == MuseSecondaryButtonStyle {
    static var museSecondary: MuseSecondaryButtonStyle { MuseSecondaryButtonStyle() }
}

extension ButtonStyle where Self == MuseGhostButtonStyle {
    static var museGhost: MuseGhostButtonStyle { MuseGhostButtonStyle() }
}

// MARK: - Animations

extension Animation {
    static let museSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let museSoft = Animation.easeOut(duration: 0.3)
    static let museQuick = Animation.easeOut(duration: 0.15)
}
