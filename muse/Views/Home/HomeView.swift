//
//  HomeView.swift
//  muse
//
//  Card-based home dashboard with ring status
//  Recording is done via ring touch gesture (hold to record)
//
//  Flow: Ring touch → ADPCM packets → Transcription → Muse creation
//

import SwiftUI
import SwiftData
import Combine

struct HomeView: View {
    @State private var ringManager = RingManager.shared
    @State private var whisperService = WhisperService.shared
    @State private var showOnboarding = false
    @State private var showEditName = false
    @State private var editingName = ""

    // Recording UI state (mirrors RingManager.isRecording)
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?

    // Subscriptions (for UI updates only - transcription is handled at app level in MainTabView)
    @State private var audioPacketSubscription: AnyCancellable?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Connection Card
                    connectionCard

                    // Battery Card
                    batteryCard

                    // Voice Model Card
                    voiceModelCard

                    // Ring Mode Card (Audio vs Music)
                    if ringManager.isConnected {
                        ringModeCard
                    }

                    // Recording indicator (when active)
                    if ringManager.isRecording {
                        recordingCard
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Color.museBackground)
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("muse")
                        .font(.museBodyMedium)
                        .foregroundColor(.museText)
                }
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView()
            }
            .sheet(isPresented: $showEditName) {
                EditMuseNameSheet(
                    name: $editingName,
                    onSave: {
                        ringManager.customMuseName = editingName.isEmpty ? nil : editingName
                        showEditName = false
                    },
                    onCancel: {
                        showEditName = false
                    }
                )
                .presentationDetents([.height(200)])
            }
            .onAppear {
                setupAudioPacketListener()
                preloadWhisperIfNeeded()
                attemptAutoReconnect()
            }
            .onDisappear {
                audioPacketSubscription?.cancel()
                recordingTimer?.invalidate()
            }
            .onChange(of: ringManager.isRecording) { _, isRecording in
                if isRecording {
                    startRecordingTimer()
                } else {
                    stopRecordingTimer()
                }
            }
        }
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                Text("connection")
                    .font(.museCaptionMedium)
                    .foregroundColor(.museTextTertiary)

                Spacer()

                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 8, height: 8)
            }

            // Content
            HStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(ringManager.state.description)
                        .font(.museTitle3)
                        .foregroundColor(.museText)

                    if let name = ringManager.deviceName {
                        Text(name.lowercased())
                            .font(.museCaption)
                            .foregroundColor(.museTextSecondary)
                    } else {
                        Text("no muse connected")
                            .font(.museCaption)
                            .foregroundColor(.museTextTertiary)
                    }
                }

                Spacer()

                // Editable muse name (when connected)
                if ringManager.isConnected {
                    Button {
                        editingName = ringManager.customMuseName ?? ""
                        showEditName = true
                    } label: {
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            if let customName = ringManager.customMuseName, !customName.isEmpty {
                                Text(customName.lowercased())
                                    .font(.museSerif)
                                    .foregroundColor(.museText)
                            } else {
                                Text("name your muse")
                                    .font(.museCaption)
                                    .foregroundColor(.museTextTertiary)
                            }
                            HStack(spacing: 3) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 9))
                                Text("edit")
                                    .font(.museMicro)
                            }
                            .foregroundColor(.museTextTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Action buttons
            HStack(spacing: Spacing.sm) {
                if ringManager.isConnected {
                    actionButton("Refresh") {
                        Task { await ringManager.refresh() }
                    }

                    actionButton("Disconnect") {
                        ringManager.disconnect()
                    }
                } else if ringManager.state.isActive {
                    // Scanning, connecting, reconnecting, or binding
                    HStack(spacing: Spacing.xs) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(ringManager.state.description.lowercased())
                            .font(.museMicro)
                            .foregroundColor(.museTextSecondary)
                    }
                } else {
                    // Disconnected
                    if ringManager.hasSavedDevice {
                        actionButton("Reconnect") {
                            ringManager.reconnectLastDevice()
                        }

                        actionButton("New Device") {
                            ringManager.forgetDevice()
                            showOnboarding = true
                        }
                    } else {
                        actionButton("Connect") {
                            showOnboarding = true
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.museCard)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .museShadowSmall()
    }

    // MARK: - Battery Card

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                Text("battery")
                    .font(.museCaptionMedium)
                    .foregroundColor(.museTextTertiary)

                Spacer()

                // Charging indicator
                if ringManager.isConnected && ringManager.isCharging {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text(ringManager.chargingState.lowercased())
                            .font(.museMicro)
                    }
                    .foregroundColor(.museConnected)
                }
            }

            // Content
            HStack(alignment: .bottom, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        if ringManager.isConnected {
                            if ringManager.isCharging && ringManager.chargingState == "Charging" {
                                // Show charging icon instead of percentage when actively charging
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.museConnected)
                            } else {
                                Text("\(ringManager.batteryLevel)")
                                    .font(.museDataLarge)
                                    .foregroundColor(batteryColor)
                            }
                        } else {
                            Text("—")
                                .font(.museDataLarge)
                                .foregroundColor(.museTextMuted)
                        }

                        if !ringManager.isCharging || ringManager.chargingState != "Charging" {
                            Text("%")
                                .font(.museCaption)
                                .foregroundColor(.museTextTertiary)
                        }
                    }

                    Text(batteryStatusText)
                        .font(.museMicro)
                        .foregroundColor(.museTextTertiary)
                }

                Spacer()

                // Battery bar visual
                BatteryBar(
                    level: ringManager.batteryLevel,
                    isConnected: ringManager.isConnected,
                    isCharging: ringManager.isCharging
                )
            }
        }
        .padding(Spacing.md)
        .background(Color.museCard)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .museShadowSmall()
    }

    private var batteryStatusText: String {
        if !ringManager.isConnected {
            return "not connected"
        }
        if ringManager.isCharging {
            return ringManager.chargingState == "Charged" ? "fully charged" : "charging"
        }
        return "connected"
    }

    // MARK: - Voice Model Card

    private var voiceModelCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                Text("transcription model")
                    .font(.museCaptionMedium)
                    .foregroundColor(.museTextTertiary)

                Spacer()

                if whisperService.state.isReady {
                    HStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(Color.museConnected)
                            .frame(width: 6, height: 6)
                        Text("ready")
                            .font(.museMicro)
                    }
                    .foregroundColor(.museConnected)
                }
            }

            // Content
            HStack(alignment: .center, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(whisperService.currentModel.displayName)
                        .font(.museTitle3)
                        .foregroundColor(.museText)

                    Text(whisperService.currentModel.description)
                        .font(.museMicro)
                        .foregroundColor(.museTextTertiary)
                        .lineLimit(1)
                }

                Spacer()

                whisperStatusView
            }
        }
        .padding(Spacing.md)
        .background(Color.museCard)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .museShadowSmall()
    }

    @ViewBuilder
    private var whisperStatusView: some View {
        switch whisperService.state {
        case .notLoaded:
            Button {
                Task { await whisperService.loadModel(.small) }
            } label: {
                Text("download")
                    .font(.museCaptionMedium)
                    .foregroundColor(.museAccent)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.museAccent.opacity(0.1))
                    .clipShape(Capsule())
            }
        case .loading(let progress):
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text("\(Int(progress * 100))%")
                    .font(.museMono)
                    .foregroundColor(.museTextSecondary)
                ProgressView()
                    .scaleEffect(0.7)
            }
        case .ready:
            Text("loaded")
                .font(.museCaptionMedium)
                .foregroundColor(.museTextSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color.museBackgroundSecondary)
                .clipShape(Capsule())
        case .transcribing:
            HStack(spacing: Spacing.xs) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("active")
                    .font(.museCaption)
                    .foregroundColor(.museTextSecondary)
            }
        case .error(let message):
            Text(message)
                .font(.museMicro)
                .foregroundColor(.red.opacity(0.8))
                .lineLimit(1)
        }
    }

    // MARK: - Ring Mode Card (Audio vs Music Control)

    private var ringModeCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                Text("ring mode")
                    .font(.museCaptionMedium)
                    .foregroundColor(.museTextTertiary)

                Spacer()

                if ringManager.isMusicControlMode {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                        Text("music control")
                            .font(.museMicro)
                    }
                    .foregroundColor(.museAccent)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                        Text("voice capture")
                            .font(.museMicro)
                    }
                    .foregroundColor(.museConnected)
                }
            }

            // Mode toggle
            HStack(spacing: Spacing.sm) {
                // Voice mode button
                Button {
                    ringManager.setMusicControlMode(false)
                } label: {
                    VStack(spacing: Spacing.xxs) {
                        Image(systemName: "waveform")
                            .font(.system(size: 20))
                        Text("voice")
                            .font(.museMicro)
                    }
                    .foregroundColor(!ringManager.isMusicControlMode ? .museText : .museTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(!ringManager.isMusicControlMode ? Color.museConnected.opacity(0.15) : Color.museBackgroundSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .stroke(!ringManager.isMusicControlMode ? Color.museConnected.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }

                // Music mode button
                Button {
                    ringManager.setMusicControlMode(true)
                } label: {
                    VStack(spacing: Spacing.xxs) {
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                        Text("music")
                            .font(.museMicro)
                    }
                    .foregroundColor(ringManager.isMusicControlMode ? .museText : .museTextTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(ringManager.isMusicControlMode ? Color.museAccent.opacity(0.15) : Color.museBackgroundSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .stroke(ringManager.isMusicControlMode ? Color.museAccent.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }
            }

            // Mode description
            Text(ringManager.isMusicControlMode
                 ? "touch gestures control music playback"
                 : "hold ring to record voice memos")
                .font(.museMicro)
                .foregroundColor(.museTextTertiary)
        }
        .padding(Spacing.md)
        .background(Color.museCard)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .museShadowSmall()
    }

    // MARK: - Recording Card (shown during recording)

    private var recordingCard: some View {
        VStack(spacing: Spacing.md) {
            // Status indicator
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)

                Text("recording")
                    .font(.museBodyMedium)
                    .foregroundColor(.museText)

                Spacer()

                Text(formatDuration(recordingDuration))
                    .font(.museMono)
                    .foregroundColor(.museTextSecondary)
            }

            // Waveform placeholder
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.museAccent.opacity(0.6))
                        .frame(width: 3, height: CGFloat.random(in: 10...30))
                }
            }
            .frame(height: 40)
        }
        .padding(Spacing.md)
        .background(Color.museCard)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .museShadowSmall()
    }

    // MARK: - Action Button

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.museMicro)
                .foregroundColor(.museText)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color.museBackgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        }
    }

    // MARK: - Computed Properties

    private var connectionStatusColor: Color {
        switch ringManager.state {
        case .connected:
            return .museConnected
        case .connecting, .scanning, .binding, .reconnecting:
            return .museConnecting
        case .disconnected:
            return .museTextMuted
        }
    }

    private var batteryColor: Color {
        let level = ringManager.batteryLevel
        if level >= 60 { return .museText }
        if level >= 30 { return .orange }
        return .red
    }

    // MARK: - Audio Setup

    /// Set up packet listener for waveform visualization only
    /// (Transcription is handled at app level in MainTabView)
    private func setupAudioPacketListener() {
        audioPacketSubscription = ringManager.audioPacketPublisher
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // Could update waveform visualization here
            }
    }

    // MARK: - Recording Timer

    private func startRecordingTimer() {
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                recordingDuration += 0.1
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    // MARK: - WhisperKit Preloading

    private func preloadWhisperIfNeeded() {
        guard !whisperService.state.isReady else { return }
        if case .loading = whisperService.state { return }

        // Auto-load small model
        Task {
            print("[HomeView] Preloading WhisperKit model: small")
            await whisperService.loadModel(.small)
        }
    }

    // MARK: - Auto Reconnect

    private func attemptAutoReconnect() {
        // Only attempt reconnect if not already connected/connecting
        guard !ringManager.isConnected && !ringManager.state.isActive else { return }

        // Only reconnect if we have a saved device
        guard ringManager.hasSavedDevice else { return }

        print("[HomeView] Attempting auto-reconnect to saved device")
        ringManager.reconnectLastDevice()
    }
}

