import AVFoundation
import Combine
import LiveKit
import SwiftUI

/// The agent's `play_morse` tool payload.
private struct MorseCommand: Decodable {
    let text: String
    let wpm: Int?
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
        await connect(roomName: "morse-new-\(Self.shortID())")
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
            await registerMorseHandler()
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
    /// of the loop, technical_design §4.2). Symmetric to the `play_morse` RPC.
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

    /// Register the `play_morse` RPC method so the agent can drive on-device Morse
    /// playback (technical_design §4.1). Acks with the played duration; never
    /// throws back to the agent — a render hiccup must not break the turn.
    private func registerMorseHandler() async {
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
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
