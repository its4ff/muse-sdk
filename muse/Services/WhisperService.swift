//
//  WhisperService.swift
//  muse
//
//  WhisperKit integration for on-device speech-to-text transcription
//

import Foundation
import WhisperKit

// MARK: - Whisper Model Size

enum WhisperModelSize: String, CaseIterable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largev3 = "large-v3"

    var displayName: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        case .largev3: return "Large"
        }
    }

    var description: String {
        switch self {
        case .tiny: return "~75MB, fast, lower accuracy"
        case .base: return "~150MB, balanced"
        case .small: return "~500MB, good accuracy"
        case .medium: return "~1.5GB, high accuracy"
        case .largev3: return "~3GB, highest accuracy"
        }
    }
}

// MARK: - Transcription Result

struct TranscriptionResult {
    let text: String
    let language: String?
    let processingTime: TimeInterval
}

// MARK: - Whisper Service State

enum WhisperServiceState: Equatable {
    case notLoaded
    case loading(progress: Double)
    case ready
    case transcribing
    case error(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isTranscribing: Bool {
        if case .transcribing = self { return true }
        return false
    }
}

// MARK: - Whisper Service

@MainActor
@Observable
final class WhisperService {

    // Singleton
    static let shared = WhisperService()

    // State
    var state: WhisperServiceState = .notLoaded
    var currentModel: WhisperModelSize = .small
    var lastTranscription: TranscriptionResult?

    // Private
    private var whisperKit: WhisperKit?

    private init() {
        print("[WhisperService] Initialized")
    }

    // MARK: - Model Loading

    func loadModel(_ model: WhisperModelSize = .small) async {
        guard state != .loading(progress: 0) else {
            print("[WhisperService] Already loading a model")
            return
        }

        if case .ready = state, currentModel == model, whisperKit != nil {
            print("[WhisperService] Model \(model.rawValue) already loaded")
            return
        }

        print("[WhisperService] Loading model: \(model.rawValue)")
        state = .loading(progress: 0)
        currentModel = model

        do {
            let config = WhisperKitConfig(
                model: model.rawValue,
                verbose: false,
                prewarm: true
            )

            whisperKit = try await WhisperKit(config)
            state = .ready
            print("[WhisperService] Model \(model.rawValue) loaded successfully")

        } catch {
            state = .error(error.localizedDescription)
            print("[WhisperService] Failed to load model: \(error)")
        }
    }

    func unloadModel() {
        whisperKit = nil
        state = .notLoaded
        print("[WhisperService] Model unloaded")
    }

    // MARK: - Transcription

    /// Transcribe audio from raw PCM samples
    func transcribe(samples: [Int], sampleRate: Int) async throws -> TranscriptionResult {
        guard let whisperKit = whisperKit else {
            throw WhisperServiceError.modelNotLoaded
        }

        guard case .ready = state else {
            throw WhisperServiceError.notReady
        }

        // Create temporary WAV file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper_\(UUID().uuidString).wav")

        guard let wavData = createWAVData(from: samples, sampleRate: sampleRate) else {
            throw WhisperServiceError.audioConversionFailed
        }

        try wavData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        state = .transcribing
        let startTime = Date()

        print("[WhisperService] Transcribing \(samples.count) samples @ \(sampleRate)Hz")

        do {
            let results = try await whisperKit.transcribe(audioPath: tempURL.path)

            let processingTime = Date().timeIntervalSince(startTime)
            let fullText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let language = results.first?.language

            let result = TranscriptionResult(
                text: fullText,
                language: language,
                processingTime: processingTime
            )

            lastTranscription = result
            state = .ready

            print("[WhisperService] Transcription complete in \(String(format: "%.2f", processingTime))s")
            print("[WhisperService] Result: \"\(fullText.prefix(100))\"")

            return result

        } catch {
            state = .error(error.localizedDescription)
            print("[WhisperService] Transcription failed: \(error)")
            throw error
        }
    }

    /// Transcribe with progress callback for streaming
    func transcribeWithProgress(
        samples: [Int],
        sampleRate: Int,
        progressCallback: @escaping (TranscriptionProgress) -> Bool?
    ) async throws -> TranscriptionResult {
        guard let whisperKit = whisperKit else {
            throw WhisperServiceError.modelNotLoaded
        }

        guard state == .ready || state == .transcribing else {
            throw WhisperServiceError.notReady
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper_\(UUID().uuidString).wav")

        guard let wavData = createWAVData(from: samples, sampleRate: sampleRate) else {
            throw WhisperServiceError.audioConversionFailed
        }

        try wavData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        state = .transcribing
        let startTime = Date()

        do {
            let results = try await whisperKit.transcribe(
                audioPath: tempURL.path,
                decodeOptions: nil,
                callback: progressCallback
            )

            let processingTime = Date().timeIntervalSince(startTime)
            let fullText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let language = results.first?.language

            let result = TranscriptionResult(
                text: fullText,
                language: language,
                processingTime: processingTime
            )

            lastTranscription = result
            state = .ready

            return result

        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - WAV Creation

    private func createWAVData(from samples: [Int], sampleRate: Int) -> Data? {
        var pcmData = Data()
        for sample in samples {
            let int16Sample = Int16(clamping: sample)
            pcmData.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Array($0) })
        }

        let sampleRateU32 = UInt32(sampleRate)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = sampleRateU32 * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRateU32.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        return header + pcmData
    }
}

// MARK: - Errors

enum WhisperServiceError: LocalizedError {
    case modelNotLoaded
    case notReady
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model not loaded"
        case .notReady:
            return "Whisper service not ready"
        case .audioConversionFailed:
            return "Failed to convert audio for transcription"
        }
    }
}
