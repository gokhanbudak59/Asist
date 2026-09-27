// WP9 (04 §5.1): `SheetRoute → View` switch for the single app-wide sheet (router.sheet).
import SwiftUI

struct SheetHost: View {
    let route: SheetRoute

    var body: some View {
        Group {
            switch route {
            case .compose(let request):
                ComposeSheet(request: request)
            case .confirm(let draft):
                ConfirmationSheet(draft: draft)
            case .match(let proposal):
                MatchConfirmationSheet(proposal: proposal)
            case .agenda(let answer):
                AgendaAnswerSheet(answer: answer)
            case .datePicker(let request):
                DateTimePickerSheet(request: request)
            case .projectEditor(let id):
                ProjectEditorSheet(projectID: id)
            case .followUpMessage(let id):
                FollowUpMessageSheet(itemID: id)
            }
        }
        .overlay(alignment: .bottom) {
            // The sheet covers RootView's toast: "Geri Al" of an action taken inside a sheet (✓ in the agenda
            // sheet, "Kopyala" …) must stay visible and tappable here.
            ToastHost(inSheet: true)
        }
    }
}
