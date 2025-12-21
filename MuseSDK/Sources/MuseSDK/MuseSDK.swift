//
//  MuseSDK.swift
//  MuseSDK
//
//  Smart Ring SDK wrapper for voice memo features
//

import Foundation
@_exported import BCLRingSDK

// MARK: - Version Info

public struct MuseSDK {
    public static let version = "1.0.0"
    public static let bclVersion = BCLFrameworkInfo.version

    private init() {}
}

// MARK: - Convenience Typealiases

/// Main ring manager singleton
public typealias RingManager = BCLRingManager

/// Device info model (used for scanning and connection)
public typealias DeviceInfo = BCLDeviceInfoModel

/// Audio format types
public typealias AudioFormat = BCLAudioType

/// Bluetooth system state
public typealias BluetoothState = BCLCentralManagerBluetoothState

/// Time zones for ring sync
public typealias RingTimeZone = BCLRingTimeZone

/// Ring error type
public typealias RingError = BCLError

// MARK: - Audio Extensions

public extension BCLRingManager {

    /// Start ADPCM audio streaming (recommended for voice)
    /// - Parameter completion: Called when streaming starts or fails
    func startAudioStream(completion: @escaping (Result<Void, BCLError>) -> Void) {
        controlADPCMFormatAudio(isOpen: true) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Stop audio streaming
    /// - Parameter completion: Called when streaming stops or fails
    func stopAudioStream(completion: @escaping (Result<Void, BCLError>) -> Void) {
        controlADPCMFormatAudio(isOpen: false) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Configure touch-triggered audio format
    /// - Parameters:
    ///   - format: Audio format (.pcm or .adpcm, recommend .adpcm)
    ///   - completion: Called when configuration completes
    func configureTouchAudio(format: BCLAudioType = .adpcm, completion: @escaping (Result<Void, BCLError>) -> Void) {
        setActivePushAudioInfo(audioType: format) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Connection Extensions

public extension BCLRingManager {

    /// Quick connect by MAC address
    func quickConnect(
        macAddress: String,
        autoReconnect: Bool = false,
        completion: @escaping (Result<DeviceInfo, BCLError>) -> Void
    ) {
        isAutoReconnectEnabled = autoReconnect
        startConnect(macAddress: macAddress, isAutoReconnect: autoReconnect, connectResultBlock: completion)
    }

    /// Quick connect by UUID
    func quickConnect(
        uuid: String,
        autoReconnect: Bool = false,
        completion: @escaping (Result<DeviceInfo, BCLError>) -> Void
    ) {
        isAutoReconnectEnabled = autoReconnect
        startConnect(uuidString: uuid, isAutoReconnect: autoReconnect, connectResultBlock: completion)
    }
}

// MARK: - ADPCM Decoder

/// Decodes ADPCM audio data to PCM Int16 samples
public class ADPCMDecoder {

    private var index: Int = 0
    private var prevSample: Int = 0

    private static let indexTable: [Int] = [
        -1, -1, -1, -1, 2, 4, 6, 8,
        -1, -1, -1, -1, 2, 4, 6, 8
    ]

    private static let stepTable: [Int] = [
        7, 8, 9, 10, 11, 12, 13, 14,
        16, 17, 19, 21, 23, 25, 28, 31,
        34, 37, 41, 45, 50, 55, 60, 66,
        73, 80, 88, 97, 107, 118, 130, 143,
        157, 173, 190, 209, 230, 253, 279, 307,
        337, 371, 408, 449, 494, 544, 598, 658,
        724, 796, 876, 963, 1060, 1166, 1282, 1411,
        1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024,
        3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484,
        7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
        15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
        32767
    ]

    public init() {}

    /// Reset decoder state (call between recordings)
    public func reset() {
        index = 0
        prevSample = 0
    }

    /// Decode ADPCM bytes to PCM Int16 samples
    public func decode(_ adpcmData: Data) -> [Int16] {
        var samples: [Int16] = []
        samples.reserveCapacity(adpcmData.count * 2)

        for byte in adpcmData {
            // Low nibble first, then high nibble
            let sample1 = decodeSample(Int(byte & 0x0F))
            let sample2 = decodeSample(Int((byte >> 4) & 0x0F))
            samples.append(sample1)
            samples.append(sample2)
        }

        return samples
    }

    private func decodeSample(_ nibble: Int) -> Int16 {
        let step = Self.stepTable[index]

        var diff = step >> 3
        if nibble & 4 != 0 { diff += step }
        if nibble & 2 != 0 { diff += step >> 1 }
        if nibble & 1 != 0 { diff += step >> 2 }

        if nibble & 8 != 0 {
            prevSample -= diff
        } else {
            prevSample += diff
        }

        // Clamp to Int16 range
        prevSample = max(-32768, min(32767, prevSample))

        // Update index
        index += Self.indexTable[nibble]
        index = max(0, min(88, index))

        return Int16(prevSample)
    }
}
