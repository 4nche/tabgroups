import SwiftUI

struct UnmatchedWindowView: View {
    let members: [(group: TabGroup, member: WindowReference)]
    let candidates: [DiscoveredWindow]
    let onAssign: (UUID, String) -> Void
    let onRemove: (UUID, UUID) -> Void

    var body: some View {
        if !members.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved tabs to reconnect")
                    .font(.headline)
                ForEach(members.indices, id: \.self) { index in
                    let item = members[index]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.member.title ?? item.member.bundleIdentifier)
                                .lineLimit(1)
                            Text(item.member.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Menu("Assign") {
                            if candidates.isEmpty {
                                Text("No accessible windows found")
                            }
                            ForEach(candidates) { candidate in
                                Button("\(candidate.appName) — \(candidate.reference.title ?? "Window")") {
                                    onAssign(item.member.id, candidate.id)
                                }
                            }
                        }
                        Button(role: .destructive) {
                            onRemove(item.group.id, item.member.id)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Remove saved tab")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
