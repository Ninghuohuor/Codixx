import SwiftUI
import CodixxCore

struct ThreadRankingView: View {
    var threads: [ThreadUsage]
    var strings: CodixxStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(strings.topThreads)
                .font(.headline)

            if threads.isEmpty {
                Text(strings.noThreadUsageYet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 6) {
                    ForEach(threads, id: \.id) { thread in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(thread.title.isEmpty ? thread.id : thread.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text("\(thread.model) / \(thread.reasoningEffort)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(thread.tokensUsed.formatted()) \(strings.tokens)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}
