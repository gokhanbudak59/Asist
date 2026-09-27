// WP0 STUB (04 §5.1) — replaced by WP9. `SheetRoute → View` switch (already the final mapping).
import SwiftUI

struct SheetHost: View {
    let route: SheetRoute

    var body: some View {
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
}
