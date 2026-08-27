import SwiftUI
import SwiftData

/// "I still see random data in Trends."
///
/// The fix that stopped the app inventing six weeks of history only stopped it
/// happening again. Rows already written were never tagged `.demo`, so nothing
/// labelled them and the only way out was a Settings screen you had no reason
/// to open. Invented numbers on a chart with your name on it should come and
/// find you, not wait to be discovered.
///
/// Shown once, on Today and on Trends, until it is answered either way.
struct LegacyDataBanner: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var snapshots: SnapshotService

    @AppStorage("history.legacyAcknowledged") private var acknowledged = false
    @Query private var sets: [SetEntry]
    @Query private var weighIns: [WeighIn]

    private var total: Int { sets.count + weighIns.count }
    /// Untagged history is history from before tagging existed — which is to
    /// say, the seeded kind.
    private var untagged: Bool {
        !sets.contains(where: \.isDemo) && !weighIns.contains(where: \.isDemo)
    }
    private var shouldShow: Bool { !acknowledged && total > 0 && untagged }

    var body: some View {
        if shouldShow {
            VStack(alignment: .leading, spacing: RFDesign.sm) {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text("Some of this isn't yours")
                        .font(RFDesign.ui(14, bold: true))
                }
                .foregroundStyle(RFDesign.ember)

                Text("An earlier build seeded \(total) sample entries so the charts "
                     + "would have a shape. They were never marked, so they can't be "
                     + "picked out one by one — clearing starts you at zero. "
                     + "Your plan and passes are kept.")
                    .font(RFDesign.ui(13))
                    .foregroundStyle(RFDesign.label)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 9) {
                    Button {
                        reportingFailure("clearing the sample data") {
                            try Seed.deleteAllHistory(context)
                        }
                        acknowledged = true
                        snapshots.setNeedsWrite(context)
                    } label: {
                        Text("Clear \(total) entries")
                            .font(RFDesign.ui(14, bold: true))
                            .foregroundStyle(RFDesign.ground)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(RFDesign.ember,
                                        in: RoundedRectangle(cornerRadius: RFDesign.radiusSmall))
                    }
                    .buttonStyle(.plain)

                    Button {
                        // Deliberately possible: some of it may be real sets he
                        // logged today, and deleting those to fix a labelling
                        // problem would be the worse mistake.
                        acknowledged = true
                    } label: {
                        Text("Keep it")
                            .font(RFDesign.ui(14))
                            .foregroundStyle(RFDesign.label)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(RFDesign.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RFDesign.ember.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: RFDesign.radiusSmall))
            .overlay {
                RoundedRectangle(cornerRadius: RFDesign.radiusSmall)
                    .stroke(RFDesign.ember.opacity(0.35), lineWidth: 1)
            }
        }
    }
}
