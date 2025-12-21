//
//  MainTabView.swift
//  muse
//
//  Main tab navigation - Home and Muses
//  Also handles app-level audio session listening (so it works from any tab)
//

import SwiftUI
import SwiftData
import Combine
import WhisperKit
import CoreLocation

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: Tab = .home
    @State private var ringManager = RingManager.shared
    @State private var whisperService = WhisperService.shared
    @State private var locationService = LocationService.shared

    // App-level audio subscription (persists across tab changes)
    @State private var audioSessionSubscription: AnyCancellable?

    // Transcription state (shared across tabs)
    @State private var isTranscribing = false

    enum Tab {
        case home
        case muses
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("home", systemImage: "circle")
                }
                .tag(Tab.home)

            MusesView()
                .tabItem {
                    Label("muses", systemImage: "square.stack")
                }
                .tag(Tab.muses)
        }
        .tint(.museAccent)
        .onAppear {
            setupAppLevelAudioListener()
            setupLocationService()
        }
    }

    // MARK: - Location Setup

    private func setupLocationService() {
        // Request permission if not determined
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestPermission()
        }
        // Start updating if already authorized
        locationService.startUpdating()
    }

    // MARK: - App-Level Audio Handling

    /// Set up audio session listener at app level so it works from any tab
    private func setupAppLevelAudioListener() {
        // Only set up once
        guard audioSessionSubscription == nil else { return }

        audioSessionSubscription = ringManager.audioSessionPublisher
            .receive(on: DispatchQueue.main)
            .sink { session in
                handleAudioSession(session)
            }

        print("[MainTabView] App-level audio listener set up")
    }

    /// Handle completed audio session - transcribe and create Muse
    private func handleAudioSession(_ session: AudioSession) {
        print("[MainTabView] Received audio session: \(String(format: "%.2f", session.duration))s, \(session.packets.count) packets")

        // Skip very short recordings
        guard session.duration >= 0.5 else {
            print("[MainTabView] Session too short, skipping")
            return
        }

        // Start transcription
        Task {
            await transcribeAndSave(session)
        }
    }

    /// Transcribe audio session and save as Muse
    private func transcribeAndSave(_ session: AudioSession) async {
        guard whisperService.state.isReady else {
            print("[MainTabView] Whisper not ready, cannot transcribe")
            return
        }

        isTranscribing = true

        // Process ADPCM packets through the full pipeline
        let (processedSamples, sampleRate) = AudioProcessor.processAudioSession(packets: session.packets)

        print("[MainTabView] Processed \(session.packets.count) packets → \(processedSamples.count) samples @ \(sampleRate)Hz")

        do {
            let result = try await whisperService.transcribeWithProgress(
                samples: processedSamples,
                sampleRate: sampleRate
            ) { _ in
                return nil // Continue transcription
            }

            let finalText = cleanTranscriptionText(result.text)
            print("[MainTabView] Transcription complete: \"\(finalText.prefix(100))\"")

            // Create Muse if we got text
            if !finalText.isEmpty {
                createMuse(
                    transcription: finalText,
                    duration: session.duration
                )
            }

        } catch {
            print("[MainTabView] Transcription failed: \(error)")
        }

        isTranscribing = false
    }

    /// Clean WhisperKit special tokens from transcription
    private func cleanTranscriptionText(_ text: String) -> String {
        var cleaned = text

        // Remove WhisperKit special tokens: <|...|>
        let tokenPattern = #"<\|[^>]+\|>"#
        if let regex = try? NSRegularExpression(pattern: tokenPattern) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        // Remove common artifacts
        cleaned = cleaned.replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
        cleaned = cleaned.replacingOccurrences(of: "(inaudible)", with: "")

        // Clean whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        return cleaned
    }

    /// Create and save a Muse entry
    private func createMuse(transcription: String, duration: TimeInterval) {
        // Capture location if available
        let location = locationService.getCurrentLocationString()

        let muse = Muse(
            transcription: transcription,
            duration: duration,
            locationString: location
        )

        modelContext.insert(muse)

        let locationInfo = location.map { " @ \($0)" } ?? ""
        print("[MainTabView] Created muse: \"\(transcription.prefix(50))...\" (\(String(format: "%.1f", duration))s)\(locationInfo)")
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: Muse.self, inMemory: true)
}
