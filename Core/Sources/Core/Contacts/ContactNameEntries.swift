import Foundation

/// 連絡先の氏名から、ユーザ辞書に登録する表記と読みを作る
///
/// Contacts framework に依存しないよう、氏名とフリガナだけを受け取る。
/// - フリガナが未登録の部分（姓・名）は登録しない（読みの推定はしない）
/// - 姓名の両方が揃っていれば「姓名」を、加えて姓のみ・名のみも登録する
public enum ContactNameEntries {
    public struct Name: Sendable, Equatable {
        public init(familyName: String, givenName: String, phoneticFamilyName: String, phoneticGivenName: String) {
            self.familyName = familyName
            self.givenName = givenName
            self.phoneticFamilyName = phoneticFamilyName
            self.phoneticGivenName = phoneticGivenName
        }

        public var familyName: String
        public var givenName: String
        public var phoneticFamilyName: String
        public var phoneticGivenName: String
    }

    public struct Entry: Sendable, Hashable {
        public init(word: String, reading: String) {
            self.word = word
            self.reading = reading
        }

        public var word: String
        /// ひらがな・カタカナの読み
        public var reading: String
    }

    /// 複数の連絡先から重複を除いて登録項目を作る。順序は入力順を保つ
    public static func entries(from names: some Sequence<Name>) -> [Entry] {
        var seen: Set<Entry> = []
        var result: [Entry] = []
        for name in names {
            for entry in Self.entries(from: name) where seen.insert(entry).inserted {
                result.append(entry)
            }
        }
        return result
    }

    public static func entries(from name: Name) -> [Entry] {
        let family = Self.part(word: name.familyName, reading: name.phoneticFamilyName)
        let given = Self.part(word: name.givenName, reading: name.phoneticGivenName)
        var result: [Entry] = []
        if let family, let given {
            result.append(.init(word: family.word + given.word, reading: family.reading + given.reading))
        }
        if let family {
            result.append(family)
        }
        if let given {
            result.append(given)
        }
        return result
    }

    private static func part(word: String, reading: String) -> Entry? {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        // フリガナ中の空白（「やま だ」など）は取り除く
        let reading = reading.filter { !$0.isWhitespace }
        guard !word.isEmpty, !reading.isEmpty, Self.isKanaReading(reading) else {
            return nil
        }
        return .init(word: word, reading: reading)
    }

    /// 読みとして使える文字（ひらがな・カタカナ・長音記号）だけでできているか
    static func isKanaReading(_ reading: String) -> Bool {
        reading.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x3041 ... 0x3096, // ひらがな
                 0x309D ... 0x309E, // ゝゞ
                 0x30A1 ... 0x30FA, // カタカナ
                 0x30FC ... 0x30FE: // ー ヽヾ
                true
            default:
                false
            }
        }
    }
}
