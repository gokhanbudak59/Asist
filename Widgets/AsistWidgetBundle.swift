// FILE: Widgets/AsistWidgetBundle.swift
import SwiftUI
import WidgetKit

/// Extension deployment target 18.0 (07 R4-D3): controls are listed directly, no availability gating.
@main
struct AsistWidgetBundle: WidgetBundle {
    var body: some Widget {
        AsistOzetWidget()
        AsistDinleKilitWidget()
        AsistSiradakiWidget()
        AsistDinleControl()
        AsistYazControl()
    }
}
