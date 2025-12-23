//
//  ShareMuseScreen.swift
//  muse
//
//  Share screen for exporting muses as shareable images
//  Two styles: Dark (dark bg, light text) and Light (light bg, dark text)
//

import SwiftUI

struct ShareMuseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("shareMuseStyle") private var selectedStyleRaw: String = ShareMuseStyle.dark.rawValue

    let muse: Muse

    private var selectedStyle: ShareMuseStyle {
        ShareMuseStyle(rawValue: selectedStyleRaw) ?? .dark
    }

    @State private var selectedFormat: ShareMuseFormat = .story
    @State private var isSaving = false
    @State private var showSuccessMessage = false
    @State private var errorMessage: String?
    @State private var animateIn = false
    @State private var showShareSheet = false
    @State private var imageToShare: UIImage?
    @State private var showLocation: Bool = true  // Toggle for showing location on render

    var body: some View {
        ZStack {
            // Background
            Color.museBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // Preview
                cardPreview
                    .opacity(animateIn ? 1 : 0)
                    .scaleEffect(animateIn ? 1 : 0.94)

                Spacer()

                // Controls
                controls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
                    .padding(.top, 16)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 15)
            }

            // Success toast
            if showSuccessMessage {
                successToast
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = imageToShare {
                ShareSheet(items: [image])
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                animateIn = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.museTextSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.museBackgroundSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("share")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundColor(.museText)

            Spacer()

            // Location toggle (only show if muse has location)
            if muse.locationString != nil {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showLocation.toggle()
                    }
                } label: {
                    Image(systemName: showLocation ? "mappin.circle.fill" : "mappin.slash")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(showLocation ? .museAccent : .museTextTertiary)
                        .frame(width: 36, height: 36)
                        .background(Color.museBackgroundSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                // Placeholder for symmetry when no location
                Color.clear
                    .frame(width: 36, height: 36)
            }
        }
    }

    // MARK: - Card Preview

    // Computed location to pass to ShareableMuseView
    private var locationForRender: String? {
        showLocation ? muse.locationString : nil
    }

    private var cardPreview: some View {
        GeometryReader { geometry in
            let scale = calculatePreviewScale(in: geometry.size)

            ShareableMuseView(
                transcription: muse.transcription,
                timestamp: muse.createdAt,
                duration: muse.duration,
                format: selectedFormat,
                style: selectedStyle,
                locationString: locationForRender
            )
                .scaleEffect(scale)
                .frame(
                    width: selectedFormat.size.width * scale,
                    height: selectedFormat.size.height * scale
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.2), radius: 30, y: 15)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.museBorder.opacity(0.3), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            // Style picker
            stylePicker

            // Format picker
            formatPicker

            // Action buttons row
            HStack(spacing: 12) {
                // Save to Photos button
                Button {
                    saveToPhotos()
                } label: {
                    HStack(spacing: 10) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .museText))
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 14, weight: .medium))
                        }
                        Text(isSaving ? "saving..." : "save to photos")
                            .font(.museBodyMedium)
                    }
                    .foregroundColor(.museText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.museBackgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.museBorder, lineWidth: 1)
                    )
                }
                .disabled(isSaving)

                // Share button
                Button {
                    shareCard()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.museText)
                        .frame(width: 52, height: 52)
                        .background(Color.museBackgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.museBorder, lineWidth: 1)
                        )
                }
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.museCaption)
                    .foregroundColor(.museError)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    private var stylePicker: some View {
        HStack(spacing: 16) {
            ForEach(ShareMuseStyle.allCases, id: \.rawValue) { style in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedStyleRaw = style.rawValue
                    }
                } label: {
                    VStack(spacing: 6) {
                        // Style preview circle with padding to prevent border clipping
                        stylePreviewCircle(for: style)
                            .overlay(
                                Circle()
                                    .stroke(
                                        selectedStyle == style ? Color.museAccent : Color.museBorder,
                                        lineWidth: selectedStyle == style ? 2 : 1
                                    )
                            )
                            .padding(2) // Prevent border clipping

                        Text(style.displayName)
                            .font(.system(size: 11, weight: selectedStyle == style ? .medium : .regular))
                            .foregroundColor(selectedStyle == style ? .museText : .museTextTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity) // Center the HStack
        .padding(.vertical, 2) // Extra vertical padding for border visibility
    }

    @ViewBuilder
    private func stylePreviewCircle(for style: ShareMuseStyle) -> some View {
        switch style {
        case .dark:
            Circle()
                .fill(Color(hex: "0F0E0D"))
                .frame(width: 40, height: 40)
                .overlay(
                    Text("\u{201C}")
                        .font(.system(size: 16, weight: .light, design: .serif))
                        .foregroundColor(Color(hex: "FAF8F5"))
                )
        case .minimal:
            Circle()
                .fill(Color(hex: "FAF8F5"))
                .frame(width: 40, height: 40)
                .overlay(
                    Text("\u{201C}")
                        .font(.system(size: 16, weight: .light, design: .serif))
                        .foregroundColor(Color(hex: "1A1816"))
                )
        case .terminal:
            Circle()
                .fill(Color(hex: "0A0A0A"))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(">_")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "4AF626"))
                )
        case .brutalist:
            Circle()
                .fill(Color.white)
                .frame(width: 40, height: 40)
                .overlay(
                    Text("A")
                        .font(.system(size: 18, weight: .black, design: .default))
                        .foregroundColor(Color(hex: "0A0A0A"))
                )
        case .cosmic:
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "0D1321"), Color(hex: "1D2D44")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    // Tiny stars
                    ZStack {
                        Circle().fill(Color.white.opacity(0.6)).frame(width: 2, height: 2).offset(x: -8, y: -6)
                        Circle().fill(Color.white.opacity(0.4)).frame(width: 1.5, height: 1.5).offset(x: 6, y: -4)
                        Circle().fill(Color.white.opacity(0.5)).frame(width: 2, height: 2).offset(x: 3, y: 8)
                        Circle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 1).offset(x: -5, y: 5)
                    }
                )
        }
    }

    private var formatPicker: some View {
        HStack(spacing: 10) {
            FormatButton(
                title: "story",
                icon: "rectangle.portrait",
                isSelected: selectedFormat == .story
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedFormat = .story
                }
            }

            FormatButton(
                title: "feed",
                icon: "rectangle.inset.filled",
                isSelected: selectedFormat == .feed
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedFormat = .feed
                }
            }
        }
    }

    // MARK: - Success Toast

    private var successToast: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.museSuccess)

                Text("saved to photos")
                    .font(.museBodyMedium)
                    .foregroundColor(.museText)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.museCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.museBorder, lineWidth: 1)
            )
            .shadow(color: Color(hex: "2D2A26").opacity(0.1), radius: 16, y: 8)
            .padding(.bottom, 120)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func shareCard() {
        let cardView = ShareableMuseView(
            transcription: muse.transcription,
            timestamp: muse.createdAt,
            duration: muse.duration,
            format: selectedFormat,
            style: selectedStyle,
            locationString: locationForRender
        )

        if let image = ShareMuseRenderer.render(cardView) {
            imageToShare = image
            showShareSheet = true
        }
    }

    private func saveToPhotos() {
        isSaving = true
        errorMessage = nil

        let cardView = ShareableMuseView(
            transcription: muse.transcription,
            timestamp: muse.createdAt,
            duration: muse.duration,
            format: selectedFormat,
            style: selectedStyle,
            locationString: locationForRender
        )

        Task {
            do {
                try await ShareMuseRenderer.saveToPhotos(cardView)

                await MainActor.run {
                    isSaving = false

                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    // Show success toast
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showSuccessMessage = true
                    }
                }

                // Hide success message after delay
                try await Task.sleep(for: .seconds(2.0))

                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        showSuccessMessage = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription

                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }

    // MARK: - Helpers

    private func calculatePreviewScale(in containerSize: CGSize) -> CGFloat {
        let cardSize = selectedFormat.size
        let maxWidth = containerSize.width
        let maxHeight = containerSize.height

        let widthScale = maxWidth / cardSize.width
        let heightScale = maxHeight / cardSize.height

        return min(widthScale, heightScale)
    }
}

// MARK: - Format Button Component

private struct FormatButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(.museCaptionMedium)
            }
            .foregroundColor(isSelected ? .museText : .museTextTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(isSelected ? Color.museBackgroundSecondary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.museBorder : Color.museBorder.opacity(0.5),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview("With Location") {
    ShareMuseScreen(
        muse: Muse(
            transcription: "Sometimes the quiet moments speak the loudest. I've been thinking about how we measure success. It's not about the destination.",
            duration: 12.5,
            locationString: "san francisco, usa"
        )
    )
}

#Preview("No Location") {
    ShareMuseScreen(
        muse: Muse(
            transcription: "Hello world.",
            duration: 2.0
        )
    )
}
