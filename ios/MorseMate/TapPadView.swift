import SwiftUI

/// An on-screen Morse key for "sending" practice. Dot, dash, and space are three
/// sections of one rounded rectangle; delete (⌫) sits beside it and Send is below.
/// Builds multi-character patterns and hands the decoded text to `onSend`.
struct TapPadView: View {
    /// Called with the decoded text (e.g. "ET") when the learner taps Send.
    let onSend: (String) -> Void

    @State private var letters: [String] = []   // committed letter patterns
    @State private var current = ""              // in-progress letter

    private var isEmpty: Bool { letters.isEmpty && current.isEmpty }

    private var pending: [String] { letters + (current.isEmpty ? [] : [current]) }

    private var preview: String {
        guard !pending.isEmpty else { return "Tap out Morse, then Send" }
        let pattern = pending.map(Self.glyphs).joined(separator: "   ")
        return "\(pattern)   →   \(MorseCode.decode(pending))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(preview)
                .font(.title3.monospaced())
                .foregroundStyle(isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 28)

            HStack(spacing: 12) {
                // Dot / dash / space as three sections of one rounded rectangle.
                HStack(spacing: 0) {
                    segment("·", label: "dot") { current += "." }
                    sectionDivider
                    segment("–", label: "dash") { current += "-" }
                    sectionDivider
                    segment("space", label: "letter space") { commitLetter() }
                }
                .frame(height: 52)
                .background(Color(.secondarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Delete sits apart, to the right — same height and fill as the group.
                Button(action: backspace) {
                    Image(systemName: "delete.left")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(isEmpty ? Color.secondary : Color.primary)
                        .frame(width: 60, height: 52)
                        .background(Color(.secondarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("delete")
                .disabled(isEmpty)
            }

            Button(action: send) {
                Label("Send", systemImage: "paperplane.fill")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isEmpty)
        }
    }

    private var sectionDivider: some View {
        Divider().frame(height: 28)
    }

    /// One tappable section of the grouped key rectangle.
    private func segment(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .buttonStyle(SegmentButtonStyle())
        .accessibilityLabel(label)
    }

    private func commitLetter() {
        guard !current.isEmpty else { return }
        letters.append(current)
        current = ""
    }

    /// Delete the most recent input: a dit/dash from the in-progress letter, or —
    /// if none — undo the last space by pulling the previous letter back into edit.
    private func backspace() {
        if !current.isEmpty {
            current.removeLast()
        } else if !letters.isEmpty {
            current = letters.removeLast()
        }
    }

    private func send() {
        commitLetter()
        let text = MorseCode.decode(letters)
        letters = []
        current = ""
        if !text.isEmpty { onSend(text) }
    }

    /// Render a letter's "."/"-" pattern as Morse glyphs for display.
    private static func glyphs(_ pattern: String) -> String {
        pattern.map { $0 == "." ? "·" : "–" }.joined()
    }
}

/// Fills its section of the grouped key and highlights on press, so dot/dash/space
/// read as three clickable parts of one rectangle.
private struct SegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : Color.clear)
    }
}