// MARK: - Battery Bar

struct BatteryBar: View {
    let level: Int
    let isConnected: Bool
    var isCharging: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isConnected && i < filledBars ? barColor : Color.museBorder)
                    .frame(width: 8, height: CGFloat(12 + i * 6))
            }
        }
    }

    private var filledBars: Int {
        if level >= 80 { return 5 }
        if level >= 60 { return 4 }
        if level >= 40 { return 3 }
        if level >= 20 { return 2 }
        if level > 0 { return 1 }
        return 0
    }

    private var barColor: Color {
        // Green when charging
        if isCharging { return .museConnected }
        if level >= 60 { return .museText }
        if level >= 30 { return .orange }
        return .red
    }
}

// MARK: - Edit Muse Name Sheet

struct EditMuseNameSheet: View {
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Header
            HStack {
                Button("Cancel") { onCancel() }
                    .font(.museCaption)
                    .foregroundColor(.museTextSecondary)

                Spacer()

                Text("name your muse")
                    .font(.museCaptionMedium)
                    .foregroundColor(.museText)

                Spacer()

                Button("Save") { onSave() }
                    .font(.museCaptionMedium)
                    .foregroundColor(.museAccent)
            }
            .padding(.top, Spacing.md)

            // Text field
            TextField("my muse", text: $name)
                .font(.museTitle3)
                .foregroundColor(.museText)
                .multilineTextAlignment(.center)
                .padding(Spacing.md)
                .background(Color.museBackgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                .focused($isFocused)

            Text("give your ring a personal name")
                .font(.museMicro)
                .foregroundColor(.museTextTertiary)

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .background(Color.museBackground)
        .onAppear {
            isFocused = true
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: Muse.self, inMemory: true)
}
