// FILE: App/Intents/AsistShortcuts.swift
import AppIntents

struct AsistShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: KaydetIntent(),
            phrases: [
                "\(.applicationName)'e kaydet",
                "\(.applicationName)'e ekle",
                "\(.applicationName) kaydet",
                "\(.applicationName)'e not al",
                "\(.applicationName) hatırlat"
            ],
            shortTitle: "Kaydet",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: DinleIntent(),
            phrases: [
                "\(.applicationName) dinle",
                "\(.applicationName) beni dinle",
                "\(.applicationName) ile konuş"
            ],
            shortTitle: "Dinle",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: BugunIntent(),
            phrases: [
                "\(.applicationName) bugün ne var",
                "\(.applicationName) bugün neler var",
                "\(.applicationName)'te bugün ne var",
                "\(.applicationName) gündem"
            ],
            shortTitle: "Bugün Ne Var",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: GecikenlerIntent(),
            phrases: [
                "\(.applicationName) gecikenler",
                "\(.applicationName) neyi unuttum"
            ],
            shortTitle: "Gecikenler",
            systemImageName: "exclamationmark.triangle.fill"
        )
    }
}
