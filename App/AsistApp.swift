// FILE: App/AsistApp.swift
import SwiftUI

@main
struct AsistApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AsistShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppEnvironment.shared.store)
                .environment(AppEnvironment.shared.router)
                .environment(AppEnvironment.shared.voice)
                .environment(AppEnvironment.shared.engine)
                .environment(AppEnvironment.shared.permissions)
                .environment(AppEnvironment.shared.toasts)
                .environment(AppEnvironment.shared.signing)
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .tint(.indigo)
        }
    }
}
