import SwiftUI

/// "It said it logged the set."
///
/// A write that does not land has to come and find you, for the same reason
/// the legacy-data banner does: the alternative is trusting a screen that is
/// quietly wrong. This one is worse than stale numbers, though — it is the
/// difference between a set you did and a set the app has, and you will not
/// find out until the next time you look for it.
///
/// Sits over every tab rather than on one screen, because the save it is
/// reporting could have come from any of them.
struct SaveFailureBanner: View {
    @EnvironmentObject private var saves: Saves

    var body: some View {
        if let failure = saves.failure {
            VStack(alignment: .leading, spacing: RFDesign.sm) {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.icloud.fill")
                        .font(.system(size: 12))
                    Text("That didn't save")
                        .font(RFDesign.ui(14, bold: true))
                    Spacer(minLength: 8)
                    Button { saves.acknowledge() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(RFDesign.labelDim)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(RFDesign.ember)

                // The gerund completes the sentence, which is why `what` is
                // written the way it is at every call site.
                Text(message(for: failure))
                    .font(RFDesign.ui(13))
                    .foregroundStyle(RFDesign.label)
                    .fixedSize(horizontal: false, vertical: true)

                Text(failure.reason)
                    .font(RFDesign.ui(11.5))
                    .foregroundStyle(RFDesign.labelDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(RFDesign.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RFDesign.ember.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: RFDesign.radiusSmall))
            .overlay {
                RoundedRectangle(cornerRadius: RFDesign.radiusSmall)
                    .stroke(RFDesign.ember.opacity(0.35), lineWidth: 1)
            }
            .padding(.horizontal, RFDesign.md)
            .accessibilityIdentifier("save-failure-banner")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func message(for failure: Saves.Failure) -> String {
        let others = saves.failures.count - 1
        let tail = others > 0
            ? " \(others) other change\(others == 1 ? "" : "s") didn't save either."
            : ""
        return "Your change while \(failure.what) is not stored — it will be gone "
             + "when you close the app.\(tail)"
    }
}
