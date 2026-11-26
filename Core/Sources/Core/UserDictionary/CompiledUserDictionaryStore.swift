import Crypto
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

public enum CompiledUserDictionaryStore {
    enum BuildError: Error {
        case missingCharIDFile
    }

    public enum SourceError: Error, Equatable {
        /// 保存された辞書データを読めなかった
        case corruptedSource(key: String)
    }

    /// コンパイル済み辞書を構成するファイル
    static let compiledFileNames = ["user.louds", "user.loudschars2", "user0.loudstxt3"]

    public static func directoryURL(memoryDirectoryURL: URL) -> URL {
        memoryDirectoryURL.appendingPathComponent("UserDictionary", isDirectory: true)
    }

    public static func exportCurrentDictionaries(memoryDirectoryURL: URL) throws {
        try Self.rebuild(
            entries: Self.currentEntries(),
            directoryURL: Self.directoryURL(memoryDirectoryURL: memoryDirectoryURL)
        )
    }

    public static func hasExportedDictionary(memoryDirectoryURL: URL) -> Bool {
        Self.hasCompiledDictionary(at: Self.directoryURL(memoryDirectoryURL: memoryDirectoryURL))
    }

    /// 設定に保存された辞書項目を集める
    ///
    /// 保存データが壊れている場合は既定値に置き換えず`SourceError`を投げる。
    /// 既定値で書き出すと、利用者の辞書が失われてしまうため。
    public static func currentEntries() throws -> [DicdataElement] {
        let userItems = try Self.strictValue(of: Config.UserDictionary()).items
        let systemItems = try Self.strictValue(of: Config.SystemUserDictionary()).items
        return (userItems + systemItems).map { item in
            Self.entry(word: item.word, reading: item.reading)
        }
    }

    /// 辞書に登録する1項目を作る
    public static func entry(word: String, reading: String) -> DicdataElement {
        DicdataElement(word: word, ruby: reading.toKatakana(), cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
    }

    static func strictValue<Item: CustomCodableConfigItem>(of item: Item) throws -> Item.Value {
        guard let data = Config.data(forKey: Item.key) else {
            return Item.default
        }
        do {
            return try JSONDecoder().decode(Item.Value.self, from: data)
        } catch {
            throw SourceError.corruptedSource(key: Item.key)
        }
    }

    /// 辞書項目の内容から指紋を作る。内容が変わったかどうかの判定にだけ使う
    public static func fingerprint(of entries: [DicdataElement]) -> String {
        var hasher = SHA256()
        // 書き出し形式を変えたときに再構築させるための版数
        hasher.update(data: Data("v1\n".utf8))
        for entry in entries {
            hasher.update(data: Data("\(entry.word)\t\(entry.ruby)\t\(entry.lcid)\t\(entry.mid)\t\(entry.value())\n".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// コンパイル済み辞書のディレクトリの更新日時。存在しなければ`nil`
    public static func modificationDate(at directoryURL: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: directoryURL.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    /// 読み込んでよい状態か。ファイルが揃っているか、項目が無く1つも無い場合に`true`
    public static func isUsableCompiledDictionary(at directoryURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        let existing = Self.compiledFileNames.filter {
            FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent($0, isDirectory: false).path)
        }
        return existing.isEmpty || existing.count == Self.compiledFileNames.count
    }

    static func hasCompiledDictionary(at directoryURL: URL) -> Bool {
        Self.compiledFileNames.allSatisfy {
            FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent($0, isDirectory: false).path)
        }
    }

    public static func rebuild(entries: [DicdataElement], directoryURL: URL, charIDFileURL: URL? = nil) throws {
        let fileManager = FileManager.default
        let parentURL = directoryURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let temporaryURL = parentURL.appendingPathComponent(
            "\(directoryURL.lastPathComponent).building-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: true)

        do {
            if !entries.isEmpty {
                guard let charIDFileURL = charIDFileURL ?? Self.defaultCharIDFileURL() else {
                    throw BuildError.missingCharIDFile
                }
                let supportedCharacters = Set(try String(contentsOf: charIDFileURL, encoding: .utf8))
                let indexableEntries = entries.filter {
                    !$0.ruby.isEmpty && $0.ruby.allSatisfy(supportedCharacters.contains)
                }
                if !indexableEntries.isEmpty {
                    try DictionaryBuilder.exportDictionary(
                        entries: indexableEntries,
                        to: temporaryURL,
                        baseName: "user",
                        shardByFirstCharacter: false,
                        charIDFileURL: charIDFileURL
                    )
                }
            }

            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: directoryURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func defaultCharIDFileURL() -> URL? {
        _ = DicdataStore.withDefaultDictionary(preloadDictionary: false)
        let fileManager = FileManager.default
        var resourceURLs = (Bundle.allBundles + Bundle.allFrameworks).compactMap(\.resourceURL)

        if let mainResourceURL = Bundle.main.resourceURL,
           let enumerator = fileManager.enumerator(
            at: mainResourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
           ) {
            for case let url as URL in enumerator where url.pathExtension == "bundle" {
                if let bundle = Bundle(url: url), let resourceURL = bundle.resourceURL {
                    resourceURLs.append(resourceURL)
                } else {
                    resourceURLs.append(url.appendingPathComponent("Contents/Resources", isDirectory: true))
                }
            }
        }

        return resourceURLs.lazy
            .map {
                $0.appendingPathComponent("Dictionary/louds/charID.chid", isDirectory: false)
            }
            .first {
                fileManager.fileExists(atPath: $0.path)
            }
    }
}
