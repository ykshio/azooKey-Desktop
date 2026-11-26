# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

azooKey on macOS: InputMethodKit 製の日本語 IME。変換エンジンは外部パッケージ AzooKeyKanaKanjiConverter（AZKKC、Zenzai 含む）。

## ビルド・テスト

前提: Xcode 26.1+（CI は Xcode 27.2）、Git LFS、SwiftLint。submodule（`azooKeyMac/Resources/gguf`, `base_n5_lm`）に LFS の重みが入る。

```bash
# Core パッケージ（ロジックの大半。CI と同じ）
swift build --package-path Core
swift test  --package-path Core
swift test  --package-path Core --filter CompiledUserDictionaryStoreTests   # 単体（Swift Testing の関数名/ファイル内スイートで絞る）

# アプリ本体のビルド確認（署名なし。CI と同じ）
xcodebuild -project azooKeyMac.xcodeproj -scheme azooKeyMac -configuration Release \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# Lint（CI は --strict。違反があると落ちる）
swiftlint --quiet --strict

# 実機インストール（archive → /Library/Input Methods へ sudo ditto → pkill）
./install.sh            # --ignore-lint / --dry-run / --no-pkill
```

- 初回の `xcodebuild` は SPM 依存を GitHub から取得する（キーチェーンの github.com 認証情報の許可ダイアログが出ることがある）。
- `swift test` は Ubuntu でも CI で回る。`Core` に macOS 専用 API を足すときは `#if os(macOS)` で囲む（Zenzai trait も macOS のみ）。
- テストは `Core/Tests/CoreTests` に Swift Testing（`import Testing`, `@Test`）で書く。`azooKeyMacTests` はほぼ空で、UI・権限系はテストしない。

## 構成

- `Core/`（SPM, ライブラリ `Core`）: UI 非依存のロジック。設定、ユーザ辞書のコンパイル、入力状態機械（`InputUtils/InputState.swift`, `SegmentsManager.swift`）、キーマップ、いい感じ変換のクライアント。新しいロジックとテストはなるべくここに置く。
- `azooKeyMac/`（Xcode アプリターゲット）: IMK の入力コントローラ、候補ウィンドウ、設定画面（SwiftUI）。`InputController/`, `Configs/`, `Windows/` は Xcode の synchronized group なので、ファイルを置くだけでターゲットに入る（pbxproj 編集不要）。

### プロセスと変換器
- `AppDelegate` が `IMKServer` と `KanaKanjiConverter` を**1つだけ**持ち、入力セッション（`azooKeyMacInputController` はクライアントごとに生成）間で共有する。設定ウィンドウも同じプロセス内。
- `activateServer` / `deactivateServer` がセッションの開始・終了。Chromium 系アプリでの deadlock 回避のため、activate 中に `client.attributes(...)` 等の同期問い合わせをしない（コメント参照）。

### 設定
- `Config.*` 構造体（`Core/Sources/Core/Configs/`）。`BoolConfigItem` / `IntConfigItem` / `StringConfigItem` / `CustomCodableConfigItem`（JSON）のどれかに準拠させ、`key` は `dev.ensan.inputmethod.azooKeyMac.preference.*`。
- 保存先は App Group `group.com.azookey.mac` の UserDefaults（読み込みは `.standard` へフォールバック）。キーや型を変えると既存ユーザーの設定が消えるので変更しない。
- SwiftUI では `@ConfigState private var x = Config.X()` で束縛する（UserDefaults の変更通知で再描画）。

### ユーザ辞書
- 元データは設定値: `Config.UserDictionary`（azooKey 辞書）と `Config.SystemUserDictionary`（macOS のユーザ辞書 `TextReplacements.db` を「読み込む」ボタンで取り込んだもの）。
- `CompiledUserDictionaryStore` が両者を LOUDS 形式にコンパイルし `AppGroup.memoryDirectoryURL()/UserDictionary/` に書く（一時ディレクトリに作ってから差し替え）。
- 編集時は `AppDelegate.exportUserDictionaryAndReloadConverter()` → `kanaKanjiConverter.updateUserDictionaryURL(_, forceReload: true)` で反映。

### 候補ウィンドウ
- IMKCandidates ではなく自前描画（`InputController/CandidateWindow/`）。`BaseCandidateViewController`（NSTableView）を `CandidatesViewController` / `PredictionCandidatesViewController` / `ReplaceSuggestionsViewController` が継承。ウィンドウサイズは行高と文字幅から `resizeWindowToFitContent` で計算する。

## 規約
- コメント・UI 文言・コミットメッセージは日本語。コミットは Conventional Commits 風（`feat(macOS): …`, `fix(input): …`, `chore(deps): …`）。
- SwiftLint の opt-in ルール（`implicit_return`, `sorted_imports` など）に従う。`install.sh` は `swiftlint --fix` を自動実行する。
