import LiveKit
import SwiftUI

struct ContentView: View {
    @StateObject private var manager = RoomManager()
    @State private var showingMorseTable = false

    var body: some View {
        VStack(spacing: 28) {
            header

            Button {
                showingMorseTable = true
            } label: {
                Label("Morse code table", systemImage: "tablecells")
            }
            .buttonStyle(.bordered)

            Spacer()

            switch manager.connectionState {
            case .connected:
                connectedView
            case .connecting, .reconnecting:
                connectingView
            default:
                if manager.isConnecting { connectingView } else { disconnectedView }
            }

            Spacer()

            if let error = manager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .padding(24)
        .animation(.default, value: manager.connectionState)
        .animation(.default, value: manager.errorMessage)
        .animation(.default, value: manager.hasPreviousSession)
        .sheet(isPresented: $showingMorseTable) {
            MorseTableView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 4) {
            Text("MorseMate")
                .font(.largeTitle.bold())
            Text("Learn Morse code by ear")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var disconnectedView: some View {
        VStack(spacing: 16) {
            orb(active: false)
            if !manager.hasPreviousSession {
                // Cold start — only one way in.
                Text("Tap to start a lesson")
                    .foregroundStyle(.secondary)
                sessionButton("Start talking", systemImage: "mic.fill", prominent: true) {
                    Task { await manager.startNewSession() }
                }
            } else {
                // A session has ended this launch — offer to continue or restart.
                Text("Session ended")
                    .foregroundStyle(.secondary)
                sessionButton("Continue last session", systemImage: "arrow.clockwise.circle.fill",
                              prominent: true) {
                    Task { await manager.continueLastSession() }
                }
                sessionButton("Start a new session", systemImage: "sparkles", prominent: false) {
                    Task { await manager.startNewSession() }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionButton(
        _ title: String, systemImage: String, prominent: Bool, action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(manager.isConnecting)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(manager.isConnecting)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting to your tutor…")
                .foregroundStyle(.secondary)
        }
    }

    private var connectedView: some View {
        VStack(spacing: 20) {
            if manager.morse.isPlaying {
                keyer(on: manager.morse.isToneOn)
                Text("Morse: \(manager.morse.lastText)")
                    .font(.headline.monospaced())
            } else {
                orb(active: manager.isAgentSpeaking)
                Text(manager.agentStatus)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            TapPadView { text in
                Task { await manager.submitTap(text) }
            }

            Button(role: .destructive) {
                Task { await manager.disconnect() }
            } label: {
                Label("End session", systemImage: "phone.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    /// Simple voice "orb" that pulses while the tutor is speaking.
    private func orb(active: Bool) -> some View {
        Circle()
            .fill(active ? Color.accentColor : Color.secondary.opacity(0.25))
            .frame(width: 140, height: 140)
            .scaleEffect(active ? 1.08 : 1.0)
            .overlay(
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 44))
                    .foregroundStyle(active ? .white : .secondary)
            )
            .animation(.easeInOut(duration: 0.35).repeatCount(active ? .max : 1, autoreverses: true),
                       value: active)
    }

    /// Crisp on/off flash that mirrors the dits and dahs (no easing) while the
    /// agent's play_morse runs.
    private func keyer(on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(on ? Color.yellow : Color.secondary.opacity(0.18))
            .frame(width: 160, height: 160)
            .overlay(
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundStyle(on ? .black : .secondary)
            )
    }
}

#Preview {
    ContentView()
}
