//
//  StraightSetSequencer.swift
//  Workout App (iOS)
//
//  Where a strength session goes after a working set: stay on the exercise
//  while it has sets left, alternate between the members of a superset, then
//  the next exercise that isn't finished or skipped — wrapping round to one
//  the user jumped past. Pure, so the order can be tested without the view.
//

import Foundation

enum StraightSetSequencer {

    struct Entry: Equatable {
        let id: String
        let sets: Int
        let supersetGroup: Int?
    }

    enum Step: Equatable {
        /// Another set of the same exercise.
        case stay
        case move(to: Int)
        /// Nothing left: the session is done.
        case finish
    }

    /// - Parameters:
    ///   - current: index into `entries` of the exercise a set was just done for.
    ///   - done: working sets completed so far, per exercise id.
    ///   - skipped: exercises the user skipped; they count as finished.
    static func next(after current: Int, entries: [Entry], done: [String: Int], skipped: Set<String>) -> Step {
        guard entries.indices.contains(current) else { return .finish }

        func hasSetsLeft(_ index: Int) -> Bool {
            let entry = entries[index]
            return !skipped.contains(entry.id) && (done[entry.id] ?? 0) < entry.sets
        }

        if let group = entries[current].supersetGroup {
            // Round-robin through the superset, starting after this exercise.
            let members = entries.indices.filter { entries[$0].supersetGroup == group }
            if let position = members.firstIndex(of: current) {
                for offset in 1...members.count {
                    let candidate = members[(position + offset) % members.count]
                    if hasSetsLeft(candidate) {
                        return candidate == current ? .stay : .move(to: candidate)
                    }
                }
            }
        } else if hasSetsLeft(current) {
            return .stay
        }

        // The next unfinished exercise after this one, then any before it.
        let order = Array(entries.indices.dropFirst(current + 1)) + Array(entries.indices.prefix(current))
        if let target = order.first(where: hasSetsLeft) {
            return .move(to: target)
        }
        return .finish
    }
}
