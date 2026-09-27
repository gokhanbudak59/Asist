// WP9 (04 §5.2; 03 §4.3, §7.10, §9; D32; 05b B6/D5/D8/F2/F13/F14): the Bugün screen.
// Header + one warning band + mute band + end-of-day undo band + "Şimdi ilgilen" hero card + sections
// GECİKENLER / EMİN OLAMADIKLARIM / BUGÜN / TAKİP / YAKLAŞAN / ZAMANI BELİRSİZ + "Bu hafta n iş bitti",
// with the Yaz / Mic / Oku bar pinned above the tab bar. The agenda snapshot is computed once per render inside
// TimelineView(.everyMinute), so relative times refresh every minute and after every store change.
import SwiftUI
import AsistCore

struct TodayView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(PermissionCenter.self) private var permissions
    @Environment(SigningMonitor.self) private var signing
    @Environment(ReminderEngine.self) private var engine
    @Environment(ToastCenter.self) private var toasts

    @State private var snoozeCandidate: Item?
    @State private var showSnoozeDialog = false
    @State private var showAllUnscheduled = false

    private static let unscheduledPreviewCount = 3

    var body: some View {
        // Read the store here (not only inside the TimelineView closure) so Observation re-renders on every change.
        let items = store.items
        let settings = store.settings
        TimelineView(.everyMinute) { context in
            content(now: context.date, items: items, settings: settings)
        }
        .navigationTitle("Bugün")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                MuteMenu()
                NavigationLink(value: Route.endOfDay) {
                    Image(systemName: Symbol.endOfDay)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Gün sonu")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomCaptureBar()
        }
        .confirmationDialog("Ertele", isPresented: $showSnoozeDialog, titleVisibility: .visible,
                            presenting: snoozeCandidate) { item in
            // Buttons directly inside ForEach (dialogs do not reliably unwrap custom container views).
            ForEach(SnoozeOption.available(now: Date(), settings: store.settings, calendar: AppTime.calendar)) { option in
                Button(option.menuTitle(now: Date(), settings: store.settings, calendar: AppTime.calendar)) {
                    ItemQuickActions.snooze(item.id, option: option, store: store, toasts: toasts, router: router)
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { item in
            Text(item.title)
        }
    }

    // MARK: - List

    private func content(now: Date, items: [Item], settings: AppSettings) -> some View {
        let calendar = AppTime.calendar
        let snapshot = AgendaBuilder.snapshot(items: items, now: now, settings: settings, calendar: calendar)
        let sections = TodaySections(snapshot: snapshot)
        return List {
            Group {
                Section {
                    TodayHeader(now: now, snapshot: snapshot, userName: settings.userName)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
                bannerSection(now: now)
                muteSection(now: now, settings: settings)
                movedSection(now: now)
                emptySection(sections)
            }
            Group {
                overdueSection(sections, now: now)
                itemSection("EMİN OLAMADIKLARIM", items: sections.review, color: Color.orange, now: now,
                            isReview: true)
                itemSection("BUGÜN", items: sections.today, color: Color.asistToday, now: now, isReview: false)
                itemSection("TAKİP", items: sections.followUps, color: Color.asistFollowUp, now: now,
                            isReview: false)
                upcomingSection(sections, now: now)
                unscheduledSection(sections, now: now)
                doneSection(sections)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func emptySection(_ sections: TodaySections) -> some View {
        if sections.isEmpty {
            Section {
                EmptyStateView(title: "Bugün için bekleyen bir şey yok",
                               message: "Aklına bir şey gelirse mikrofona dokunman yeterli.",
                               systemImage: Symbol.tabToday)
                    .listRowBackground(Color.clear)
            }
        } else if sections.nothingForToday {
            Section {
                EmptyStateView(title: "Bugünlük her şey tamam",
                               message: "Yaklaşan işlerin aşağıda.",
                               systemImage: "checkmark.circle")
                    .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private func doneSection(_ sections: TodaySections) -> some View {
        if sections.doneThisWeek > 0 {
            Section {
                Label("Bu hafta " + String(sections.doneThisWeek) + " iş bitti", systemImage: Symbol.taskDone)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Bands

    @ViewBuilder
    private func bannerSection(now: Date) -> some View {
        if let banner = permissions.topBanner(store: store, signing: signing, engine: engine, now: now) {
            Section {
                BannerView(banner: banner,
                           onAction: { performBannerAction(banner.action) },
                           onDismiss: dismissHandler(for: banner))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private func muteSection(now: Date, settings: AppSettings) -> some View {
        if let until = settings.muteUntil, until > now {
            Section {
                MuteBanner(until: until) {
                    cancelMute()
                }
            }
        }
    }

    @ViewBuilder
    private func movedSection(now: Date) -> some View {
        if let record = store.meta.lastEndOfDayMove, !record.before.isEmpty,
           now.timeIntervalSince(record.movedAt) < 24 * 3600 {
            Section {
                HStack(spacing: Metrics.cardSpacing) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(Color.asistUpcoming)
                        .accessibilityHidden(true)
                    Text(String(record.before.count) + " iş sonraki iş gününe taşındı.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        undoMove(record)
                    } label: {
                        Text("Geri Al")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    Button {
                        store.updateMeta { meta in
                            meta.lastEndOfDayMove = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Color.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Kapat")
                }
            }
        }
    }

    // MARK: - Item sections

    @ViewBuilder
    private func overdueSection(_ sections: TodaySections, now: Date) -> some View {
        if let hero = sections.hero {
            Section {
                HeroCard(item: hero, projectName: store.projectName(for: hero), now: now)
                    .listRowInsets(EdgeInsets())
                ForEach(sections.overdueRest) { item in
                    row(item, now: now, isReview: false)
                }
            } header: {
                SectionHeader(title: "GECİKENLER", count: sections.overdueCount, color: Color.asistOverdue)
            }
        }
    }

    @ViewBuilder
    private func itemSection(_ title: String, items: [Item], color: Color, now: Date, isReview: Bool) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    row(item, now: now, isReview: isReview)
                }
            } header: {
                SectionHeader(title: title, count: items.count, color: color)
            }
        }
    }

    @ViewBuilder
    private func upcomingSection(_ sections: TodaySections, now: Date) -> some View {
        if !sections.upcoming.isEmpty {
            Section {
                ForEach(sections.upcoming) { group in
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.asistUpcoming)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.items) { item in
                        row(item, now: now, isReview: false)
                    }
                }
                if sections.upcomingTotal > sections.upcomingShown {
                    Button {
                        router.listFilter = .reminders
                        router.selectedTab = .lists
                    } label: {
                        Text("Tümünü göster (" + String(sections.upcomingTotal) + ")")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            } header: {
                SectionHeader(title: "YAKLAŞAN", color: Color.asistUpcoming)
            }
        }
    }

    @ViewBuilder
    private func unscheduledSection(_ sections: TodaySections, now: Date) -> some View {
        if !sections.unscheduled.isEmpty {
            let visible = showAllUnscheduled
                ? sections.unscheduled
                : Array(sections.unscheduled.prefix(TodayView.unscheduledPreviewCount))
            Section {
                ForEach(visible) { item in
                    row(item, now: now, isReview: false)
                }
                if !showAllUnscheduled && sections.unscheduled.count > visible.count {
                    Button {
                        showAllUnscheduled = true
                    } label: {
                        Text("Tümünü göster (" + String(sections.unscheduled.count) + ")")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            } header: {
                SectionHeader(title: "ZAMANI BELİRSİZ", count: sections.unscheduled.count, color: Color.secondary)
            }
        }
    }

    private func row(_ item: Item, now: Date, isReview: Bool) -> some View {
        let id = item.id
        return NavigationLink(value: Route.item(id)) {
            ItemRow(item: item, projectName: store.projectName(for: item), now: now) {
                ItemQuickActions.complete(id, store: store, toasts: toasts)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                ItemQuickActions.complete(id, store: store, toasts: toasts)
            } label: {
                Label(item.kind == .waiting ? "Geldi" : "Yaptım", systemImage: "checkmark")
            }
            .tint(Color.asistDone)
            if isReview {
                Button {
                    ItemQuickActions.confirmReview(id, store: store, toasts: toasts)
                } label: {
                    Label("Doğru", systemImage: "hand.thumbsup.fill")
                }
                .tint(Color.asistAccent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                ItemQuickActions.delete(id, store: store, toasts: toasts)
            } label: {
                Label("Sil", systemImage: "trash")
            }
            Button {
                snoozeCandidate = item
                showSnoozeDialog = true
            } label: {
                Label("Ertele", systemImage: Symbol.snooze)
            }
            .tint(Color.asistToday)
        }
    }

    // MARK: - Actions

    @MainActor
    private func performBannerAction(_ action: BannerAction) {
        switch action {
        case .openNotificationSettings:
            PermissionCenter.openNotificationSettings()
        case .openAppSettings:
            PermissionCenter.openAppSettings()
        case .openAppStatus:
            router.openRoute(.appStatus, in: .settings)
        case .openDiagnostics:
            router.openRoute(.diagnostics, in: .settings)
        case .openGuideBanners:
            router.openRoute(.guide(.banners), in: .settings)
        case .none:
            break
        }
    }

    private func dismissHandler(for banner: AppBanner) -> (() -> Void)? {
        guard banner.dismissible else { return nil }
        return {
            dismissBanner(banner)
        }
    }

    @MainActor
    private func dismissBanner(_ banner: AppBanner) {
        let hours = max(1, banner.hideHours)
        let until = Date().addingTimeInterval(TimeInterval(hours) * 3600)
        let id = banner.id
        store.updateMeta { meta in
            meta.dismissedBanners[id] = until
        }
        Haptics.selection()
    }

    @MainActor
    private func cancelMute() {
        store.updateSettings { settings in
            settings.muteUntil = nil
        }
        toasts.show("Sessiz kapatıldı")
        Haptics.selection()
    }

    /// Undo band of "Sonraki iş gününe taşı" (< 24 h). Only items unchanged since the move are put back, so a
    /// later edit / completion is never overwritten by the old copy.
    @MainActor
    private func undoMove(_ record: MoveRecord) {
        var restorable: [Item] = []
        let limit = record.movedAt.addingTimeInterval(5)
        for old in record.before {
            guard let current = store.item(old.id), current.isOpen else { continue }
            if current.updatedAt <= limit {
                restorable.append(old)
            }
        }
        store.updateMeta { meta in
            meta.lastEndOfDayMove = nil
        }
        guard !restorable.isEmpty else {
            toasts.show("Taşınan işler sonradan değiştiği için geri alınamadı.")
            Haptics.warning()
            return
        }
        store.undo(UndoToken(label: "Gün sonu taşıma", before: restorable))
        toasts.show(String(restorable.count) + " iş eski zamanına döndü.")
        Haptics.success()
        AsistLog.info("Gün sonu taşıma geri alındı (" + String(restorable.count) + ")", .ui)
    }
}

/// Snapshot → what the screen shows. A record appears once: overdue wins over "emin olamadıklarım", which wins over
/// today / takip / upcoming / zamanı belirsiz.
private struct TodaySections {
    let hero: Item?
    let overdueRest: [Item]
    let overdueCount: Int
    let review: [Item]
    let today: [Item]
    let followUps: [Item]
    let upcoming: [DayGroup]
    let upcomingShown: Int
    let upcomingTotal: Int
    let unscheduled: [Item]
    let doneThisWeek: Int

    init(snapshot: AgendaSnapshot) {
        let overdue = snapshot.overdue
        hero = overdue.first
        overdueRest = Array(overdue.dropFirst())
        overdueCount = overdue.count

        var shownIDs = Set<UUID>()
        for item in overdue {
            shownIDs.insert(item.id)
        }
        var reviewList: [Item] = []
        for item in snapshot.review where !shownIDs.contains(item.id) {
            reviewList.append(item)
            shownIDs.insert(item.id)
        }
        review = reviewList

        today = TodaySections.remaining(snapshot.today, shown: &shownIDs)
        followUps = TodaySections.remaining(snapshot.followUps, shown: &shownIDs)

        var groups: [DayGroup] = []
        var shownUpcoming = 0
        for group in snapshot.upcoming {
            let rest = TodaySections.remaining(group.items, shown: &shownIDs)
            if !rest.isEmpty {
                groups.append(DayGroup(day: group.day, title: group.title, items: rest))
                shownUpcoming += rest.count
            }
        }
        upcoming = groups
        upcomingShown = shownUpcoming
        upcomingTotal = max(snapshot.upcomingTotal, shownUpcoming)

        unscheduled = TodaySections.remaining(snapshot.unscheduled, shown: &shownIDs)
        doneThisWeek = snapshot.doneThisWeek
    }

    /// Nothing open at all → "Bugün için bekleyen bir şey yok".
    var isEmpty: Bool {
        hero == nil && review.isEmpty && today.isEmpty && followUps.isEmpty && upcoming.isEmpty
            && unscheduled.isEmpty
    }

    /// Nothing due today but something later → "Bugünlük her şey tamam".
    var nothingForToday: Bool {
        hero == nil && review.isEmpty && today.isEmpty && followUps.isEmpty
    }

    private static func remaining(_ items: [Item], shown: inout Set<UUID>) -> [Item] {
        var result: [Item] = []
        for item in items where !shown.contains(item.id) {
            result.append(item)
            shown.insert(item.id)
        }
        return result
    }
}
