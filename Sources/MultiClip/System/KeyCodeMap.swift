import Foundation

/// Maps single letters/digits to ANSI virtual key codes for hot-key config.
enum KeyCodeMap {
    private static let letters: [Character: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16,
        "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
        "8": 28, "9": 25, "0": 29
    ]
    private static let reverse: [UInt32: Character] = {
        var r: [UInt32: Character] = [:]
        for (k, v) in letters { r[v] = k }
        return r
    }()

    static func keyCode(for character: Character) -> UInt32? {
        letters[Character(character.lowercased())]
    }

    static func character(for keyCode: UInt32) -> Character? {
        reverse[keyCode]
    }
}
