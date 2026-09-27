// WP6 — 01b §3.3 (04 §3.6.7). Used only as (05a #17):
// `SystemVolumeAnchor(trigger: voice.trigger).frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)`
// Kök görünümün arkasına 1 pt olarak eklenir: sistem ses HUD'unu bastırır ve ses kaydırıcısına erişim sağlar.
import SwiftUI
import UIKit
import MediaPlayer

struct SystemVolumeAnchor: UIViewRepresentable {
    let trigger: VolumeButtonTrigger

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.alpha = 0.01                                       // 0 veya isHidden → HUD bastırılmaz
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        trigger.attach(view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        trigger.attach(uiView)
    }
}
