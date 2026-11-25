import SwiftUI

struct TabStripView: View {
    let group: TabGroup
    let windowTitles: [UUID: (app: String, title: String)]
    let onSelect: (UUID) -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(group.members) { member in
                let labels = windowTitles[member.id]
                HStack(spacing: 7) {
                    Image(systemName: member.id == group.selectedMemberID ? "circle.fill" : "circle")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(member.id == group.selectedMemberID ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(labels?.app ?? member.bundleIdentifier)
                            .font(.system(size: 10, weight: .semibold))
                        Text(labels?.title ?? member.title ?? "Window")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Button {
                        onRemove(member.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Remove tab")
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(member.id == group.selectedMemberID ? Color.accentColor.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .onTapGesture { onSelect(member.id) }
                .gesture(DragGesture(minimumDistance: 10).onEnded { gesture in
                    if abs(gesture.translation.width) > 70 || abs(gesture.translation.height) > 70 {
                        onRemove(member.id)
                    }
                })
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12)))
        .fixedSize(horizontal: true, vertical: true)
    }
}
