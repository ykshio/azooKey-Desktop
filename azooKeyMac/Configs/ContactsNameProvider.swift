import Contacts
import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// 連絡先の氏名とフリガナを読み、ユーザ辞書の項目として渡す
///
/// プライバシーのため、次を守る。
/// - 取得するのは姓・名とそのフリガナだけ
/// - 端末外へ送らず、ログにも出さない
/// - ここではメモリ上にだけ保持する（永続化されるのはコンパイル済みのユーザ辞書の表記と読みのみ）
final class ContactsNameProvider: @unchecked Sendable {
    private let store = CNContactStore()
    private let lock = NSLock()
    /// 取得済みの登録項目。連絡先が変わったら捨て、次の辞書の再読込時に取り直す
    private var cachedEntries: [ContactNameEntries.Entry]?
    private var observer: (any NSObjectProtocol)?

    init() {
        self.observer = NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.invalidate()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    static var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    static var isAuthorized: Bool {
        Self.authorizationStatus == .authorized
    }

    /// 連絡先へのアクセスを求める。許可されたら`true`
    static func requestAccess() async -> Bool {
        do {
            return try await CNContactStore().requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    func invalidate() {
        self.lock.withLock {
            self.cachedEntries = nil
        }
    }

    /// 設定がオンで、かつアクセスが許可されているときだけ項目を返す
    ///
    /// 取得に失敗した場合は投げる（空として扱うと、辞書から連絡先が消えてしまうため）
    func dictionaryEntries() throws -> [DicdataElement] {
        guard Config.ContactsNameConversion().value, Self.isAuthorized else {
            self.invalidate()
            return []
        }
        let entries = try self.lock.withLock { self.cachedEntries } ?? self.fetchEntries()
        return entries.map {
            CompiledUserDictionaryStore.entry(word: $0.word, reading: $0.reading)
        }
    }

    private func fetchEntries() throws -> [ContactNameEntries.Entry] {
        let keys = [
            CNContactFamilyNameKey,
            CNContactGivenNameKey,
            CNContactPhoneticFamilyNameKey,
            CNContactPhoneticGivenNameKey
        ] as [any CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true

        var names: [ContactNameEntries.Name] = []
        try self.store.enumerateContacts(with: request) { contact, _ in
            names.append(
                .init(
                    familyName: contact.familyName,
                    givenName: contact.givenName,
                    phoneticFamilyName: contact.phoneticFamilyName,
                    phoneticGivenName: contact.phoneticGivenName
                )
            )
        }
        let entries = ContactNameEntries.entries(from: names)
        self.lock.withLock {
            self.cachedEntries = entries
        }
        return entries
    }
}
