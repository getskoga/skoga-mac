import SwiftUI

/// Root view inside the Settings window scene. Two columns: search +
/// section list on the left, the selected section's panel on the right.
/// Sections without a dedicated implementation render a
/// `PlaceholderSection` rather than a dead-end "coming soon" — the
/// shell is meant to ship before most of the panels do.
///
/// Mounts its own toast overlay because the toast layer lives on
/// `MainWindow`, which is invisible (and z-order-behind) when the user
/// is interacting with Settings. Without this, copying the sign-out
/// command or saving the default reviewer would surface no feedback.
struct SettingsShell: View {
    @Environment(\.palette) private var p
    @Environment(ModalState.self) private var modal

    @State private var selected: SettingsSectionID = .general
    @State private var search: String = ""

    var body: some View {
        ZStack(alignment: .top) {
            p.paper.ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                Hairline(axis: .vertical)
                detail
            }

            // Toast lives at the window level so it floats above both
            // columns. Same easing/transition as MainWindow's toast so
            // a user moving between windows gets a consistent feel.
            if let toast = modal.toast {
                VStack {
                    Spacer()
                    ToastView(text: toast).padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: modal.toast)
        .frame(minWidth: 760, minHeight: 520)
    }

    // MARK: – Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if filteredSections.isEmpty {
                        emptySearchRow
                    } else {
                        ForEach(filteredSections) { section in
                            SettingsSidebarRow(
                                section: section,
                                selected: section == selected
                            ) {
                                selected = section
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 16)
            }
            Spacer(minLength: 0)
        }
        .frame(width: Tokens.sidebarWidth, alignment: .leading)
        .background(p.paper2)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(skoga: .search).skogaIconSize(11)
                .foregroundStyle(p.inkMute)
            TextField("Search settings", text: $search)
                .textFieldStyle(.plain)
                .font(SkogaFont.body(12.5))
                .foregroundStyle(p.ink)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(skoga: .close).skogaIconSize(9)
                        .foregroundStyle(p.inkMute)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.input)
                .fill(p.paper)
                .hairlineBorder(p.rule, radius: Tokens.Radius.input)
        )
    }

    /// Case-insensitive substring match across title *and* blurb so
    /// search terms users will actually type ("api keys", "theme",
    /// "ios") still land — "api keys" doesn't match the literal title
    /// "Models & keys" but does match its blurb. Cheap enough at 12
    /// entries that the linear scan doesn't need indexing.
    private var filteredSections: [SettingsSectionID] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = SettingsSectionID.allCases
        if q.isEmpty { return all }
        return all.filter {
            $0.title.lowercased().contains(q) ||
            $0.blurb.lowercased().contains(q)
        }
    }

    private var emptySearchRow: some View {
        Text("No matches")
            .font(SkogaFont.body(12))
            .foregroundStyle(p.inkMute)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    // MARK: – Detail

    private var detail: some View {
        ScrollView {
            content
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 28)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.paper)
    }

    @ViewBuilder private var content: some View {
        switch selected {
        case .general:
            GeneralSettingsSection()
        case .github:
            GitHubSettingsSection()
        case .modelsKeys:
            ModelsSettingsSection()
        case .notifications:
            NotificationsSettingsSection()
        case .budgets:
            BudgetsSettingsSection()
        case .editor:
            EditorSettingsSection()
        case .keyboard:
            KeyboardSettingsSection()
        case .privacy:
            PrivacySettingsSection()
        case .about:
            AboutSettingsSection()
        default:
            PlaceholderSection(section: selected)
        }
    }
}

// MARK: – Sidebar row

private struct SettingsSidebarRow: View {
    @Environment(\.palette) private var p
    let section: SettingsSectionID
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(skoga: section.icon).skogaIconSize(13)
                    .foregroundStyle(selected ? p.forest : p.inkMute)
                    .frame(width: 16)
                Text(section.title)
                    .font(SkogaFont.body(12.5).weight(selected ? .medium : .regular))
                    .foregroundStyle(selected ? p.ink : p.ink2)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(selected ? p.paper4 : (hovering ? p.paper3 : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
