@testable import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

// MARK: - 判定

@Test func reloaderDecidesRebuildWhenSourceChanged() {
    let date = Date(timeIntervalSince1970: 100)
    #expect(UserDictionaryReloader.decide(exportedFingerprint: "a", currentFingerprint: "b", loadedModificationDate: date, compiledModificationDate: date) == .rebuild)
    #expect(UserDictionaryReloader.decide(exportedFingerprint: nil, currentFingerprint: "b", loadedModificationDate: nil, compiledModificationDate: date) == .rebuild)
}

@Test func reloaderDecidesRebuildWhenCompiledDictionaryIsMissing() {
    #expect(UserDictionaryReloader.decide(exportedFingerprint: "a", currentFingerprint: "a", loadedModificationDate: nil, compiledModificationDate: nil) == .rebuild)
}

@Test func reloaderDecidesReloadWhenOnlyCompiledDictionaryChanged() {
    let old = Date(timeIntervalSince1970: 100)
    let new = Date(timeIntervalSince1970: 200)
    #expect(UserDictionaryReloader.decide(exportedFingerprint: "a", currentFingerprint: "a", loadedModificationDate: old, compiledModificationDate: new) == .reload)
    // 起動直後（未読込）
    #expect(UserDictionaryReloader.decide(exportedFingerprint: "a", currentFingerprint: "a", loadedModificationDate: nil, compiledModificationDate: new) == .reload)
}

@Test func reloaderDecidesNothingWhenUnchanged() {
    let date = Date(timeIntervalSince1970: 100)
    #expect(UserDictionaryReloader.decide(exportedFingerprint: "a", currentFingerprint: "a", loadedModificationDate: date, compiledModificationDate: date) == .none)
}

@Test func statusReportsFailureOnlyWhenNewerThanLastLoad() {
    let old = Date(timeIntervalSince1970: 100)
    let new = Date(timeIntervalSince1970: 200)
    #expect(!UserDictionaryReloader.Status().isUsingPreviousDictionaryAfterFailure)
    #expect(UserDictionaryReloader.Status(lastLoadedAt: old, lastFailedAt: new).isUsingPreviousDictionaryAfterFailure)
    #expect(!UserDictionaryReloader.Status(lastLoadedAt: new, lastFailedAt: old).isUsingPreviousDictionaryAfterFailure)
    #expect(UserDictionaryReloader.Status(lastFailedAt: old).isUsingPreviousDictionaryAfterFailure)
}

// MARK: - 指紋・ディレクトリの状態

@Test func fingerprintChangesWithContent() {
    let a = [CompiledUserDictionaryStore.entry(word: "単語", reading: "たんご")]
    let b = [CompiledUserDictionaryStore.entry(word: "単語", reading: "たんごう")]
    #expect(CompiledUserDictionaryStore.fingerprint(of: a) == CompiledUserDictionaryStore.fingerprint(of: a))
    #expect(CompiledUserDictionaryStore.fingerprint(of: a) != CompiledUserDictionaryStore.fingerprint(of: b))
    #expect(CompiledUserDictionaryStore.fingerprint(of: a) != CompiledUserDictionaryStore.fingerprint(of: []))
}

@Test func partiallyMissingCompiledDictionaryIsNotUsable() throws {
    let directoryURL = try makeReloaderTestDirectory()
    #expect(CompiledUserDictionaryStore.isUsableCompiledDictionary(at: directoryURL)) // 項目なし
    try Data().write(to: directoryURL.appendingPathComponent("user.louds"))
    #expect(!CompiledUserDictionaryStore.isUsableCompiledDictionary(at: directoryURL))
    try Data().write(to: directoryURL.appendingPathComponent("user.loudschars2"))
    try Data().write(to: directoryURL.appendingPathComponent("user0.loudstxt3"))
    #expect(CompiledUserDictionaryStore.isUsableCompiledDictionary(at: directoryURL))
    #expect(!CompiledUserDictionaryStore.isUsableCompiledDictionary(at: directoryURL.appendingPathComponent("missing")))
}

@Test func strictValueThrowsForCorruptedData() throws {
    struct Probe: CustomCodableConfigItem {
        struct Value: Codable { var items: [String] }
        static let `default` = Value(items: ["default"])
        static let key = "dev.ensan.inputmethod.azooKeyMac.test.strictValueProbe.\(UUID().uuidString)"
    }
    defer { Config.set(nil, forKey: Probe.key) }
    #expect(try CompiledUserDictionaryStore.strictValue(of: Probe()).items == ["default"])
    Config.set(Data("not json".utf8), forKey: Probe.key)
    #expect(throws: CompiledUserDictionaryStore.SourceError.corruptedSource(key: Probe.key)) {
        _ = try CompiledUserDictionaryStore.strictValue(of: Probe())
    }
}

// MARK: - 再読込の流れ

/// テストは逐次実行され、各状態へのアクセスも`await`で直列化されるため、ロックは省略する
private final class ReloaderHarness: @unchecked Sendable {
    var entries: [DicdataElement] = [CompiledUserDictionaryStore.entry(word: "単語", reading: "たんご")]
    var sourceError: (any Error)?
    var buildError: (any Error)?
    var buildCount = 0
    var reloadCount = 0
    var status = UserDictionaryReloader.Status()
    let directoryURL: URL

