@testable import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

private let controlJEvent = KeyEventCore(
    modifierFlags: [.control],
    characters: "\n",
    charactersIgnoringModifiers: "j",
    keyCode: 38
)

private func makeSegmentsManager() -> SegmentsManager {
    SegmentsManager(
        kanaKanjiConverter: .withDefaultDictionary(),
        applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        containerURL: nil,
        context: .init(useZenzai: false)
    )
}

@MainActor
private func markedString(_ manager: SegmentsManager, _ state: InputState) -> String {
    manager.getCurrentMarkedText(inputState: state).reduce(into: "") { $0.append(contentsOf: $1.content) }
}

@Suite("Fnキー（Ctrl+J等）の変換は確定せずに表示する")
struct FunctionKeyPreviewTests {
    @Test(arguments: [InputState.composing, .previewing])
    func functionKeyPreviewsWithoutCommitting(state: InputState) {
        let expectations: [(UserAction.Function, ModifiedCandidateKind)] = [
            (.six, .hiragana), (.seven, .katakana), (.eight, .hankakuKatakana),
            (.nine, .fullWidthRoman), (.ten, .halfWidthRoman)
        ]
        for (function, kind) in expectations {
            let (action, callback) = state.event(
                eventCore: controlJEvent,
                userAction: .function(function),
                inputLanguage: .japanese,
                liveConversionEnabled: true,
                enableDebugWindow: false,
                enableSuggestion: false
            )
            guard case .previewModifiedCandidate(let actual) = action else {
                Issue.record("Expected previewModifiedCandidate, got \(action)")
                continue
            }
            #expect(actual == kind)
            guard case .transition(.previewing) = callback else {
                Issue.record("Expected transition to previewing, got \(callback)")
                continue
            }
        }
    }

    @MainActor
    @Test func previewShowsConvertedTextAndCommitsIt() {
        let manager = makeSegmentsManager()
        manager.insertAtCursorPosition("aiu", inputStyle: .roman2kana)

        manager.previewModifiedCandidate(kind: .katakana, inputState: .composing)
        #expect(markedString(manager, .previewing) == "アイウ")

        // 続けて別の種類に切り替えられる
        manager.previewModifiedCandidate(kind: .halfWidthRoman, inputState: .previewing)
        #expect(markedString(manager, .previewing) == "aiu")

        #expect(manager.commitMarkedText(inputState: .previewing) == "aiu")
        #expect(manager.isEmpty)
    }

    @MainActor
    @Test func editingClearsPreview() {
        let manager = makeSegmentsManager()
        manager.insertAtCursorPosition("aiu", inputStyle: .roman2kana)
        manager.previewModifiedCandidate(kind: .katakana, inputState: .composing)

        // Escape相当（候補ウィンドウを閉じる）で元に戻る
        manager.requestSetCandidateWindowState(visible: false)
        #expect(markedString(manager, .previewing) != "アイウ")

        manager.previewModifiedCandidate(kind: .katakana, inputState: .composing)
        manager.deleteBackwardFromCursorPosition()
        #expect(markedString(manager, .composing) == "あい")
        #expect(manager.commitMarkedText(inputState: .composing) == "あい")
    }
}
