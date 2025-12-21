//
//  AudioProcessor.swift
//  muse
//
//  Ring-specific audio processing for 8kHz ADPCM audio
//  Based on TranscribeView.swift and AudioLabView.swift from Cove
//
//  ADPCM Processing Pipeline:
//  1. Sort packets by sequence number (can arrive out of order)
//  2. Convert each packet's ADPCM → PCM using SDK's convertAdpcmToPcm()
//  3. DC offset removal (fixes baseline drift)
//  4. De-clip (reconstruct clipped peaks)
//  5. Normalize to -6dB
//  6. Upsample 8kHz → 16kHz (for WhisperKit)
//

import Foundation
import MuseSDK

/// Audio processor for BCL ring microphone recordings
/// Pipeline: Sort → ADPCM→PCM (SDK) → DC remove → De-clip → Normalize → Upsample
class AudioProcessor {

    // MARK: - ADPCM Decoder (IMA-ADPCM fallback)

    /// Shared IMA-ADPCM decoder instance (fallback if SDK fails)
    private static var decoder = ADPCMDecoder()

    /// Reset decoder state (call between recordings)
    static func resetDecoder() {
        decoder.reset()
    }

    /// Decode ADPCM data to PCM Int16 samples using IMA-ADPCM (fallback)
    static func decodeADPCM(_ data: Data) -> [Int16] {
        return decoder.decode(data)
    }

    // MARK: - SDK-Based ADPCM Conversion (Preferred)

