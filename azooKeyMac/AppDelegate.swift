//
//  AppDelegate.swift
//  AppDelegate
//
//  Created by ensan on 2021/09/06.
//

import Cocoa
import Core
import InputMethodKit
import KanaKanjiConverterModuleWithDefaultDictionary
import SwiftUI

// Necessary to launch this app
class NSManualApplication: NSApplication {
    let appDelegate = AppDelegate()

    override init() {
        super.init()
        self.delegate = appDelegate
    }

    required init?(coder: NSCoder) {
        // No need for implementation
        fatalError("init(coder:) has not been implemented")
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer?
    weak var configWindow: NSWindow?
    weak var userDictionaryEditorWindow: NSWindow?
    var configWindowController: NSWindowController?
    var userDictionaryEditorWindowController: NSWindowController?
    let kanaKanjiConverter = KanaKanjiConverter.withDefaultDictionary()
    private let learningDataCommitScheduler = DebouncedActionScheduler()
    private static let learningDataCommitDelay: TimeInterval = 2

    @MainActor
    func scheduleLearningDataCommit() {
        learningDataCommitScheduler.schedule(after: Self.learningDataCommitDelay) { [weak self] in
            self?.kanaKanjiConverter.commitUpdateLearningData()
        }
    }

    @MainActor
    func postponeLearningDataCommit() {
        learningDataCommitScheduler.postponeIfScheduled(after: Self.learningDataCommitDelay)
    }

    /// ユーザ辞書の書き出しと変換器への再読込を受け持つ
    @MainActor
    private lazy var userDictionaryReloader = UserDictionaryReloader(
        directoryURL: CompiledUserDictionaryStore.directoryURL(memoryDirectoryURL: AppGroup.memoryDirectoryURL()),
        entriesProvider: {
            // 取り込み済みのmacOSのユーザ辞書が更新されていれば、先に読み直しておく
            SystemUserDictionaryHelper.refreshIfNeeded(databaseURL: SystemUserDictionaryHelper.defaultDatabaseURL)
            return try CompiledUserDictionaryStore.currentEntries()
        },
        builder: { entries, directoryURL in
            try CompiledUserDictionaryStore.rebuild(entries: entries, directoryURL: directoryURL)
        },
        reload: { [weak self] directoryURL in
            self?.kanaKanjiConverter.updateUserDictionaryURL(directoryURL, forceReload: true)
        }
    )

    /// 元データや辞書ファイルが変わっていれば再構築・再読込する（入力セッション開始時など）
    @MainActor
    func reloadUserDictionaryIfNeeded() {
        self.userDictionaryReloader.reloadIfNeeded()
    }

    /// 辞書を編集したときに呼ぶ。必ず書き出し直してから再読込する
    @MainActor
    @discardableResult
    func exportUserDictionaryAndReloadConverter() -> Task<Bool, Never> {
        self.userDictionaryReloader.reloadIfNeeded(forceRebuild: true)
    }

    private static func buildSwiftUIWindow(
        _ view: some View,
        contentRect: NSRect = NSRect(x: 0, y: 0, width: 400, height: 300),
        styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .borderless],
        title: String = ""
    ) -> (window: NSWindow, windowController: NSWindowController) {
        // Create a new window
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        // Set the window title
        window.title = title
        window.contentViewController = NSHostingController(rootView: view)
        // Keep window with in a controller
        let windowController = NSWindowController(window: window)
        // Show the window
        window.level = .modalPanel
        window.makeKeyAndOrderFront(nil)
        return (window, windowController)
    }

    func openConfigWindow() {
        if let configWindow {
            // Show the window
            configWindow.level = .modalPanel
            configWindow.makeKeyAndOrderFront(nil)
        } else {
            // Create a new window
            (self.configWindow, self.configWindowController) = Self.buildSwiftUIWindow(ConfigWindow(), title: "設定")
        }
    }

    func openUserDictionaryEditorWindow() {
        if let userDictionaryEditorWindow {
            // Show the window
            userDictionaryEditorWindow.level = .modalPanel
            userDictionaryEditorWindow.makeKeyAndOrderFront(nil)
        } else {
            (self.userDictionaryEditorWindow, self.userDictionaryEditorWindowController) = Self.buildSwiftUIWindow(UserDictionaryEditorWindow(), title: "設定")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try LegacyDataMigration.applyStagedLearning(to: AppGroup.memoryDirectoryURL())
        } catch {
            NSLog("Failed to import legacy learning data: %@", error.localizedDescription)
        }
        // Insert code here to initialize your application
        self.server = IMKServer(name: Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String, bundleIdentifier: Bundle.main.bundleIdentifier)
        NSLog("tried connection")

        // Keychainから設定値を非同期で読み込み
        Task {
            await Config.OpenAiApiKey.loadFromKeychain()
        }
        self.reloadUserDictionaryIfNeeded()

        // Check if mainMenu exists, or create it
        if NSApp.mainMenu == nil {
            NSApp.mainMenu = NSMenu()
        }

        // Add an Edit menu
        let editMenu = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        NSApp.mainMenu?.addItem(editMenu)
        let editSubmenu = NSMenu(title: "Edit")
        editMenu.submenu = editSubmenu

        // Add standard Edit actions
        editSubmenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editSubmenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editSubmenu.addItem(NSMenuItem.separator())
        editSubmenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editSubmenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editSubmenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editSubmenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    }

    func applicationWillTerminate(_ notification: Notification) {
        learningDataCommitScheduler.cancel()
        kanaKanjiConverter.commitUpdateLearningData()
    }
}
