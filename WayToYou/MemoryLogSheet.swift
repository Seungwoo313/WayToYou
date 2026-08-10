import SwiftUI

/// 주고받은 것들의 연대기. 예전 버전은 소포 한 개, 시그널 한 개만 기억해서
/// 어제 무슨 일이 있었는지 앱이 전혀 모르는 상태였다.
struct MemoryLogSheet: View {
    let store: WayToYouStore
    let now: Date
    let presentedAsSheet: Bool
    let onSelect: (Parcel) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        store: WayToYouStore,
        now: Date,
        presentedAsSheet: Bool = true,
        onSelect: @escaping (Parcel) -> Void
    ) {
        self.store = store
        self.now = now
        self.presentedAsSheet = presentedAsSheet
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackground().equatable()

                if entries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Metric.xl) {
                            summary

                            ForEach(groups, id: \.day) { group in
                                VStack(alignment: .leading, spacing: Metric.m) {
                                    Text(group.label)
                                        .font(.rounded(.footnote, .semibold))
                                        .foregroundStyle(Palette.textTertiary)
                                        .padding(.leading, Metric.xs)

                                    ForEach(group.entries) { entry in
                                        row(for: entry)
                                    }
                                }
                            }
                        }
                        .padding(Metric.screenPadding)
                    }
                }
            }
            .navigationTitle("우리의 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if presentedAsSheet {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { dismiss() }
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(Palette.space)
    }

    // MARK: - Header

    private var summary: some View {
        HStack(spacing: 0) {
            stat(value: "\(sentCount)", label: "보낸 소포", tint: Palette.me)
            divider
            stat(value: "\(receivedCount)", label: "받은 소포", tint: Palette.you)
            divider
            stat(value: "\(store.signals.count)", label: "시그널", tint: Palette.textSecondary)
        }
        .padding(.vertical, Metric.l)
        .frame(maxWidth: .infinity)
        .glassPanel(radius: Metric.cardRadius)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: 1, height: 30)
    }

    private func stat(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.rounded(.caption2))
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Metric.m) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text("아직 기록이 없어요")
                .font(.rounded(.title3, .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("주고받은 소포와 시그널이 여기 쌓여요")
                .font(.rounded(.subheadline))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(Metric.xxl)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for entry: LogEntry) -> some View {
        switch entry.kind {
        case .parcel(let parcel) where parcel.direction == .incoming:
            // 받은 소포만 다시 열어볼 수 있다. 보낸 건 내 편지라 열 게 없다.
            Button { onSelect(parcel) } label: { parcelRow(parcel) }
                .buttonStyle(PressableCard())

        case .parcel(let parcel):
            parcelRow(parcel)

        case .signal(let event):
            signalRow(event)
        }
    }

    private func parcelRow(_ parcel: Parcel) -> some View {
        let tint = Palette.tint(for: parcel.direction)
        let isMine = parcel.direction == .outgoing
        return HStack(spacing: Metric.m) {
            // 포장지 색 막대 하나로 어떤 소포였는지 알려준다.
            // 아이콘을 원에 담아 늘어놓으면 화면이 아이콘 판이 된다.
            Capsule()
                .fill(parcel.wrap.color)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(isMine ? "보냄" : "받음")
                        .font(.rounded(.caption2, .bold))
                        .foregroundStyle(tint)
                    if parcel.isSimulated {
                        Text("데모")
                            .font(.rounded(.caption2, .medium))
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Palette.textTertiary.opacity(0.14), in: Capsule())
                    }
                }
                Text(parcel.title)
                    .font(.rounded(.subheadline, .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(statusCaption(for: parcel))
                    .font(.rounded(.caption2))
                    .foregroundStyle(Palette.textTertiary)
            }

            Spacer(minLength: Metric.s)

            if parcel.direction == .incoming && parcel.openedAt == nil && parcel.phase(at: now) == .arrived {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .padding(Metric.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
        )
    }

    private func statusCaption(for parcel: Parcel) -> String {
        switch parcel.phase(at: now) {
        case .inTransit:
            let remaining = max(parcel.arrivesAt.timeIntervalSince(now), 0)
            return "이동 중 · \(remaining.shortKoreanDuration) 남음"
        case .arrived:
            return parcel.direction == .outgoing
                ? "도착 · 아직 열어보지 않았어요"
                : "도착 · 열어보세요"
        case .opened:
            let openedAt = parcel.openedAt ?? parcel.arrivesAt
            return parcel.direction == .outgoing
                ? "상대가 \(openedAt.koreanRelative(to: now)) 읽었어요"
                : "\(openedAt.koreanRelative(to: now)) 읽음"
        }
    }

    private func signalRow(_ event: SignalEvent) -> some View {
        let tint = Palette.tint(for: event.direction)
        return HStack(spacing: Metric.m) {
            Circle()
                .fill(event.signal.color)
                .frame(width: 6, height: 6)
                .padding(.leading, 13)

            Text(event.direction == .outgoing ? "내가 ‘\(event.signal.title)’" : "상대가 ‘\(event.signal.title)’")
                .font(.rounded(.footnote))
                .foregroundStyle(Palette.textSecondary)

            Spacer(minLength: Metric.s)

            Text(event.sentAt.koreanRelative(to: now))
                .font(.rounded(.caption2))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, Metric.m)
        .padding(.vertical, Metric.s)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tint.opacity(0.45))
                .frame(width: 4, height: 14)
        }
    }

    // MARK: - Data

    private var sentCount: Int { store.parcels.filter { $0.direction == .outgoing }.count }
    private var receivedCount: Int { store.parcels.filter { $0.direction == .incoming }.count }

    private var entries: [LogEntry] {
        let parcelEntries = store.parcels.map {
            LogEntry(id: $0.id, date: $0.sentAt, kind: .parcel($0))
        }
        let signalEntries = store.signals.map {
            LogEntry(id: $0.id, date: $0.sentAt, kind: .signal($0))
        }
        return (parcelEntries + signalEntries)
            .filter { $0.date <= now }
            .sorted { $0.date > $1.date }
    }

    private var groups: [LogGroup] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = store.homeCity.timeZone
        let buckets = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return buckets.keys.sorted(by: >).map { day in
            LogGroup(day: day, label: label(for: day, calendar: calendar), entries: buckets[day] ?? [])
        }
    }

    private func label(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "오늘" }
        if calendar.isDateInYesterday(day) { return "어제" }
        return day.dayHeader(in: store.homeCity.timeZone)
    }
}

private struct LogEntry: Identifiable {
    enum Kind {
        case parcel(Parcel)
        case signal(SignalEvent)
    }

    let id: UUID
    let date: Date
    let kind: Kind
}

private struct LogGroup {
    let day: Date
    let label: String
    let entries: [LogEntry]
}
