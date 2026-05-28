import SwiftUI

/// Toolbar above the History list: date-range chips on the left, free-
/// text search on the right. Mirrors `FilterRail`'s shape so the two
/// surfaces read as siblings — same chip group treatment, same search
/// field debounce behavior.
struct HistoryToolbar: View {
    @Environment(\.palette) private var p
    @Environment(HistoryState.self) private var history

    @State private var queryDraft: String = ""
    @State private var debounceArmed: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            chipGroup
            Spacer(minLength: 0)
            searchField
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Tokens.Pad.viewX)
        .padding(.vertical, 12)
        .background(p.paper)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var chipGroup: some View {
        HStack(spacing: 0) {
            chip(.all)
            divider
            chip(.today)
            divider
            chip(.last7d)
            divider
            chip(.last30d)
        }
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                .fill(p.paper2)
                .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.chip))
    }

    private var divider: some View { Hairline(axis: .vertical) }

    @ViewBuilder
    private func chip(_ value: HistoryState.DateRange) -> some View {
        let on = history.dateRange == value
        Button {
            guard history.dateRange != value else { return }
            history.dateRange = value
            // No manual load kick-off — HistoryView.body has a
            // `.task(id: history.dateRange)` that re-fires whenever
            // the range value changes, so the mutation alone is
            // enough to drive a fresh fetch.
        } label: {
            Text(value.label)
                .font(SkogaFont.smallMedium(11.5))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(on ? p.ink : p.inkMute)
                .background(on ? p.paper4 : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(skoga: .search).skogaIconSize(12).foregroundStyle(p.inkMute)
            TextField("Filter sessions, tasks, repos…", text: $queryDraft)
                .textFieldStyle(.plain)
                .font(SkogaFont.small(11.5))
                .foregroundStyle(p.ink)
                .onAppear {
                    if queryDraft != history.query { queryDraft = history.query }
                    debounceArmed = true
                }
                .onChange(of: history.query) { _, new in
                    if queryDraft != new { queryDraft = new }
                }
                .task(id: queryDraft) {
                    guard debounceArmed else { return }
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled, history.query != queryDraft else { return }
                    history.query = queryDraft
                }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(minWidth: 240)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                .fill(p.paper2)
                .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
        )
    }
}
