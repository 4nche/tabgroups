import Foundation

/// What a Shift-drag drop does, given which groups the two windows already belong to.
enum DropPlan {
    enum Action: Equatable {
        case createGroup
        case addSource(toGroup: UUID)
        case addTarget(toGroup: UUID)
        case merge(group: UUID, into: UUID)
        case nothing
    }

    static func action(sourceGroup: UUID?, targetGroup: UUID?) -> Action {
        switch (sourceGroup, targetGroup) {
        case (nil, nil): return .createGroup
        case (nil, let target?): return .addSource(toGroup: target)
        case (let source?, nil): return .addTarget(toGroup: source)
        case (let source?, let target?): return source == target ? .nothing : .merge(group: source, into: target)
        }
    }
}

/// Tells a window being dragged from one being resized, which also shifts its origin.
enum DragMotion: Equatable {
    case still, moved, resized

    static let moveThreshold: Double = 8

    static func classify(from start: WindowBounds, to now: WindowBounds) -> DragMotion {
        let resize = abs(now.width - start.width) + abs(now.height - start.height)
        if resize > GroupGeometry.tolerance { return .resized }
        let travel = abs(now.x - start.x) + abs(now.y - start.y)
        return travel > moveThreshold ? .moved : .still
    }
}
