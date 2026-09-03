import AppKit
import Foundation

/// Builds a short, mechanical-sounding buzzer once in memory. Keeping the
/// waveform synthetic avoids shipping or decoding an external audio asset.
enum BuzzerSoundFactory {
    private static let sampleRate = 22_050
    private static let duration: TimeInterval = 0.72

    static func makeSound() -> NSSound? {
        NSSound(data: makeWaveData())
    }

    private static func makeWaveData() -> Data {
        let sampleCount = Int(Double(sampleRate) * duration)
        let dataByteCount = sampleCount * MemoryLayout<Int16>.size
        var wave = Data(capacity: 44 + dataByteCount)

        wave.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + dataByteCount), to: &wave)
        wave.append(contentsOf: "WAVE".utf8)
        wave.append(contentsOf: "fmt ".utf8)
        append(UInt32(16), to: &wave)
        append(UInt16(1), to: &wave) // Linear PCM
        append(UInt16(1), to: &wave) // Mono
        append(UInt32(sampleRate), to: &wave)
        append(UInt32(sampleRate * MemoryLayout<Int16>.size), to: &wave)
        append(UInt16(MemoryLayout<Int16>.size), to: &wave)
        append(UInt16(16), to: &wave)
        wave.append(contentsOf: "data".utf8)
        append(UInt32(dataByteCount), to: &wave)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)

            // Two close square waves create the throbbing texture of a small
            // electromechanical buzzer; the octave adds a sharper edge.
            let primary = squareWave(frequency: 145, at: time)
            let detuned = squareWave(frequency: 152, at: time)
            let octave = squareWave(frequency: 290, at: time)
            let vibration = 0.88 + (0.12 * sin(2 * .pi * 27 * time))

            let attack = min(1, time / 0.008)
            let release = min(1, (duration - time) / 0.055)
            let envelope = attack * max(0, release)
            let mixed = ((0.54 * primary) + (0.31 * detuned) + (0.15 * octave))
                * vibration
                * envelope
                * 0.72
            let sample = Int16(max(-1, min(1, mixed)) * Double(Int16.max))
            append(UInt16(bitPattern: sample), to: &wave)
        }

        return wave
    }

    private static func squareWave(frequency: Double, at time: TimeInterval) -> Double {
        sin(2 * .pi * frequency * time) >= 0 ? 1 : -1
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
