import AVFoundation
import SwiftUI

/// Renders a Morse string deterministically on-device: a precise ~600 Hz sine at
/// a target WPM, synchronized with haptics and a visual flash.
///
/// The full sequence is known up front, so we pre-render one PCM buffer and play
/// it through an `AVAudioPlayerNode` — sample-accurate and click-free, without a
/// real-time render callback. The app owns its own `AVAudioEngine`; it plays
/// through whatever `AVAudioSession` LiveKit already holds while connected.
@MainActor
final class MorsePlayer: ObservableObject {
    /// True while a sequence is playing. Drives UI.
    @Published private(set) var isPlaying = false
    /// True while a tone is sounding — the crisp visual "keyer" flash.
    @Published private(set) var isToneOn = false
    /// The most recent text rendered, for display.
    @Published private(set) var lastText = ""

    let frequency: Double = 600

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let haptics = MorseHaptics()
    private var connectedFormat: AVAudioFormat?

    /// Play `text` as Morse at `wpm`. Returns the total duration in milliseconds
    /// once playback finishes (drives the `play_morse` RPC ack — §4.1).
    @discardableResult
    func play(_ text: String, wpm: Int) async -> Int {
        let segments = MorseCode.segments(for: text)
        guard !segments.isEmpty else { return 0 }

        let dit = MorseCode.ditSeconds(wpm: wpm)
        let session = AVAudioSession.sharedInstance()
        let sampleRate = session.sampleRate > 0 ? session.sampleRate : 48_000
        guard let buffer = Self.renderBuffer(
            segments: segments, ditSeconds: dit, sampleRate: sampleRate, frequency: frequency
        ) else { return 0 }

        let totalMs = Int((Double(MorseCode.totalUnits(segments)) * dit) * 1000)

        lastText = text
        isPlaying = true
        defer {
            isPlaying = false
            isToneOn = false
        }

        guard configureEngine(format: buffer.format) else { return 0 }

        // Fire haptics + visual on the same timeline as the audio.
        haptics.play(segments: segments, ditSeconds: dit)
        let flash = Task { @MainActor in await self.driveFlash(segments: segments, ditSeconds: dit) }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buffer, at: nil, options: []) {
                continuation.resume()
            }
            player.play()
        }
        flash.cancel()
        return totalMs
    }

    // MARK: - Engine

    private func configureEngine(format: AVAudioFormat) -> Bool {
        if connectedFormat != format {
            if player.engine == nil { engine.attach(player) }
            engine.connect(player, to: engine.mainMixerNode, format: format)
            connectedFormat = format
        }
        do {
            if !engine.isRunning { try engine.start() }
            return true
        } catch {
            return false
        }
    }

    /// Toggle the visual flash across the timeline. Audio is the reference clock;
    /// this runs alongside and is cancelled when audio completes.
    private func driveFlash(segments: [MorseCode.Segment], ditSeconds: Double) async {
        for segment in segments {
            isToneOn = segment.isOn
            let nanos = UInt64(Double(segment.units) * ditSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { break }
        }
        isToneOn = false
    }

    // MARK: - Rendering

    /// Pre-render the full timeline into a mono float buffer. Each tone gets a
    /// short fade in/out to avoid clicks.
    nonisolated static func renderBuffer(
        segments: [MorseCode.Segment],
        ditSeconds: Double,
        sampleRate: Double,
        frequency: Double
    ) -> AVAudioPCMBuffer? {
        let ditFrames = max(1, Int((ditSeconds * sampleRate).rounded()))
        let totalFrames = segments.reduce(0) { $0 + $1.units * ditFrames }
        guard totalFrames > 0,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                  channels: 1, interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)
              )
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(totalFrames)
        let samples = buffer.floatChannelData![0]
        let amplitude: Float = 0.6
        let ramp = max(1, min(ditFrames / 8, Int(0.004 * sampleRate)))  // ~4 ms

        var index = 0
        for segment in segments {
            let n = segment.units * ditFrames
            if segment.isOn {
                for k in 0..<n {
                    let t = Double(k) / sampleRate
                    var s = Float(sin(2.0 * Double.pi * frequency * t)) * amplitude
                    if k < ramp {
                        s *= Float(k) / Float(ramp)
                    } else if k >= n - ramp {
                        s *= Float(n - k) / Float(ramp)
                    }
                    samples[index + k] = s
                }
            } else {
                for k in 0..<n { samples[index + k] = 0 }
            }
            index += n
        }
        return buffer
    }
}
