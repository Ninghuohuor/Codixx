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
                                HStack(spacing: 6) {
                                    Text(threadTitle(thread))
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    if thread.isArchived {
                                        Text(strings.archivedThread)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Color(nsColor: .separatorColor).opacity(0.35),
                                                in: Capsule()
                                            )
                                    }
                                }
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

    private func threadTitle(_ thread: ThreadUsage) -> String {
        let title = thread.title.isEmpty ? thread.id : thread.title
        if let projectName = projectFolderName(from: thread.cwd) {
            return "\(projectName) - \(title)"
        }
        return title
    }

    private func projectFolderName(from cwd: String) -> String? {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: trimmed, isDirectory: true)
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? trimmed : name
    }
}
