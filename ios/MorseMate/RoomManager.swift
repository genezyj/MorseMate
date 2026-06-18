import AVFoundation
import Combine
import LiveKit
import SwiftUI

/// Owns the LiveKit `Room` and all session orchestration, keeping it out of the
/// SwiftUI views (per project conventions). Views observe this object; it
/// re-publishes the room's changes so connection/participant updates drive the UI.
@MainActor
final class RoomManager: ObservableObject {
    let room = Room()

    @Published var isConnecting = false
    @Published var errorMessage: String?

    private var roomChanges: AnyCancellable?
    private let tokenService = TokenService()

    init() {
        // Forward the Room's published changes so views observing RoomManager
        // refresh on connection-state / participant / attribute updates.
        roomChanges = room.objectWillChange.sink { [weak self] _ in
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

    func connect() async {
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
                participantName: AppConfig.participantName
            )
            try await room.connect(
                url: details.serverUrl,
                token: details.participantToken,
                connectOptions: ConnectOptions(enableMicrophone: true)
            )
        } catch let error as TokenServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        await room.disconnect()
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
