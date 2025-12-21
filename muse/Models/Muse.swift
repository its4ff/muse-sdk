//
//  Muse.swift
//  muse
//
//  SwiftData model for voice memos (muses)
//

import Foundation
import SwiftData

@Model
final class Muse {
    var id: UUID
    var createdAt: Date
    var transcription: String
    var duration: TimeInterval  // Recording duration in seconds
    var audioData: Data?        // Optional raw PCM audio (for playback if needed)

    init(
        transcription: String,
        duration: TimeInterval,
        audioData: Data? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.transcription = transcription
        self.duration = duration
        self.audioData = audioData
    }

    // MARK: - Computed Properties

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: createdAt).lowercased()
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: createdAt).lowercased()
    }

    var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: createdAt).lowercased()
    }

    var durationString: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        }
        return "0:\(String(format: "%02d", seconds))"
    }

    var hasAudio: Bool {
        guard let data = audioData else { return false }
        return !data.isEmpty
    }

    var preview: String {
        if transcription.count <= 100 {
            return transcription
        }
        return String(transcription.prefix(100)) + "..."
    }
}
