import Foundation
#if os(macOS)
import AppKit
import SQLite3
#endif

/// macOSのユーザ辞書データを取り出すためのヘルパー
///
/// - note:
///   `bash`コマンドとしては次の通りのものに対応
///   ```bash
///   sqlite3 -header -csv ~/Library/KeyboardServices/TextReplacements.db "SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY"
///   ```
public enum SystemUserDictionaryHelper: Sendable {
    public struct Entry: Sendable {
        public let shortcut: String
        public let phrase: String
    }

    public enum FetchError: Sendable, Error, Equatable {
        case unsupportedOperatingSystem
        case fileNotExist(String)
        case fileNotReadable(String)
        case failedToOpenDatabase(status: Int32)
        case failedToPrepareStatement(status: Int32)
        /// 行の読み取りが途中で失敗した（`SQLITE_BUSY`など）
        case failedToReadRows(status: Int32)
    }

    #if os(macOS)
    /// Delegate that allows the user to choose **only** a directory named "KeyboardServices".
    private final class KeyboardServicesDirectoryDelegate: NSObject, NSOpenSavePanelDelegate {
        private let allowedFolderName = "KeyboardServices"

        /// Controls which items are enabled in the open panel.
        func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
            // Enable selection only for the target directory itself.
            url.hasDirectoryPath && url.lastPathComponent == allowedFolderName
        }

