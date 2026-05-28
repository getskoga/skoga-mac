import SwiftUI

/// Settings → About. Carries the version / build / daemon-protocol
/// roadmap until those land, plus the hidden "Re-run first-run" entry
/// the issue calls for — surfaced under About so users (and QA) can
/// re-trigger the wizard after completion or after skipping midway.
struct AboutSettingsSection: View {
    @Environment(\.palette) private var p
    @Environment(OnboardingState.self) private var onboarding

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            roadmapCard
            rerunCard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(skoga: SettingsSectionID.about.icon).skogaIconSize(15)
                    .foregroundStyle(p.ink2)
                Text(SettingsSectionID.about.title)
                    .font(SkogaFont.serifTitle(24))
                    .foregroundStyle(p.ink)
            }
            Text(SettingsSectionID.about.blurb)
                .font(SkogaFont.body(13))
                .foregroundStyle(p.inkMute)
                .lineSpacing(13 * 0.45)
                .frame(maxWidth: 540, alignment: .leading)
        }
    }

    /// Same shape as `PlaceholderSection`'s roadmap card so About stays
    /// visually consistent with the unimplemented panels until version /
    /// build / protocol fields land.
    private var roadmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("SHIPPING NEXT")
                    .font(SkogaFont.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(p.inkFaint)
                Spacer()
                Text("v1 roadmap")
                    .font(SkogaFont.monoTiny(9.5))
                    .tracking(0.8)
                    .foregroundStyle(p.amber)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.tiny)
                            .stroke(p.amber.opacity(0.45), lineWidth: Tokens.Hairline.width)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(SettingsSectionID.about.roadmap, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .stroke(p.rule, lineWidth: Tokens.Hairline.width)
                            .fill(p.paper)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(item)
                            .font(SkogaFont.body(12.5))
                            .foregroundStyle(p.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(16)
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    /// Hidden re-run entry. Visible from About but not promoted in the
    /// sidebar — its purpose is to give the user (and QA) a way to
    /// retrigger the wizard after they completed or skipped midway, per
    /// the issue's "hidden Settings · About entry for testing" note.
    private var rerunCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("FIRST-RUN WIZARD")
                    .font(SkogaFont.mono(10))
                    .tracking(1.0)
                    .foregroundStyle(p.inkFaint)
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                Image(skoga: .loop).skogaIconSize(13)
                    .foregroundStyle(p.ink2)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Re-run onboarding")
                        .font(SkogaFont.bodyMedium(13))
                        .foregroundStyle(p.ink)
                    Text("Drops you back on the welcome card with your previous picks (default model, sandbox carveouts, workspace, etc.) pre-filled.")
                        .font(SkogaFont.body(12))
                        .foregroundStyle(p.inkMute)
                        .lineSpacing(12 * 0.5)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        onboarding.restart()
                    } label: {
                        HStack(spacing: 6) {
                            Image(skoga: .loop).skogaIconSize(11)
                            Text("Re-run first-run").font(SkogaFont.bodyMedium(12))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .foregroundStyle(p.ink2)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                                .fill(p.paper)
                                .hairlineBorder(p.rule, radius: Tokens.Radius.chip)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(p.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .stroke(p.rule, lineWidth: Tokens.Hairline.width)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }
}
