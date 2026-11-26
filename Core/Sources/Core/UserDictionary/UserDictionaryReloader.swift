import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// 入力セッション開始時などに呼び出し、ユーザ辞書の元データやコンパイル済み辞書が変わっていれば再構築・再読込する。
///
/// - 元データ（設定に保存された辞書項目など）の指紋が前回の書き出し時と違えば、再コンパイルしてから読み込む
/// - コンパイル済み辞書の更新日時が前回の読み込み時と違えば、読み込み直す
/// - 元データが壊れている・書き出しに失敗した場合は、直前の有効な辞書をそのまま使い続ける
@MainActor
public final class UserDictionaryReloader {
    public typealias EntriesProvider = @Sendable () throws -> [DicdataElement]
    public typealias Builder = @Sendable (_ entries: [DicdataElement], _ directoryURL: URL) throws -> Void

    public struct Status: Codable, Sendable, Equatable {
        public init(lastLoadedAt: Date? = nil, lastFailedAt: Date? = nil, exportedFingerprint: String? = nil) {
            self.lastLoadedAt = lastLoadedAt
            self.lastFailedAt = lastFailedAt
            self.exportedFingerprint = exportedFingerprint
        }

        /// 最後に辞書を読み込んだ日時
        public var lastLoadedAt: Date?
        /// 最後に読み込みに失敗した日時
        public var lastFailedAt: Date?
        /// 最後に書き出したときの元データの指紋
        public var exportedFingerprint: String?

        /// 最後の試行が失敗し、直前の辞書を使い続けているか
        public var isUsingPreviousDictionaryAfterFailure: Bool {
            guard let lastFailedAt else {
                return false
            }
            guard let lastLoadedAt else {
                return true
            }
            return lastFailedAt > lastLoadedAt
        }
    }

    public enum Action: Sendable, Equatable {
        case none
        case reload
        case rebuild
    }

    /// 何をすべきかを判定する
    nonisolated public static func decide(
        exportedFingerprint: String?,
        currentFingerprint: String,
        loadedModificationDate: Date?,
        compiledModificationDate: Date?
    ) -> Action {
        if exportedFingerprint != currentFingerprint || compiledModificationDate == nil {
            return .rebuild
        }
        if compiledModificationDate != loadedModificationDate {
            return .reload
        }
        return .none
    }

    private let directoryURL: URL
    private let entriesProvider: EntriesProvider
    private let builder: Builder
    private let reload: @MainActor (URL) -> Void
    private let loadStatus: @MainActor () -> Status
    private let saveStatus: @MainActor (Status) -> Void
    private let now: @Sendable () -> Date
    /// このプロセスで最後に読み込んだコンパイル済み辞書の更新日時
    private var loadedModificationDate: Date?
    private var lastTask: Task<Bool, Never>?

    public init(
        directoryURL: URL,
        entriesProvider: @escaping EntriesProvider,
        builder: @escaping Builder,
        reload: @escaping @MainActor (URL) -> Void,
        loadStatus: (@MainActor () -> Status)? = nil,
        saveStatus: (@MainActor (Status) -> Void)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directoryURL = directoryURL
        self.entriesProvider = entriesProvider
        self.builder = builder
        self.reload = reload
        self.loadStatus = loadStatus ?? { Config.UserDictionaryLoadStatus().value }
        self.saveStatus = saveStatus ?? { Config.UserDictionaryLoadStatus().value = $0 }
        self.now = now
    }

    /// 必要なら再構築・再読込する。結果として有効な辞書が読み込まれていれば`true`を返す
    ///
    /// - parameter forceRebuild: 元データの変化を問わず再構築する（辞書の編集直後など）
    @discardableResult
    public func reloadIfNeeded(forceRebuild: Bool = false) -> Task<Bool, Never> {
        let previousTask = self.lastTask
        let task = Task { @MainActor in
            // 同時に再構築が走らないよう、前の処理を待ってから始める
            _ = await previousTask?.value
            return await self.performReload(forceRebuild: forceRebuild)
        }
        self.lastTask = task
        return task
    }

    private struct Outcome: Sendable {
        var action: Action
        var fingerprint: String
        var modificationDate: Date?
    }

    private func performReload(forceRebuild: Bool) async -> Bool {
        let directoryURL = self.directoryURL
        let entriesProvider = self.entriesProvider
        let builder = self.builder
        let exportedFingerprint = self.loadStatus().exportedFingerprint
        let loadedModificationDate = self.loadedModificationDate

        let result: Result<Outcome, any Error> = await Task.detached(priority: .utility) {
            do {
                let entries = try entriesProvider()
                let fingerprint = CompiledUserDictionaryStore.fingerprint(of: entries)
                var action = Self.decide(
                    exportedFingerprint: exportedFingerprint,
                    currentFingerprint: fingerprint,
                    loadedModificationDate: loadedModificationDate,
                    compiledModificationDate: CompiledUserDictionaryStore.modificationDate(at: directoryURL)
                )
                if forceRebuild {
                    action = .rebuild
                }
                if action == .rebuild {
                    try builder(entries, directoryURL)
                }
                return .success(Outcome(
                    action: action,
                    fingerprint: fingerprint,
                    modificationDate: CompiledUserDictionaryStore.modificationDate(at: directoryURL)
                ))
            } catch {
                return .failure(error)
            }
        }.value

        var status = self.loadStatus()
        switch result {
        case .success(let value):
            if value.action == .rebuild {
                status.exportedFingerprint = value.fingerprint
            }
            if value.action != .none {
                // 壊れた（一部のファイルが欠けた）辞書は読み込まず、直前の辞書を使い続ける
                guard CompiledUserDictionaryStore.isUsableCompiledDictionary(at: directoryURL) else {
                    status.lastFailedAt = self.now()
                    self.saveStatus(status)
                    return false
                }
                self.reload(directoryURL)
                self.loadedModificationDate = value.modificationDate
                status.lastLoadedAt = self.now()
                self.saveStatus(status)
            }
            return true
        case .failure(let error):
            print("Failed to reload user dictionary: \(error)")
            status.lastFailedAt = self.now()
            self.saveStatus(status)
            return false
        }
    }
}
