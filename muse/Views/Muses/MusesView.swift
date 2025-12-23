//
//  MusesView.swift
//  muse
//
//  Voice vault - beautiful card-based view of transcribed recordings
//  Serif text, typewriter timestamps, zen aesthetic
//

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Audio Player Manager

@MainActor
@Observable
final class MuseAudioPlayer {
    static let shared = MuseAudioPlayer()

    private var audioPlayer: AVAudioPlayer?
    var playingMuseId: UUID?
    var isPlaying: Bool { audioPlayer?.isPlaying ?? false }

    private init() {}

    func play(muse: Muse) {
        // Stop any current playback
        stop()

        guard let audioData = muse.audioData, !audioData.isEmpty else {
            print("[MuseAudioPlayer] No audio data for muse")
            return
        }

        do {
            // Configure audio session for playback
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            // Create player from WAV data
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.play()
            playingMuseId = muse.id

            print("[MuseAudioPlayer] Playing muse: \(muse.durationString)")

            // Auto-stop when done
            let duration = audioPlayer?.duration ?? muse.duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { [weak self] in
                if self?.playingMuseId == muse.id {
                    self?.stop()
                }
            }
        } catch {
            print("[MuseAudioPlayer] Playback error: \(error)")
            playingMuseId = nil
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        playingMuseId = nil

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func togglePlayback(muse: Muse) {
        if playingMuseId == muse.id {
            stop()
        } else {
            play(muse: muse)
        }
    }
}

// MARK: - Time Period Filter

enum MuseTimePeriod: String, CaseIterable {
    case today = "today"
    case week = "week"
    case all = "all"
}

// MARK: - Muses View

struct MusesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Muse.createdAt, order: .reverse) private var muses: [Muse]
    @State private var selectedPeriod: MuseTimePeriod = .all

    var body: some View {
        NavigationStack {
            ZStack {
                Color.museBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Period selector
                    periodSelector
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.sm)

                    // Content
                    if filteredMuses.isEmpty {
                        emptyState
                    } else {
                        musesList
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.museBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("muses")
                        .font(.museBodyMedium)
                        .foregroundColor(.museText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !muses.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                deleteAll()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.museTextSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Period Selector

    private var periodSelector: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(MuseTimePeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.museSoft) {
                        selectedPeriod = period
                    }
                } label: {
                    Text(period.rawValue)
                        .font(.museCaptionMedium)
                        .foregroundColor(selectedPeriod == period ? .museText : .museTextTertiary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(selectedPeriod == period ? Color.museBackgroundSecondary : Color.clear)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            // Entry count
            Text("\(filteredMuses.count)")
                .font(.museMono)
                .foregroundColor(.museTextMuted)
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Minimal icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.museBorder.opacity(0.5), lineWidth: 1)
                    .frame(width: 80, height: 100)

                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.museBorder.opacity(0.3))
                            .frame(width: 50, height: 6)
                    }
                }
            }

            VStack(spacing: Spacing.sm) {
                Text("no muses yet")
                    .font(.museSerifLarge)
                    .foregroundColor(.museTextSecondary)

                Text("tap and hold your ring to speak\nyour thoughts will appear here")
                    .font(.museCaption)
                    .foregroundColor(.museTextTertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
    }

    // MARK: - Muses List

    private var musesList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                ForEach(filteredMuses) { muse in
                    MuseCard(
                        muse: muse,
                        onDelete: { deleteMuse(muse) }
                    )
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Filtered Muses

    private var filteredMuses: [Muse] {
        switch selectedPeriod {
        case .today:
            return muses.filter { Calendar.current.isDateInToday($0.createdAt) }
        case .week:
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return muses.filter { $0.createdAt >= weekAgo }
        case .all:
            return muses
        }
    }

    // MARK: - Actions

    private func deleteMuse(_ muse: Muse) {
        modelContext.delete(muse)
    }

    private func deleteAll() {
        for muse in muses {
            modelContext.delete(muse)
        }
    }
}

// MARK: - Muse Card

struct MuseCard: View {
    let muse: Muse
    let onDelete: () -> Void

    @State private var showShareSheet = false
    @State private var showAudioShareSheet = false
    @State private var audioFileURL: URL?
    @State private var audioPlayer = MuseAudioPlayer.shared

    private var isPlaying: Bool {
        audioPlayer.playingMuseId == muse.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: location/date + play button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Location (if available)
                    if let location = muse.locationString {
                        Text(location)
                            .font(.museCaptionMedium)
                            .foregroundColor(.museTextSecondary)
                    }

                    // Full date
                    Text(muse.fullDateString)
                        .font(.museCaption)
                        .foregroundColor(.museTextTertiary)
                }

                Spacer()

                // Play button with duration
                Button {
                    if muse.hasAudio {
                        audioPlayer.togglePlayback(muse: muse)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if muse.hasAudio {
                            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 8))
                                .foregroundColor(isPlaying ? .museAccent : .museTextTertiary)
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 10))
                        }

                        Text(muse.durationString)
                            .font(.museMonoMedium)
                    }
                    .foregroundColor(isPlaying ? .museAccent : .museTextTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isPlaying ? Color.museAccent.opacity(0.1) : Color.museBackgroundSecondary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(isPlaying ? Color.museAccent.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!muse.hasAudio)
            }

            // Transcribed text (serif)
            Text(muse.transcription.isEmpty ? "(audio only)" : muse.transcription)
                .font(.museSerif)
                .foregroundColor(muse.transcription.isEmpty ? .museTextTertiary : .museText)
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)

            // Footer: time (right aligned)
            HStack {
                Spacer()

                Text(muse.timeString)
                    .font(.museMono)
                    .foregroundColor(.museTextTertiary)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.museCard)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(isPlaying ? Color.museAccent.opacity(0.3) : Color.museBorder.opacity(0.3), lineWidth: isPlaying ? 1 : 0.5)
        )
        .museShadowSmall()
        .animation(.museSoft, value: isPlaying)
        .contextMenu {
            Button {
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            if muse.hasAudio {
                Button {
                    shareAudio()
                } label: {
                    Label("Share Audio", systemImage: "waveform")
                }
            }

            if !muse.transcription.isEmpty {
                Button {
                    UIPasteboard.general.string = muse.transcription
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareMuseScreen(muse: muse)
        }
        .sheet(isPresented: $showAudioShareSheet) {
            if let url = audioFileURL {
                AudioShareSheet(url: url)
            }
        }
    }

    private func shareAudio() {
        guard let audioData = muse.audioData, !audioData.isEmpty else { return }

        // Create temp file with timestamp-based name
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy_hmma"
        let filename = "muse_\(formatter.string(from: muse.createdAt).lowercased()).wav"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try audioData.write(to: tempURL)
            audioFileURL = tempURL
            showAudioShareSheet = true
        } catch {
            print("[MuseCard] Failed to write audio file: \(error)")
        }
    }
}

// MARK: - Audio Share Sheet

struct AudioShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        // Make it appear as a smaller sheet on iPhone
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    MusesView()
        .modelContainer(for: Muse.self, inMemory: true)
}
