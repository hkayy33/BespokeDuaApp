import SwiftUI

/// White card with log out — matches account drawer styling.
struct BespokeAccountActionsCard: View {
    let onLogout: () -> Void

    var body: some View {
        Button(action: onLogout) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18, weight: .medium))

                Text("Log out")
                    .font(BespokeFont.inter(16, weight: .semibold))
            }
            .foregroundStyle(BespokeColor.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(BespokePlainButtonStyle())
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

enum BespokeSubscriptionDisplay {
    static func planTitle(plan: String, isSubscribed: Bool) -> String {
        if isSubscribed {
            return "Bespoke Plus"
        }
        let trimmed = plan.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("free") == .orderedSame {
            return "Free Plan"
        }
        if trimmed.lowercased().hasSuffix("plan") {
            return trimmed
        }
        return "\(trimmed) Plan"
    }
}

enum BespokePlusFeatures {
    static let items = [
        "Zero daily limits",
        "Organise saved duas into collections",
        "Access to Dua Feed",
    ]

    static let footer = "& more"
}

struct BespokePlusFeaturesList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(BespokePlusFeatures.items, id: \.self) { feature in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(BespokeFont.inter(13, weight: .bold))
                        .foregroundStyle(BespokeColor.nameGold)
                    Text(feature)
                        .font(BespokeFont.inter(13, weight: .regular))
                        .foregroundStyle(BespokeColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(BespokePlusFeatures.footer)
                .font(BespokeFont.inter(13, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .padding(.leading, 16)
        }
    }
}

struct BespokePlusUpgradeCard: View {
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                Text("Bespoke Plus")
                    .font(BespokeFont.inter(16, weight: .semibold))
            }
            .foregroundStyle(BespokeColor.forest)

            BespokePlusFeaturesList()

            Button(action: onUpgrade) {
                Text("Upgrade to Bespoke Plus")
                    .font(BespokeFont.inter(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LinearGradient.bespokeGold)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .bespokeButtonHitArea(cornerRadius: 14)
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(BespokePlainButtonStyle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}
