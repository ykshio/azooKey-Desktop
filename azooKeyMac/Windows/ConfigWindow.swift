import Cocoa
import Core
import SwiftUI

struct ConfigWindow: View {
    @ConfigState private var liveConversion = Config.LiveConversion()
    @ConfigState private var inputStyle = Config.InputStyle()
    @ConfigState private var typeBackSlash = Config.TypeBackSlash()
    @ConfigState private var punctuationStyle = Config.PunctuationStyle()
    @ConfigState private var typeHalfSpace = Config.TypeHalfSpace()
    @ConfigState private var optionDirectFullWidthInput = Config.OptionDirectFullWidthInput()
    @ConfigState private var zenzaiProfile = Config.ZenzaiProfile()
    @ConfigState private var zenzaiPersonalizationLevel = Config.ZenzaiPersonalizationLevel()
    @ConfigState private var openAiApiKey = Config.OpenAiApiKey()
    @ConfigState private var openAiModelName = Config.OpenAiModelName()
    @ConfigState private var openAiReasoningEffort = Config.OpenAiReasoningEffort()
    @ConfigState private var openAiApiEndpoint = Config.OpenAiApiEndpoint()
    @ConfigState private var learning = Config.Learning()
    @ConfigState private var inferenceLimit = Config.ZenzaiInferenceLimit()
    @ConfigState private var debugWindow = Config.DebugWindow()
    @ConfigState private var debugPredictiveTyping = Config.DebugPredictiveTyping()
    @ConfigState private var debugTypoCorrection = Config.DebugTypoCorrection()
    @ConfigState private var userDictionary = Config.UserDictionary()
    @ConfigState private var systemUserDictionary = Config.SystemUserDictionary()
    @ConfigState private var userDictionaryLoadStatus = Config.UserDictionaryLoadStatus()
    @ConfigState private var contactsNameConversion = Config.ContactsNameConversion()
    @ConfigState private var keyboardLayout = Config.KeyboardLayout()
    @ConfigState private var aiBackend = Config.AIBackendPreference()
    @ConfigState private var transformShortcut = Config.TransformShortcut()
    @ConfigState private var candidateFontSize = Config.CandidateFontSize()
    @ConfigState private var candidateFontName = Config.CandidateFontName()
    /// 日本語を表示できるフォントのファミリー名（設定画面を開いたときに集める）
    @State private var japaneseFontFamilies: [String] = []

    @State private var selectedTab: Tab = .basic
    @State private var zenzaiProfileHelpPopover = false
    @State private var zenzaiInferenceLimitHelpPopover = false
    @State private var openAiApiKeyPopover = false
    @State private var connectionTestInProgress = false
    @State private var showingRomajiTableEditor = false
    @State private var connectionTestResult: String?
    @State private var systemUserDictionaryUpdateMessage: SystemUserDictionaryUpdateMessage?
    @State private var contactsAccessDenied = false
    @State private var contactsAccessRequestInProgress = false
    @State private var showingLearningResetConfirmation = false
    @State private var learningResetMessage: LearningResetMessage?
    @State private var foundationModelsAvailability: FoundationModelsAvailability?
    @State private var availabilityCheckDone = false
    @State private var debugTypoCorrectionState: DebugTypoCorrectionState = .notDownloaded
    @State private var debugTypoCorrectionDownloadInProgress = false
    @State private var debugTypoCorrectionErrorMessage: String?

    private enum Tab: String, CaseIterable, Hashable {
        case basic = "基本"
        case customize = "カスタマイズ"
        case advanced = "詳細設定"

        var icon: String {
            switch self {
            case .basic: return "star"
            case .customize: return "slider.horizontal.3"
            case .advanced: return "gearshape.2"
            }
        }
    }

    private enum LearningResetMessage {
        case success
        case error(String)
    }

    private enum SystemUserDictionaryUpdateMessage {
        case error(any Error)
    }

