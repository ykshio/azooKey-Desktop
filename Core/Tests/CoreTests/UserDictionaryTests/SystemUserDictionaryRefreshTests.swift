@testable import Core
import Foundation
#if os(macOS)
import SQLite3
#endif
import Testing

@Test func systemDictionaryIsNotRefreshedUntilImportedOnce() {
    let value = Config.SystemUserDictionary.Value(items: [])
    #expect(!SystemUserDictionaryHelper.shouldRefresh(value: value, currentSourceModificationDate: Date()))
}

@Test func systemDictionaryIsRefreshedWhenDatabaseChanged() {
    let old = Date(timeIntervalSince1970: 100)
    let new = Date(timeIntervalSince1970: 200)
    let value = Config.SystemUserDictionary.Value(lastUpdate: old, items: [], sourceModificationDate: old)
    #expect(SystemUserDictionaryHelper.shouldRefresh(value: value, currentSourceModificationDate: new))
    #expect(!SystemUserDictionaryHelper.shouldRefresh(value: value, currentSourceModificationDate: old))
    // データベースが見つからない場合は読み直さない
    #expect(!SystemUserDictionaryHelper.shouldRefresh(value: value, currentSourceModificationDate: nil))
    // 旧データ（更新日時を持たない）は一度読み直す
    let legacy = Config.SystemUserDictionary.Value(lastUpdate: old, items: [])
    #expect(SystemUserDictionaryHelper.shouldRefresh(value: legacy, currentSourceModificationDate: old))
}

@Test func legacySystemDictionaryValueDecodes() throws {
    let json = #"{"lastUpdate":100,"items":[]}"#
    let value = try JSONDecoder().decode(Config.SystemUserDictionary.Value.self, from: Data(json.utf8))
    #expect(value.lastUpdate == Date(timeIntervalSinceReferenceDate: 100))
    #expect(value.sourceModificationDate == nil)
}

@Test func sourceModificationDateUsesNewerOfDatabaseAndWAL() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SystemUserDictionaryRefreshTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let databaseURL = directoryURL.appendingPathComponent("TextReplacements.db")
    #expect(SystemUserDictionaryHelper.sourceModificationDate(databaseURL: databaseURL) == nil)

    try Data().write(to: databaseURL)
    let databaseDate = Date(timeIntervalSince1970: 1_000)
    try FileManager.default.setAttributes([.modificationDate: databaseDate], ofItemAtPath: databaseURL.path)
    #expect(SystemUserDictionaryHelper.sourceModificationDate(databaseURL: databaseURL) == databaseDate)

    let walURL = directoryURL.appendingPathComponent("TextReplacements.db-wal")
    try Data().write(to: walURL)
    let walDate = Date(timeIntervalSince1970: 2_000)
    try FileManager.default.setAttributes([.modificationDate: walDate], ofItemAtPath: walURL.path)
    #expect(SystemUserDictionaryHelper.sourceModificationDate(databaseURL: databaseURL) == walDate)
}

#if os(macOS)
@Test func readEntriesReadsTextReplacementDatabase() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SystemUserDictionaryRefreshTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let databaseURL = directoryURL.appendingPathComponent("TextReplacements.db")

    var db: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &db) == SQLITE_OK)
    let sql = """
    CREATE TABLE ZTEXTREPLACEMENTENTRY (ZSHORTCUT TEXT, ZPHRASE TEXT);
    INSERT INTO ZTEXTREPLACEMENTENTRY VALUES ('ぷりんすくー', 'こんにちは');
    """
    #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db)

    let entries = try SystemUserDictionaryHelper.readEntries(databaseURL: databaseURL)
    #expect(entries.count == 1)
    #expect(entries.first?.shortcut == "ぷりんすくー")
    #expect(entries.first?.phrase == "こんにちは")
}
#endif

@Test func readEntriesFailsWithoutPromptWhenDatabaseIsMissing() {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).db")
    #if os(macOS)
    #expect(throws: SystemUserDictionaryHelper.FetchError.fileNotExist(databaseURL.path)) {
        _ = try SystemUserDictionaryHelper.readEntries(databaseURL: databaseURL)
    }
    #else
    #expect(throws: SystemUserDictionaryHelper.FetchError.unsupportedOperatingSystem) {
        _ = try SystemUserDictionaryHelper.readEntries(databaseURL: databaseURL)
    }
    #endif
}

@Test func collectRowsReturnsAllRowsWhenFinished() throws {
    var statuses: [Int32] = [100, 100, 101] // ROW, ROW, DONE
    let entries = try SystemUserDictionaryHelper.collectRows(step: { statuses.removeFirst() }, readRow: {
        .init(shortcut: "よみ", phrase: "単語")
    })
    #expect(entries.count == 2)
}

@Test func collectRowsDiscardsPartialResultOnError() {
    var statuses: [Int32] = [100, 5] // ROW, BUSY
    #expect(throws: SystemUserDictionaryHelper.FetchError.failedToReadRows(status: 5)) {
        _ = try SystemUserDictionaryHelper.collectRows(step: { statuses.removeFirst() }, readRow: {
            .init(shortcut: "よみ", phrase: "単語")
        })
    }
}

@Test func refreshResultIsDiscardedWhenImportChangedMeanwhile() {
    let old = Date(timeIntervalSince1970: 100)
    let imported = Config.SystemUserDictionary.Value(lastUpdate: old, items: [], sourceModificationDate: old)
    #expect(SystemUserDictionaryHelper.isSameImport(imported, imported))
    // 「リセット」された
    #expect(!SystemUserDictionaryHelper.isSameImport(imported, .init(items: [])))
    // 手動で読み込み直された
    let reimported = Config.SystemUserDictionary.Value(lastUpdate: Date(timeIntervalSince1970: 200), items: [], sourceModificationDate: old)
    #expect(!SystemUserDictionaryHelper.isSameImport(imported, reimported))
}
