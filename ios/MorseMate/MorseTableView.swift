import SwiftUI

/// A read-only reference of the full character ↔ Morse mapping, shown as a bottom
/// sheet. Presenting it does not affect the live session — the LiveKit `Room`
/// lives in `RoomManager` and is untouched by this view.
struct MorseTableView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                section("Letters") { $0.isLetter }
                section("Numbers") { $0.isNumber }
                section("Symbols") { !$0.isLetter && !$0.isNumber }
            }
            .navigationTitle("Morse Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, where include: @escaping (Character) -> Bool) -> some View {
        Section(title) {
            ForEach(entries(include), id: \.character) { row in
                HStack {
                    Text(String(row.character))
                        .font(.title3.bold().monospaced())
                    Spacer()
                    Text(MorseCode.glyphs(for: row.pattern))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func entries(_ include: (Character) -> Bool) -> [(character: Character, pattern: String)] {
        MorseCode.table
            .filter { include($0.key) }
            .sorted { $0.key < $1.key }
            .map { (character: $0.key, pattern: $0.value) }
    }
}

#Preview {
    MorseTableView()
}