    private var azooKeyApplicationSupportDirectoryURL: URL {
        AppGroup.applicationSupportDirectoryURL()
    }

    private var legacyAzooKeyApplicationSupportDirectoryURL: URL {
        if #available(macOS 13, *) {
            URL.applicationSupportDirectory
                .appending(path: "azooKey", directoryHint: .isDirectory)
        } else {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("azooKey", isDirectory: true)
        }
    }

    private var debugTypoCorrectionModelDirectoryURL: URL {
        DebugTypoCorrectionWeights.modelDirectoryURL(
            azooKeyApplicationSupportDirectoryURL: self.azooKeyApplicationSupportDirectoryURL
        )
    }

    private var legacyDebugTypoCorrectionModelDirectoryURL: URL {
        DebugTypoCorrectionWeights.modelDirectoryURL(
            azooKeyApplicationSupportDirectoryURL: self.legacyAzooKeyApplicationSupportDirectoryURL
        )
    }

    private var debugTypoCorrectionStatusText: String {
        if self.debugTypoCorrectionDownloadInProgress {
            return "ダウンロード中..."
        }
        switch self.debugTypoCorrectionState {
        case .downloaded:
            return "重み: ダウンロード済み"
        case .failed:
            return "重み: ダウンロード失敗"
        case .notDownloaded:
            return "重み: ダウンロード未実施"
        }
    }

    @MainActor
    private func refreshDebugTypoCorrectionState() async {
        let modelDirectoryURL = self.debugTypoCorrectionModelDirectoryURL
        let legacyModelDirectoryURL = self.legacyDebugTypoCorrectionModelDirectoryURL
        let state = await Task.detached(priority: .utility) { () -> DebugTypoCorrectionState in
            Self.migrateLegacyDebugTypoCorrectionWeightsIfNeeded(
                from: legacyModelDirectoryURL,
                to: modelDirectoryURL
            )
            return DebugTypoCorrectionWeights.state(modelDirectoryURL: modelDirectoryURL)
        }.value
        self.debugTypoCorrectionState = state
        if state != .failed {
            self.debugTypoCorrectionErrorMessage = nil
        }
    }

    @MainActor
    private func downloadDebugTypoCorrectionWeights() {
        guard !self.debugTypoCorrectionDownloadInProgress else {
            return
        }
        self.debugTypoCorrectionDownloadInProgress = true
        self.debugTypoCorrectionErrorMessage = nil

        let modelDirectoryURL = self.debugTypoCorrectionModelDirectoryURL
        Task {
            do {
                try await DebugTypoCorrectionWeights.downloadWeights(modelDirectoryURL: modelDirectoryURL)
                let state = await Task.detached(priority: .utility) {
                    DebugTypoCorrectionWeights.state(modelDirectoryURL: modelDirectoryURL)
                }.value
                await MainActor.run {
                    self.debugTypoCorrectionState = state
                    self.debugTypoCorrectionErrorMessage = state == .failed ? "ダウンロード後の整合性チェックに失敗しました" : nil
                    self.debugTypoCorrectionDownloadInProgress = false
                }
            } catch {
                await MainActor.run {
                    self.debugTypoCorrectionState = .failed
                    self.debugTypoCorrectionErrorMessage = error.localizedDescription
                    self.debugTypoCorrectionDownloadInProgress = false
                }
            }
        }
    }

    nonisolated private static func migrateLegacyDebugTypoCorrectionWeightsIfNeeded(from sourceURL: URL, to targetURL: URL) {
        guard sourceURL.standardizedFileURL != targetURL.standardizedFileURL else {
            return
        }
        guard !DebugTypoCorrectionWeights.hasRequiredWeightFiles(modelDirectoryURL: targetURL),
              DebugTypoCorrectionWeights.hasRequiredWeightFiles(modelDirectoryURL: sourceURL) else {
            return
        }
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        } catch {
            // The status check below will surface a notDownloaded/failed state.
        }
    }

    /// 日本語（ひらがな・漢字）を表示できるフォントのファミリー名
    private static func japaneseFontFamilies() -> [String] {
        let manager = NSFontManager.shared
        let required = CharacterSet(charactersIn: "あ漢")
        return manager.availableFontFamilies.filter { family in
            guard !family.hasPrefix("."),
                  let font = manager.font(withFamily: family, traits: [], weight: 5, size: 12) else {
                return false
            }
            return font.coveredCharacterSet.isSuperset(of: required)
        }
    }

    /// システムのユーザ辞書の利用を切り替える。オンにするとその場で読み込み、以降は変更を自動で反映する
    private func setSystemUserDictionaryEnabled(_ enabled: Bool) {
        guard enabled else {
            self.systemUserDictionary.value.lastUpdate = nil
            self.systemUserDictionary.value.items = []
            self.systemUserDictionaryUpdateMessage = nil
            self.exportUserDictionary()
            return
        }
        do {
            let entries = try SystemUserDictionaryHelper.fetchEntries()
            self.systemUserDictionary.value = .init(
                lastUpdate: .now,
                items: entries.map {
                    .init(word: $0.phrase, reading: $0.shortcut)
                },
                sourceModificationDate: SystemUserDictionaryHelper.sourceModificationDate(
                    databaseURL: SystemUserDictionaryHelper.defaultDatabaseURL
                )
            )
            self.systemUserDictionaryUpdateMessage = nil
            self.exportUserDictionary()
        } catch {
            // 読めなかった場合はオフのまま
            self.systemUserDictionaryUpdateMessage = .error(error)
        }
    }

    private func openAzooKeyDataDirectoryInFinder() {
        do {
            try FileManager.default.createDirectory(
                at: self.azooKeyApplicationSupportDirectoryURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.activateFileViewerSelecting([self.azooKeyApplicationSupportDirectoryURL])
        } catch {
            // no-op
        }
    }

    private func exportUserDictionary() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.exportUserDictionaryAndReloadConverter()
        }
    }

    /// 連絡先の氏名の利用を切り替える。オンにするときに初めてアクセスを求め、拒否されたらオフのままにする
    @MainActor
    private func setContactsNameConversion(_ enabled: Bool) async {
        guard enabled else {
            self.$contactsNameConversion.wrappedValue = false
            self.contactsAccessDenied = false
            self.exportUserDictionary()
            return
        }
        let granted: Bool
        switch ContactsNameProvider.authorizationStatus {
        case .authorized:
            granted = true
        case .notDetermined:
            self.contactsAccessRequestInProgress = true
            granted = await ContactsNameProvider.requestAccess()
            self.contactsAccessRequestInProgress = false
        default:
            granted = false
        }
        guard granted else {
            self.$contactsNameConversion.wrappedValue = false
            self.contactsAccessDenied = true
            return
        }
        self.contactsAccessDenied = false
        self.$contactsNameConversion.wrappedValue = true
        (NSApplication.shared.delegate as? AppDelegate)?.contactsNameProvider.invalidate()
        self.exportUserDictionary()
    }

    private func openContactsPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
    }

    private func getErrorMessage(for error: OpenAIError) -> String {
        switch error {
        case .invalidURL:
            return "エラー: 無効なURL形式です"
        case .noServerResponse:
            return "エラー: サーバーから応答がありません"
        case .invalidResponseStatus(let code, let body):
            return getHTTPErrorMessage(code: code, body: body)
        case .parseError(let message):
            return "エラー: レスポンス解析失敗 - \(message)"
        case .invalidResponseStructure:
            return "エラー: 予期しないレスポンス形式"
        }
    }

    private func getHTTPErrorMessage(code: Int, body: String) -> String {
        switch code {
        case 401:
            return "エラー: APIキーが無効です"
        case 403:
            return "エラー: アクセスが拒否されました"
        case 404:
            return "エラー: エンドポイントが見つかりません"
        case 429:
            return "エラー: レート制限に達しました"
        case 500...599:
            return "エラー: サーバーエラー (コード: \(code))"
        default:
            return "エラー: HTTPステータス \(code)\n詳細: \(body.prefix(100))..."
        }
    }

    func testConnection() async {
        connectionTestInProgress = true
        connectionTestResult = nil

        do {
            let testRequest = OpenAIRequest(
                prompt: "Text before: おはようございます。今日も",
                target: "てんき",
                modelName: openAiModelName.value.isEmpty ? Config.OpenAiModelName.default : openAiModelName.value,
                reasoningEffort: openAiReasoningEffort.value
            )
            _ = try await OpenAIClient.sendRequest(
                testRequest,
                apiKey: openAiApiKey.value,
                apiEndpoint: openAiApiEndpoint.value
            )

            connectionTestResult = "接続成功"
        } catch let error as OpenAIError {
            connectionTestResult = getErrorMessage(for: error)
        } catch {
            connectionTestResult = "エラー: \(error.localizedDescription)"
        }

        connectionTestInProgress = false
    }

    @MainActor
    private func resetLearningData() {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            learningResetMessage = .error("学習データのリセットに失敗しました")
            Task {
                try? await Task.sleep(for: .seconds(30))
                if case .error = learningResetMessage {
                    learningResetMessage = nil
                }
            }
            return
        }

        do {
            try LegacyDataMigration.discardStagedLearning(for: AppGroup.memoryDirectoryURL())
        } catch {
            learningResetMessage = .error(error.localizedDescription)
            return
        }
        appDelegate.kanaKanjiConverter.resetMemory()
        learningResetMessage = .success

        // 10秒後にメッセージを消す
        Task {
            try? await Task.sleep(for: .seconds(10))
            if case .success = learningResetMessage {
                learningResetMessage = nil
            }
        }
    }

    @ViewBuilder
    private func helpButton(helpContent: LocalizedStringKey, isPresented: Binding<Bool>) -> some View {
        if #available(macOS 14, *) {
            Button("ヘルプ", systemImage: "questionmark") {
                isPresented.wrappedValue = true
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .popover(isPresented: isPresented) {
                Text(helpContent).padding()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // カスタムタブバー
            HStack(spacing: 4) {
                ForEach([Tab.basic, Tab.customize, Tab.advanced], id: \.self) { tab in
                    Button(
                        action: {
                            selectedTab = tab
                        },
                        label: {
                            HStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(selectedTab == tab ? Color(nsColor: .controlAccentColor) : Color(nsColor: .secondaryLabelColor))
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: selectedTab == tab ? .medium : .regular))
                                    .foregroundColor(selectedTab == tab ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTab == tab ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        selectedTab == tab ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                                        lineWidth: 0.5
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                    )
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.3))
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // コンテンツエリア（選択されたタブのみ表示）
            Group {
                if selectedTab == .basic {
                    basicTabView
                } else if selectedTab == .customize {
                    customizeTabView
                } else {
                    advancedTabView
                }
            }
        }
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showingRomajiTableEditor) {
            RomajiTableEditorWindow(base: CustomInputTableStore.loadTable()) { exported in
                do {
                    _ = try CustomInputTableStore.save(exported: exported)
                    CustomInputTableStore.registerIfExists()
                } catch {
                    print("Failed to save custom input table: \(error)")
                }
            }
        }
    }

    // MARK: - 基本タブ
    @ViewBuilder
    private var basicTabView: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Picker("いい感じ変換", selection: $aiBackend) {
                        Text("オフ").tag(Config.AIBackendPreference.Value.off)

                        if let availability = foundationModelsAvailability, availability.isAvailable {
                            Text("Foundation Models").tag(Config.AIBackendPreference.Value.foundationModels)
                        }

                        Text("OpenAI API").tag(Config.AIBackendPreference.Value.openAI)
                    }
                    .onAppear {
                        if !availabilityCheckDone {
                            foundationModelsAvailability = FoundationModelsClientCompat.checkAvailability()
                            availabilityCheckDone = true

                            let hasSetAIBackend = UserDefaults.standard.bool(forKey: "hasSetAIBackendManually")
                            if !hasSetAIBackend,
                               aiBackend.value == .off,
                               let availability = foundationModelsAvailability,
                               availability.isAvailable {
                                aiBackend.value = .foundationModels
                                UserDefaults.standard.set(true, forKey: "hasSetAIBackendManually")
                            }

                            if aiBackend.value == .foundationModels,
                               let availability = foundationModelsAvailability,
                               !availability.isAvailable {
                                aiBackend.value = .off
                            }
                        }
                    }
                    .onChange(of: aiBackend.value) { _ in
                        UserDefaults.standard.set(true, forKey: "hasSetAIBackendManually")
                    }
                }

                HStack {
                    Text("ショートカット")
                    Spacer()
                    KeyboardShortcutRecorder(shortcut: $transformShortcut)
                        .frame(width: 160, height: 24)
                }
                .help("クリックして新しいキーを入力します。Deleteでデフォルト（⌃S）に戻り、Escでキャンセルします。")

                if aiBackend.value == .openAI {
                    HStack {
                        SecureField("APIキー", text: $openAiApiKey, prompt: Text("例:sk-xxxxxxxxxxx"))
                        helpButton(
                            helpContent: "OpenAI APIキーはローカルのみで管理され、外部に公開されることはありません。生成の際にAPIを利用するため、課金が発生します。",
                            isPresented: $openAiApiKeyPopover
                        )
                    }
                    TextField("モデル名", text: $openAiModelName, prompt: Text("例: gpt-4o-mini"))
                    Picker("推論の強さ", selection: $openAiReasoningEffort) {
                        Text("モデルの既定値").tag(nil as OpenAIReasoningEffort?)
                        ForEach(OpenAIReasoningEffort.allCases, id: \.self) { effort in
                            Text(effort.rawValue).tag(Optional(effort))
                        }
                    }
                    .help("利用できる値はモデルによって異なります。対応していない場合は「モデルの既定値」を選んでください。")
                    TextField("エンドポイント", text: $openAiApiEndpoint, prompt: Text("例: https://api.openai.com/v1/chat/completions"))
                        .help("例: https://api.openai.com/v1/chat/completions\nGemini: https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")

                    HStack {
                        Button("接続テスト") {
                            Task {
                                await testConnection()
                            }
                        }
                        .disabled(connectionTestInProgress || openAiApiKey.value.isEmpty)

                        if connectionTestInProgress {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }

                    if let result = connectionTestResult {
                        Text(result)
                            .foregroundColor(result.contains("成功") ? .green : .red)
                            .font(.caption)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Label("いい感じ変換", systemImage: "sparkles")
            }

            Section {
                LabeledContent {
                    HStack {
                        Text("\(self.userDictionary.value.items.count)件のアイテム")
                        Button("編集") {
                            (NSApplication.shared.delegate as? AppDelegate)!.openUserDictionaryEditorWindow()
                        }
                    }
                } label: {
                    Text("azooKeyユーザ辞書")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        isOn: Binding(
                            get: { self.systemUserDictionary.value.lastUpdate != nil },
                            set: { self.setSystemUserDictionaryEnabled($0) }
                        )
                    ) {
                        HStack {
                            Text("システムのユーザ辞書")
                            if self.systemUserDictionary.value.lastUpdate != nil {
                                Text("\(self.systemUserDictionary.value.items.count)件")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .help("macOSの「テキスト置換」に登録した単語を変換候補に加えます。変更は自動で反映されます。")
                    if case .error(let error) = self.systemUserDictionaryUpdateMessage {
                        Text("読み込みエラー: \(error.localizedDescription)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "連絡先の氏名",
                        isOn: Binding(
                            get: { self.contactsNameConversion.value },
                            set: { newValue in
                                Task { @MainActor in
                                    await self.setContactsNameConversion(newValue)
                                }
                            }
                        )
                    )
                    .disabled(self.contactsAccessRequestInProgress)
                    .help("フリガナが登録されている連絡先の姓・名を変換候補に加えます。連絡先のデータは端末の外へ送信されません。")
                    if self.contactsAccessDenied || (self.contactsNameConversion.value && !ContactsNameProvider.isAuthorized) {
                        HStack {
                            Text("連絡先へのアクセスが許可されていません。システム設定の「プライバシーとセキュリティ」>「連絡先」でazooKeyを許可してください。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("システム設定を開く") {
                                self.openContactsPrivacySettings()
                            }
                        }
                    }
                }
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let lastLoadedAt = self.userDictionaryLoadStatus.value.lastLoadedAt {
                            Text(lastLoadedAt.formatted(date: .numeric, time: .standard))
                        } else {
                            Text("まだ読み込まれていません")
                        }
                        if self.userDictionaryLoadStatus.value.isUsingPreviousDictionaryAfterFailure {
                            Text("読み込みに失敗したため、直前の辞書を使っています")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } label: {
                    Text("最終更新日時")
                }
                .help("単語の編集や、上の項目の切り替えのたびに更新されます")
            } header: {
                Label("ユーザ辞書", systemImage: "book.closed")
            }

            Section {
                Toggle("ライブ変換を有効化", isOn: $liveConversion)
                HStack {
                    TextField("変換プロフィール", text: $zenzaiProfile, prompt: Text("例：田中太郎/高校生"))
                    helpButton(
                        helpContent: """
                    Zenzaiはあなたのプロフィールを考慮した変換を行うことができます。
                    名前や仕事、趣味などを入力すると、それに合わせた変換が自動で推薦されます。
                    （実験的な機能のため、精度が不十分な場合があります）
                    """,
                        isPresented: $zenzaiProfileHelpPopover
                    )
                }
            } header: {
                Label("変換設定", systemImage: "brain")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - カスタマイズタブ
    @ViewBuilder
    private var customizeTabView: some View {
        Form {
            Section {
                Toggle("円記号の代わりにバックスラッシュを入力", isOn: $typeBackSlash)
                Toggle("スペースは常に半角を入力", isOn: $typeHalfSpace)
                Toggle("Optionキーで直接全角英数を入力", isOn: $optionDirectFullWidthInput)
                Picker("句読点の種類", selection: $punctuationStyle) {
                    Text("、と。").tag(Config.PunctuationStyle.Value.`kutenAndToten`)
                    Text("、と．").tag(Config.PunctuationStyle.Value.periodAndToten)
                    Text("，と。").tag(Config.PunctuationStyle.Value.kutenAndComma)
                    Text("，と．").tag(Config.PunctuationStyle.Value.periodAndComma)
                }
            } header: {
                Label("入力オプション", systemImage: "character.cursor.ibeam")
            }

            Section {
                LabeledContent("候補の文字サイズ") {
                    HStack {
                        Text("\(self.candidateFontSize.value) pt")
                            .monospacedDigit()
                        Stepper("", value: $candidateFontSize, in: Config.CandidateFontSize.range)
                            .labelsHidden()
                        Button("標準に戻す") {
                            self.$candidateFontSize.wrappedValue = Config.CandidateFontSize.default
                        }
                        .disabled(self.candidateFontSize.value == Config.CandidateFontSize.default)
                    }
                }
                Picker("候補のフォント", selection: $candidateFontName) {
                    Text("システム標準").tag("")
                    // 一覧に無いフォント（削除されたものなど）が設定されていても選択状態を保つ
                    if !self.candidateFontName.value.isEmpty && !self.japaneseFontFamilies.contains(self.candidateFontName.value) {
                        Text(self.candidateFontName.value).tag(self.candidateFontName.value)
                    }
                    ForEach(self.japaneseFontFamilies, id: \.self) { family in
                        // 「YuKyokasho」ではなく「游教科書体」のように表示する
                        Text(NSFontManager.shared.localizedName(forFamily: family, face: nil)).tag(family)
                    }
                }
                .task {
                    if self.japaneseFontFamilies.isEmpty {
                        self.japaneseFontFamilies = Self.japaneseFontFamilies()
                    }
                }
            } header: {
                Label("候補ウィンドウ", systemImage: "textformat.size")
            }

            Section {
                Picker("履歴学習", selection: $learning) {
                    Text("学習する").tag(Config.Learning.Value.inputAndOutput)
                    Text("学習を停止").tag(Config.Learning.Value.onlyOutput)
                    Text("学習を無視").tag(Config.Learning.Value.nothing)
                }
                LabeledContent {
                    HStack {
                        switch learningResetMessage {
                        case .none:
                            EmptyView()
                        case .success:
                            Text("履歴学習データをリセットしました")
                                .foregroundColor(.green)
                        case .error(let message):
                            Text("エラー: \(message)")
                                .foregroundColor(.red)
                        }
                        Spacer()
                        Button("リセット") {
                            showingLearningResetConfirmation = true
                        }
                        .confirmationDialog(
                            "履歴学習データをリセットしますか？",
                            isPresented: $showingLearningResetConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("リセット", role: .destructive) {
                                resetLearningData()
                            }
                            Button("キャンセル", role: .cancel) {}
                        }
                    }
                } label: {
                    Text("履歴学習データ")
                }
                LegacyDataImportView(privateApplicationSupportURL: self.legacyAzooKeyApplicationSupportDirectoryURL)
            } header: {
                Label("学習", systemImage: "memorychip")
            }

            Section {
                Picker("入力方式", selection: $inputStyle) {
                    Text("デフォルト").tag(Config.InputStyle.Value.default)
                    Text("かな入力（JIS）").tag(Config.InputStyle.Value.defaultKanaJIS)
                    Text("かな入力（US）").tag(Config.InputStyle.Value.defaultKanaUS)
                    Text("AZIK").tag(Config.InputStyle.Value.defaultAZIK)
                    Text("カスタム").tag(Config.InputStyle.Value.custom)
                }
                if inputStyle.value == .custom {
                    LabeledContent {
                        Button("編集") {
                            showingRomajiTableEditor = true
                        }
                    } label: {
                        Text("カスタム入力テーブル")
                    }
                }
            } header: {
                Label("入力方式", systemImage: "keyboard")
            }

            Section {
                Picker("キーボード配列", selection: $keyboardLayout) {
                    Text("QWERTY").tag(Config.KeyboardLayout.Value.qwerty)
                    Text("Australian").tag(Config.KeyboardLayout.Value.australian)
                    Text("British").tag(Config.KeyboardLayout.Value.british)
                    Text("Colemak").tag(Config.KeyboardLayout.Value.colemak)
                    Text("Dvorak").tag(Config.KeyboardLayout.Value.dvorak)
                    Text("Dvorak - QWERTY ⌘").tag(Config.KeyboardLayout.Value.dvorakQwertyCommand)
                }
            } header: {
                Label("キーボード配列", systemImage: "keyboard.badge.ellipsis")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - 詳細設定タブ
    @ViewBuilder
    private var advancedTabView: some View {
        Form {
            Section {
                HStack {
                    TextField("変換プロフィール", text: $zenzaiProfile, prompt: Text("例：田中太郎/高校生"))
                    helpButton(
                        helpContent: """
                    Zenzaiはあなたのプロフィールを考慮した変換を行うことができます。
                    名前や仕事、趣味などを入力すると、それに合わせた変換が自動で推薦されます。
                    （実験的な機能のため、精度が不十分な場合があります）
                    """,
                        isPresented: $zenzaiProfileHelpPopover
                    )
                }
                HStack {
                    TextField(
                        "Zenzaiの推論上限",
                        text: Binding(
                            get: {
                                String(self.$inferenceLimit.wrappedValue)
                            },
                            set: {
                                if let value = Int($0), (1 ... 50).contains(value) {
                                    self.$inferenceLimit.wrappedValue = value
                                }
                            }
                        )
                    )
                    Stepper("", value: $inferenceLimit, in: 1 ... 50)
                        .labelsHidden()
                    helpButton(helpContent: "推論上限を小さくすると、入力中のもたつきが改善されることがあります。", isPresented: $zenzaiInferenceLimitHelpPopover)
                }
            } header: {
                Label("Zenzai設定", systemImage: "cpu")
            }

            Section {
                Toggle("デバッグウィンドウを有効化", isOn: $debugWindow)
                Toggle("開発中の予測入力を有効化", isOn: $debugPredictiveTyping)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("開発中の入力訂正を有効化", isOn: $debugTypoCorrection)
                    if self.debugTypoCorrection.value {
                        HStack {
                            Text(self.debugTypoCorrectionStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if self.debugTypoCorrectionDownloadInProgress {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Spacer()
                            switch self.debugTypoCorrectionState {
                            case .downloaded:
                                EmptyView()
                            case .failed:
                                Button("再ダウンロード") {
                                    self.downloadDebugTypoCorrectionWeights()
                                }
                                .disabled(self.debugTypoCorrectionDownloadInProgress)
                            case .notDownloaded:
                                Button("ダウンロード") {
                                    self.downloadDebugTypoCorrectionWeights()
                                }
                                .disabled(self.debugTypoCorrectionDownloadInProgress)
                            }
                        }
                        if case .failed = self.debugTypoCorrectionState,
                           let errorMessage = self.debugTypoCorrectionErrorMessage {
                            Text(errorMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .onAppear {
                    guard self.debugTypoCorrection.value else {
                        return
                    }
                    Task { @MainActor in
                        await self.refreshDebugTypoCorrectionState()
                    }
                }
                .onChange(of: self.debugTypoCorrection.value) { enabled in
                    if enabled {
                        Task { @MainActor in
                            await self.refreshDebugTypoCorrectionState()
                        }
                    } else {
                        self.debugTypoCorrectionState = .notDownloaded
                        self.debugTypoCorrectionDownloadInProgress = false
                        self.debugTypoCorrectionErrorMessage = nil
                    }
                }
                Picker("パーソナライズ", selection: $zenzaiPersonalizationLevel) {
                    Text("オフ").tag(Config.ZenzaiPersonalizationLevel.Value.off)
                    Text("弱く").tag(Config.ZenzaiPersonalizationLevel.Value.soft)
                    Text("普通").tag(Config.ZenzaiPersonalizationLevel.Value.normal)
                    Text("強く").tag(Config.ZenzaiPersonalizationLevel.Value.hard)
                }
                LabeledContent("アプリデータ") {
                    HStack {
                        Button("Finderで開く") {
                            self.openAzooKeyDataDirectoryInFinder()
                        }
                    }
                }
            } header: {
                Label("開発者向け設定", systemImage: "hammer")
            }

            Section {
                LabeledContent("Version") {
                    Text(PackageMetadata.gitTag ?? PackageMetadata.gitCommit ?? "Unknown Version")
                        .monospaced()
                        .bold()
                        .copyable([
                            PackageMetadata.gitTag ?? PackageMetadata.gitCommit ?? "Unknown Version"
                        ])
                }
                .textSelection(.enabled)
            } header: {
                Label("アプリ情報", systemImage: "info.circle")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    ConfigWindow()
}