        /// Validates the final URL when the user presses “Open”.
        func panel(_ sender: Any, validate url: URL) throws {
            guard url.lastPathComponent == allowedFolderName else {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSUserCancelledError,
                    userInfo: [NSLocalizedDescriptionKey: "KeyboardServicesという名前のフォルダのみ選択できます。"]
                )
            }
        }
    }

    /// A shared delegate instance that remains alive for the lifetime of the open panel.
    @MainActor private static let keyboardServicesDelegate = KeyboardServicesDirectoryDelegate()

    @MainActor private static func promptUserForTextReplacementDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "システムのユーザ辞書ディレクトリ（KeyboardServices）を選択してください"
        panel.message = "システムのユーザ辞書ディレクトリ（KeyboardServices）を選択してください"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/KeyboardServices")
        panel.delegate = keyboardServicesDelegate

        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }
    #endif

    #if os(macOS)
    /// macOSのユーザ辞書（テキスト置換）のデータベース
    public static var defaultDatabaseURL: URL {
        // サンドボックス内では homeDirectoryForCurrentUser がコンテナを指すため、実際のホームを組み立てる
        URL(fileURLWithPath: "/Users/\(NSUserName())/Library/KeyboardServices/TextReplacements.db", isDirectory: false)
    }
    #endif

    /// データベースの更新日時。SQLiteは変更を`-wal`ファイルに書くことがあるため、両方の新しい方を返す
    public static func sourceModificationDate(databaseURL: URL) -> Date? {
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal", isDirectory: false)
        return [databaseURL, walURL]
            .compactMap { url in
                (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            }
            .max()
    }

    /// 取り込み済みのシステム辞書を読み直すべきか
    ///
    /// 一度も取り込んでいない（または「リセット」した）場合は読み直さない。利用者が選んだときだけ使うため。
    public static func shouldRefresh(value: Config.SystemUserDictionary.Value, currentSourceModificationDate: Date?) -> Bool {
        guard value.lastUpdate != nil, let currentSourceModificationDate else {
            return false
        }
        return value.sourceModificationDate != currentSourceModificationDate
    }

    /// 取り込み済みで、データベースが更新されていれば、画面を出さずに読み直して設定に保存する
    ///
    /// 読めない場合は何もしない（直前に取り込んだ内容を使い続ける）。読み直したら`true`
    @discardableResult
    public static func refreshIfNeeded(databaseURL: URL) -> Bool {
        let item = Config.SystemUserDictionary()
        guard let value = try? CompiledUserDictionaryStore.strictValue(of: item) else {
            return false
        }
        let modificationDate = Self.sourceModificationDate(databaseURL: databaseURL)
        guard Self.shouldRefresh(value: value, currentSourceModificationDate: modificationDate) else {
            return false
        }
        do {
            let entries = try Self.readEntries(databaseURL: databaseURL)
            let newValue = Config.SystemUserDictionary.Value(
                lastUpdate: Date(),
                items: entries.map { .init(word: $0.phrase, reading: $0.shortcut) },
                sourceModificationDate: modificationDate
            )
            // 設定画面の「リセット」・読み込みはメインスレッドで動く。再確認と保存を同じメインスレッド上で
            // 間を空けずに行い、読み取り中にそれらが行われていたら、その操作を優先して結果を捨てる
            return Self.onMainThread {
                guard let current = try? CompiledUserDictionaryStore.strictValue(of: item),
                      Self.isSameImport(value, current) else {
                    return false
                }
                item.value = newValue
                return true
            }
        } catch {
            print("Failed to refresh system user dictionary: \(error)")
            return false
        }
    }

    /// メインスレッドで同期的に実行する（すでにメインスレッドならそのまま）
    private static func onMainThread<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(body)
        }
    }

    /// 同じ取り込み結果のままか（「リセット」や手動の読み込みで変わっていないか）
    static func isSameImport(_ lhs: Config.SystemUserDictionary.Value, _ rhs: Config.SystemUserDictionary.Value) -> Bool {
        lhs.lastUpdate == rhs.lastUpdate && lhs.sourceModificationDate == rhs.sourceModificationDate
    }

    /// SQLiteの結果コード（Linuxでは SQLite3 を読み込まないため値で持つ）
    static let sqliteRow: Int32 = 100
    static let sqliteDone: Int32 = 101

    /// 行を最後まで読み切ったときだけ結果を返す。途中で失敗したら、読みかけの結果は使わずに投げる
    static func collectRows(step: () -> Int32, readRow: () -> Entry?) throws(FetchError) -> [Entry] {
        var entries: [Entry] = []
        var status = step()
        while status == Self.sqliteRow {
            if let entry = readRow() {
                entries.append(entry)
            }
            status = step()
        }
        guard status == Self.sqliteDone else {
            throw .failedToReadRows(status: status)
        }
        return entries
    }

    /// データベースから読む。権限が無い場合も画面は出さずに失敗する
    public static func readEntries(databaseURL: URL) throws(FetchError) -> [Entry] {
        #if !os(macOS)
        throw .unsupportedOperatingSystem
        #else
        let dbPath = databaseURL.path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw .fileNotExist(dbPath)
        }
        guard FileManager.default.isReadableFile(atPath: dbPath) else {
            throw .fileNotReadable(dbPath)
        }

        var db: OpaquePointer?
        let openStatus = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil)
        guard openStatus == SQLITE_OK else {
            sqlite3_close(db)
            throw .failedToOpenDatabase(status: openStatus)
        }
        defer {
            sqlite3_close(db)
        }

        let query = "SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY"
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK else {
            throw .failedToPrepareStatement(status: prepareStatus)
        }
        defer {
            sqlite3_finalize(statement)
        }

        return try Self.collectRows(step: { sqlite3_step(statement) }, readRow: {
            guard let shortcutC = sqlite3_column_text(statement, 0),
                  let phraseC = sqlite3_column_text(statement, 1) else {
                return nil
            }
            return Entry(shortcut: String(cString: shortcutC), phrase: String(cString: phraseC))
        })
        #endif
    }

    @MainActor public static func fetchEntries() throws(FetchError) -> [Entry] {
        #if !os(macOS)
        throw .unsupportedOperatingSystem
        #else
        let databaseURL = Self.defaultDatabaseURL
        let dbPath = databaseURL.path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw .fileNotExist(dbPath)
        }
        if FileManager.default.isReadableFile(atPath: dbPath) {
            return try Self.readEntries(databaseURL: databaseURL)
        }
        // 読めない場合は、利用者にフォルダを選んでもらってから読む
        #if canImport(AppKit)
        guard let authorizedURL = Self.promptUserForTextReplacementDirectory(), authorizedURL.startAccessingSecurityScopedResource() else {
            throw FetchError.fileNotReadable(dbPath)
        }
        defer {
            authorizedURL.stopAccessingSecurityScopedResource()
        }
        return try Self.readEntries(databaseURL: databaseURL)
        #else
        throw FetchError.fileNotReadable(dbPath)
        #endif
        #endif
    }
}
