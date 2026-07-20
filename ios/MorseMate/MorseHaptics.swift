import CoreHaptics

/// Plays a Morse timeline through the Taptic Engine, in lock-step with the audio.
///
/// Haptics are **device-only** — `supportsHaptics` is false on the Simulator, so
/// this no-ops there.
final class MorseHaptics {
    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        try? engine?.start()
    }

    /// Build a continuous-haptic pattern mirroring the `on` spans of the timeline
    /// and start it immediately (called at the same moment audio playback begins).
    func play(segments: [MorseCode.Segment], ditSeconds: Double) {
        guard let engine else { return }

        var events: [CHHapticEvent] = []
        var time = 0.0
        for segment in segments {
            let duration = Double(segment.units) * ditSeconds
            if segment.isOn {
                events.append(
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                        ],
                        relativeTime: time,
                        duration: duration
                    )
                )
            }
            time += duration
        }
        guard !events.isEmpty else { return }

        do {
            try engine.start()  // ensure running after any interruption
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Haptics are a non-essential enhancement; never fail playback over them.
        }
    }
}