    init() throws {
        self.directoryURL = try makeReloaderTestDirectory().appendingPathComponent("UserDictionary", isDirectory: true)
    }

    @MainActor
    func makeReloader() -> UserDictionaryReloader {
        UserDictionaryReloader(
            directoryURL: self.directoryURL,
            entriesProvider: { try self.provide() },
            builder: { _, directoryURL in try self.build(directoryURL) },
            reload: { _ in self.reloadCount += 1 },
            loadStatus: { self.status },
            saveStatus: { self.status = $0 }
        )
    }

    func provide() throws -> [DicdataElement] {
        if let sourceError {
            throw sourceError
        }
        return self.entries
    }

    func build(_ directoryURL: URL) throws {
        if let buildError {
            throw buildError
        }
        self.buildCount += 1
        // 本物と同様に、作り直したディレクトリで差し替える
        try? FileManager.default.removeItem(at: directoryURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        for name in CompiledUserDictionaryStore.compiledFileNames {
            try Data("\(self.buildCount)".utf8).write(to: directoryURL.appendingPathComponent(name))
        }
    }
}

private struct TestError: Error {}

@MainActor
@Test func reloaderBuildsOnFirstRunAndSkipsWhenUnchanged() async throws {
    let harness = try ReloaderHarness()
    let reloader = harness.makeReloader()

    #expect(await reloader.reloadIfNeeded().value)
    #expect(harness.buildCount == 1)
    #expect(harness.reloadCount == 1)
    #expect(harness.status.lastLoadedAt != nil)
    #expect(harness.status.exportedFingerprint == CompiledUserDictionaryStore.fingerprint(of: harness.entries))

    #expect(await reloader.reloadIfNeeded().value)
    #expect(harness.buildCount == 1)
    #expect(harness.reloadCount == 1)
}

@MainActor
@Test func reloaderRebuildsWhenSourceChanges() async throws {
    let harness = try ReloaderHarness()
    let reloader = harness.makeReloader()
    _ = await reloader.reloadIfNeeded().value

    harness.entries.append(CompiledUserDictionaryStore.entry(word: "追加", reading: "ついか"))
    #expect(await reloader.reloadIfNeeded().value)
    #expect(harness.buildCount == 2)
    #expect(harness.reloadCount == 2)
}

@MainActor
@Test func reloaderOnlyReloadsWhenAnotherProcessRebuilt() async throws {
    let harness = try ReloaderHarness()
    _ = await harness.makeReloader().reloadIfNeeded().value
    // 新しいプロセスの起動を模す（読込日時はメモリ上にしかない）
    let reloader = harness.makeReloader()
    #expect(await reloader.reloadIfNeeded().value)
    #expect(harness.buildCount == 1)
    #expect(harness.reloadCount == 2)
}

@MainActor
@Test func reloaderKeepsPreviousDictionaryWhenSourceIsCorrupted() async throws {
    let harness = try ReloaderHarness()
    let reloader = harness.makeReloader()
    _ = await reloader.reloadIfNeeded().value
    let loadedAt = harness.status.lastLoadedAt

    harness.sourceError = TestError()
    #expect(await reloader.reloadIfNeeded(forceRebuild: true).value == false)
    #expect(harness.buildCount == 1)
    #expect(harness.reloadCount == 1)
    #expect(harness.status.lastLoadedAt == loadedAt)
    #expect(harness.status.isUsingPreviousDictionaryAfterFailure)
    #expect(CompiledUserDictionaryStore.isUsableCompiledDictionary(at: harness.directoryURL))
}

@MainActor
@Test func reloaderKeepsPreviousDictionaryWhenBuildFails() async throws {
    let harness = try ReloaderHarness()
    let reloader = harness.makeReloader()
    _ = await reloader.reloadIfNeeded().value
    let fingerprint = harness.status.exportedFingerprint

    harness.entries.append(CompiledUserDictionaryStore.entry(word: "追加", reading: "ついか"))
    harness.buildError = TestError()
    #expect(await reloader.reloadIfNeeded().value == false)
    #expect(harness.reloadCount == 1)
    #expect(harness.status.exportedFingerprint == fingerprint)
    #expect(harness.status.isUsingPreviousDictionaryAfterFailure)

    // 直ったら次の機会に反映される
    harness.buildError = nil
    #expect(await reloader.reloadIfNeeded().value)
    #expect(harness.reloadCount == 2)
    #expect(!harness.status.isUsingPreviousDictionaryAfterFailure)
}

@MainActor
@Test func reloaderDoesNotLoadPartiallyMissingDictionary() async throws {
    let harness = try ReloaderHarness()
    let reloader = harness.makeReloader()
    _ = await reloader.reloadIfNeeded().value
    try FileManager.default.removeItem(at: harness.directoryURL.appendingPathComponent("user.louds"))
    // ファイルの削除でディレクトリの更新日時が変わり、読込対象になるが、欠けているので読み込まない
    #expect(await reloader.reloadIfNeeded().value == false)
    #expect(harness.reloadCount == 1)
}

private func makeReloaderTestDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("UserDictionaryReloaderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}