    /// Convert ADPCM packet data to PCM using SDK's native decoder
    /// This is the preferred method as it uses the ring's actual ADPCM codec (YMA variant)
    static func convertADPCMPacketToPCM(audioData: [Int]) -> [Int] {
        // Convert [Int] to Data (as Int16 bytes, like TranscribeView)
        let int16Array = audioData.map { Int16($0) }
        let adpcmData = int16Array.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Int16>.size)
        }

        // Use SDK's conversion
        if let pcmData = BCLRingManager.shared.convertAdpcmToPcm(adpcmData: adpcmData) {
            // Convert PCM Data back to [Int] samples
            return pcmData.withUnsafeBytes { buffer in
                let int16Buffer = buffer.bindMemory(to: Int16.self)
                return int16Buffer.map { Int($0) }
            }
        }

        // Fallback: return original data if SDK conversion fails
        print("[AudioProcessor] SDK ADPCM conversion failed, using raw data")
        return audioData
    }

    // MARK: - Main Entry Point

    /// Process complete audio session with sorted ADPCM packets
    /// This is the main entry point for processing ring audio
    static func processAudioSession(packets: [(length: Int, seq: Int, audioData: [Int])]) -> (samples: [Int], sampleRate: Int) {
        guard !packets.isEmpty else {
            return ([], 16000)
        }

        print("[AudioProcessor] Processing \(packets.count) ADPCM packets...")

        // Step 1: Sort by sequence number (packets can arrive out of order!)
        let sortedPackets = packets.sorted { $0.seq < $1.seq }
        print("[AudioProcessor] Sorted packets by seq: \(sortedPackets.first?.seq ?? 0) to \(sortedPackets.last?.seq ?? 0)")

        // Step 2: Convert each ADPCM packet to PCM using SDK
        var processedPCMSamples: [Int] = []

        for (index, packet) in sortedPackets.enumerated() {
            let pcmSamples = convertADPCMPacketToPCM(audioData: packet.audioData)
            processedPCMSamples.append(contentsOf: pcmSamples)

            if index == 0 {
                print("[AudioProcessor] First packet: \(packet.audioData.count) ADPCM → \(pcmSamples.count) PCM samples")
            }
        }

        print("[AudioProcessor] ADPCM → PCM complete: \(processedPCMSamples.count) samples")

        // Step 3: DC offset removal (fixes ADPCM baseline drift)
        processedPCMSamples = removeDCOffset(processedPCMSamples)

        // Step 4: De-clip (reconstruct clipped peaks)
        processedPCMSamples = deClip(processedPCMSamples)

        // Step 5: Normalize to -6dB
        processedPCMSamples = normalize(processedPCMSamples, targetDb: -6.0)

        // Step 6: Upsample 8kHz → 16kHz (for Whisper)
        let originalCount = processedPCMSamples.count
        processedPCMSamples = upsample(processedPCMSamples, from: 8000, to: 16000)
        print("[AudioProcessor] Upsampled: \(originalCount) → \(processedPCMSamples.count) samples (8kHz → 16kHz)")

        return (processedPCMSamples, 16000)
    }

    // MARK: - DC Offset Removal

    /// Remove DC offset (mean value) from samples
    /// Important for ADPCM which can drift from zero baseline
    static func removeDCOffset(_ samples: [Int]) -> [Int] {
        guard !samples.isEmpty else { return samples }
        let sum = samples.reduce(0, +)
        let mean = sum / samples.count
        return samples.map { $0 - mean }
    }

    // MARK: - De-Clipper

    /// Reconstruct clipped peaks using cubic Hermite interpolation
    /// Detects regions where audio hits max/min and smoothly reconstructs
    static func deClip(_ samples: [Int], threshold: Int = 30000) -> [Int] {
        guard samples.count > 4 else { return samples }

        var output = samples
        let clipThreshold = threshold

        var i = 0
        while i < samples.count {
            if abs(samples[i]) >= clipThreshold {
                let clipStart = i
                var clipEnd = i

                while clipEnd < samples.count - 1 && abs(samples[clipEnd + 1]) >= clipThreshold {
                    clipEnd += 1
                }

                if clipStart >= 2 && clipEnd < samples.count - 2 {
                    let preStart = samples[clipStart - 2]
                    let preEnd = samples[clipStart - 1]
                    let postStart = samples[clipEnd + 1]
                    let postEnd = samples[clipEnd + 2]

                    let isPositiveClip = samples[clipStart] > 0
                    let preSlope = Float(preEnd - preStart)
                    let postSlope = Float(postEnd - postStart)

                    let clipLength = clipEnd - clipStart + 1
                    for j in 0..<clipLength {
                        let t = Float(j + 1) / Float(clipLength + 1)

                        // Hermite interpolation
                        let h00 = 2*t*t*t - 3*t*t + 1
                        let h10 = t*t*t - 2*t*t + t
                        let h01 = -2*t*t*t + 3*t*t
                        let h11 = t*t*t - t*t

                        let reconstructed = h00 * Float(preEnd) +
                                          h10 * preSlope +
                                          h01 * Float(postStart) +
                                          h11 * postSlope

                        let limited = isPositiveClip ?
                            max(Float(preEnd), min(40000, reconstructed)) :
                            min(Float(preEnd), max(-40000, reconstructed))

                        output[clipStart + j] = Int(limited)
                    }
                }

                i = clipEnd + 1
            } else {
                i += 1
            }
        }

        // Final soft clip to valid range
        return output.map { sample in
            if sample > 32767 {
                return 32767 - Int(sqrt(Float(sample - 32767)))
            } else if sample < -32768 {
                return -32768 + Int(sqrt(Float(-sample - 32768)))
            }
            return sample
        }
    }

    // MARK: - Normalizer

    /// Normalize audio to target dB level
    static func normalize(_ samples: [Int], targetDb: Float = -6.0) -> [Int] {
        guard !samples.isEmpty else { return samples }

        let peak = Float(samples.map { abs($0) }.max() ?? 0)
        guard peak > 100 else { return samples }

        let targetPeak = pow(10.0, targetDb / 20.0) * 32767.0
        let gain = targetPeak / peak

        return samples.map { sample in
            let result = Float(sample) * gain
            return Int(max(-32767, min(32767, result)))
        }
    }

    // MARK: - Upsampler

    /// Upsample audio using linear interpolation
    /// Better quality for Whisper which prefers 16kHz
    static func upsample(_ samples: [Int], from sourceSampleRate: Int = 8000, to targetSampleRate: Int = 16000) -> [Int] {
        guard sourceSampleRate < targetSampleRate else { return samples }
        guard !samples.isEmpty else { return samples }

        let ratio = Float(targetSampleRate) / Float(sourceSampleRate)
        let outputLength = Int(Float(samples.count) * ratio)

        var output = [Int](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let sourceIndex = Float(i) / ratio
            let index0 = Int(sourceIndex)
            let index1 = min(index0 + 1, samples.count - 1)
            let frac = sourceIndex - Float(index0)

            let sample0 = Float(samples[index0])
            let sample1 = Float(samples[index1])

            output[i] = Int(sample0 + frac * (sample1 - sample0))
        }

        return output
    }

    // MARK: - Legacy Pipeline (kept for compatibility)

    /// Process ADPCM audio through the full pipeline using IMA-ADPCM decoder
    /// Note: Prefer processAudioSession() which uses SDK conversion
    /// Returns: (samples: [Int], sampleRate: Int)
    static func processADPCM(_ data: Data) -> (samples: [Int], sampleRate: Int) {
        // 1. Decode ADPCM to PCM using IMA-ADPCM
        let decoded = decodeADPCM(data)
        var samples = decoded.map { Int($0) }

        // 2. DC offset removal
        samples = removeDCOffset(samples)

        // 3. De-clip
        samples = deClip(samples)

        // 4. Normalize to -6dB
        samples = normalize(samples, targetDb: -6.0)

        // 5. Upsample 8kHz → 16kHz
        samples = upsample(samples, from: 8000, to: 16000)

        return (samples, 16000)
    }

    /// Process raw PCM samples (already decoded)
    /// Note: This should only be used if samples are already PCM, not ADPCM
    static func processPCM(_ samples: [Int], sampleRate: Int = 8000) -> (samples: [Int], sampleRate: Int) {
        var processed = samples

        // DC offset removal
        processed = removeDCOffset(processed)

        // De-clip
        processed = deClip(processed)

        // Normalize
        processed = normalize(processed, targetDb: -6.0)

        // Upsample if needed
        if sampleRate < 16000 {
            processed = upsample(processed, from: sampleRate, to: 16000)
            return (processed, 16000)
        }

        return (processed, sampleRate)
    }
}
