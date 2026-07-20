import AVFoundation
import Combine
import LiveKit
import SwiftUI

/// The agent's `play_morse` tool payload.
private struct MorseCommand: Decodable {
    let text: String
    let wpm: Int?
}

/// The agent's `report_result` tool payload: the verdict on the student's last
/// answer, used to drive the on-screen score (the device does the counting).
private struct ResultReport: Decodable {
    let expected: String
    let answer: String
    let correct: Bool
}

/// Owns the LiveKit `Room` and all session orchestration, keeping it out of the
/// SwiftUI views (per project conventions). Views observe this object; it
/// re-publishes the room's changes so connection/participant updates drive the UI.
@MainActor
final class RoomManager: ObservableObject {
    let room = Room()

    /// On-device Morse renderer (audio + haptics + flash), driven by the agent's
    /// `play_morse` RPC.
    let morse = MorsePlayer()

    @Published var isConnecting = false
    @Published var errorMessage: String?

    /// Whether a session has run during this app launch. In-memory only, so fully
    /// killing the app resets it (cold start → only "Start talking"), while
    /// backgrounding preserves it. Drives the continue / new-session choice.
    @Published private(set) var hasPreviousSession = false

    /// Running score for the current session, driven by the agent's `report_result`
    /// RPC. The device owns this counting/percentage math (deterministic on-device);
    /// the agent only sends the per-answer verdict.
    @Published private(set) var attempts = 0
    @Published private(set) var correctCount = 0
    @Published private(set) var lastExpected: String?
    @Published private(set) var lastAnswer: String?
    @Published private(set) var lastCorrect: Bool?

    var accuracyPercent: Int {
        attempts == 0 ? 0 : Int((Double(correctCount) / Double(attempts) * 100).rounded())
    }

    private var roomChanges: AnyCancellable?
    private var morseChanges: AnyCancellable?
    private let tokenService = TokenService()

    init() {
        // Forward the Room's and player's published changes so views observing
        // RoomManager refresh on connection / participant / tone updates.
        roomChanges = room.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        morseChanges = morse.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: Derived state

    var connectionState: ConnectionState { room.connectionState }

    /// The tutor agent in the room, if present (falls back to any remote peer).
    var agent: RemoteParticipant? {
        let remotes = Array(room.remoteParticipants.values)
        return remotes.first { $0.kind == .agent } ?? remotes.first
    }

    /// A human-readable label for the agent's current activity, surfaced from the
    /// `lk.agent.state` attribute the LiveKit Agents framework publishes.
    var agentStatus: String {
        guard let agent else { return "Waiting for tutor to join…" }
        switch agent.attributes["lk.agent.state"] {
        case "initializing": return "Tutor is starting up…"
        case "listening": return "Listening — go ahead"
        case "thinking": return "Thinking…"
        case "speaking": return "Speaking"
        default: return "Connected"
        }
    }

    var isAgentSpeaking: Bool {
        guard let agent else { return false }
        return room.activeSpeakers.contains { $0.identity == agent.identity }
    }

    // MARK: Actions

    /// Start a brand-new session: a fresh `morse-new-…` room, so the agent gives
    /// its full self-introduction and starts over.
    func startNewSession() async {
        resetScore()
        await connect(roomName: "morse-new-\(Self.shortID())")
    }

    /// Zero the running score. Called when starting a brand-new session; a continued
    /// session keeps its score so accuracy carries across the resume.
    private func resetScore() {
        attempts = 0
        correctCount = 0
        lastExpected = nil
        lastAnswer = nil
        lastCorrect = nil
    }

    /// Record the agent's verdict on the student's last answer (from `report_result`).
    private func recordResult(_ report: ResultReport) {
        attempts += 1
        if report.correct { correctCount += 1 }
        lastExpected = report.expected
        lastAnswer = report.answer
        lastCorrect = report.correct
    }

    /// Resume practicing: a fresh `morse-cont-…` room (reliable agent dispatch),
    /// but the agent skips the introduction and goes straight back to practice.
    func continueLastSession() async {
        await connect(roomName: "morse-cont-\(Self.shortID())")
    }

    private static func shortID() -> String {
        String(UUID().uuidString.prefix(8).lowercased())
    }

    private func connect(roomName: String) async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        guard await Self.requestMicrophonePermission() else {
            errorMessage = "Microphone access is required to talk to your tutor. "
                + "Enable it in Settings → MorseMate."
            return
        }

        do {
            let details = try await tokenService.fetchConnectionDetails(
                roomName: roomName,
                participantName: AppConfig.participantName
            )
            try await room.connect(
                url: details.serverUrl,
                token: details.participantToken,
                connectOptions: ConnectOptions(enableMicrophone: true)
            )
            await registerRpcHandlers()
            hasPreviousSession = true
        } catch let error as TokenServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        await room.disconnect()
    }

    /// Send the learner's tapped Morse to the agent for feedback (the "send" half
    /// of the loop). Symmetric to the `play_morse` RPC.
    func submitTap(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let agentIdentity = agent?.identity else { return }
        let payload = #"{"decoded":"\#(trimmed)"}"#
        _ = try? await room.localParticipant.performRpc(
            destinationIdentity: agentIdentity,
            method: "submit_tap",
            payload: payload
        )
    }

    /// Register the agent → device RPC methods. Both ack and never throw back to the
    /// agent — a render hiccup or UI update must not break the turn.
    private func registerRpcHandlers() async {
        // `play_morse` drives on-device Morse playback.
        try? await room.registerRpcMethod("play_morse") { [weak self] data in
            guard let self else { return #"{"status":"unavailable"}"# }
            guard let payload = data.payload.data(using: .utf8),
                  let command = try? JSONDecoder().decode(MorseCommand.self, from: payload)
            else {
                return #"{"status":"bad_request"}"#
            }
            let ms = await self.morse.play(command.text, wpm: command.wpm ?? 10)
            return #"{"status":"played","durationMs":\#(ms)}"#
        }

        // `report_result` carries the tutor's verdict on the student's last answer,
        // driving the on-screen score. The device does the counting.
        try? await room.registerRpcMethod("report_result") { [weak self] data in
            guard let self else { return #"{"status":"unavailable"}"# }
            guard let payload = data.payload.data(using: .utf8),
                  let report = try? JSONDecoder().decode(ResultReport.self, from: payload)
            else {
                return #"{"status":"bad_request"}"#
            }
            await self.recordResult(report)
            return #"{"status":"ok"}"#
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
