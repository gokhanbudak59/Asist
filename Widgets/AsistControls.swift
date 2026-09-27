// FILE: Widgets/AsistControls.swift
import AppIntents
import SwiftUI
import WidgetKit

struct AsistDinleControl: ControlWidget {
    static let kind = "com.gokhanbudak.asist.control.dinle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AsistAcIntent(target: .dinle)) {
                Label("Asist Dinle", systemImage: "mic.fill")
            }
        }
        .displayName("Asist Dinle")
        .description("Asist'i açar ve hemen dinlemeye başlar.")
    }
}

struct AsistYazControl: ControlWidget {
    static let kind = "com.gokhanbudak.asist.control.yaz"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AsistAcIntent(target: .yaz)) {
                Label("Asist Yaz", systemImage: "square.and.pencil")
            }
        }
        .displayName("Asist Yaz")
        .description("Asist'i yazma ekranıyla açar.")
    }
}
