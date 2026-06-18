import Foundation

/// Pure, deterministic Morse logic — the single source of truth for the audio,
/// haptic, and visual renderers. Has no dependency on audio hardware or LiveKit,
/// so it is unit-testable on its own (technical_design §3.3, §7).
enum MorseCode {
    /// International Morse for letters, digits, and a few common marks.
    /// `.` = dit, `-` = dah.
    static let table: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
        "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
        "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
        "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
        "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
        "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "/": "-..-.",
        "-": "-....-", "=": "-...-", "@": ".--.-.",
    ]

    /// One on/off span of the timeline, measured in **dit units** (PARIS standard):
    /// dit = 1 on-unit, dah = 3 on-units, intra-character gap = 1 off-unit,
    /// inter-character gap = 3 off-units, inter-word gap = 7 off-units.
    struct Segment: Equatable {
        let isOn: Bool
        let units: Int
    }

    /// Flatten text into an on/off segment timeline with no leading or trailing
    /// gap. Unknown characters are skipped.
    static func segments(for text: String) -> [Segment] {
        var result: [Segment] = []
        let words = text.uppercased().split(separator: " ", omittingEmptySubsequences: true)
        for (wordIndex, word) in words.enumerated() {
            if wordIndex > 0 { result.append(Segment(isOn: false, units: 7)) }  // inter-word
            let letters = word.compactMap { table[$0] != nil ? $0 : nil }
            for (letterIndex, letter) in letters.enumerated() {
                guard let code = table[letter] else { continue }
                if letterIndex > 0 { result.append(Segment(isOn: false, units: 3)) }  // inter-char
                for (symbolIndex, symbol) in code.enumerated() {
                    if symbolIndex > 0 { result.append(Segment(isOn: false, units: 1)) }  // intra-char
                    result.append(Segment(isOn: true, units: symbol == "." ? 1 : 3))
                }
            }
        }
        return result
    }

    /// Total dit-units in a timeline (for duration math).
    static func totalUnits(_ segments: [Segment]) -> Int {
        segments.reduce(0) { $0 + $1.units }
    }

    /// Duration of one dit in seconds for a target words-per-minute.
    /// PARIS standard: dit_ms = 1200 / wpm.
    static func ditSeconds(wpm: Int) -> Double {
        1.2 / Double(max(1, wpm))
    }
}
