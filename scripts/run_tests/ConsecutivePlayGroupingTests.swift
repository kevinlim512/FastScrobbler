import Foundation

func runConsecutivePlayGroupingTests() {
    section("Consecutive play grouping")

    struct FakeEntry: Equatable {
        let id: Int
        let source: String
        let key: String
    }

    func grouped(_ entries: [FakeEntry]) -> [ConsecutivePlayGrouper.Group<FakeEntry, Int>] {
        ConsecutivePlayGrouper.groups(
            from: entries,
            shouldGroup: { _ in true },
            dedupeKey: { "\($0.source):\($0.key)" },
            memberID: { $0.id }
        )
    }

    let consecutive = grouped([
        FakeEntry(id: 1, source: "playbackHistory", key: "song-a"),
        FakeEntry(id: 2, source: "playbackHistory", key: "song-a"),
        FakeEntry(id: 3, source: "playbackHistory", key: "song-a"),
        FakeEntry(id: 4, source: "live", key: "song-b")
    ])
    expectEqual("consecutive repeats collapse into one group", consecutive.map(\.count), [3, 1])
    expectEqual("grouped runs keep the newest row as representative", consecutive.first?.representative.id, 1)
    expectEqual("grouped runs retain all underlying IDs", consecutive.first?.memberIDs ?? [], [1, 2, 3])

    let separated = grouped([
        FakeEntry(id: 10, source: "playbackHistory", key: "song-a"),
        FakeEntry(id: 11, source: "live", key: "song-a"),
        FakeEntry(id: 12, source: "playbackHistory", key: "song-a")
    ])
    expectEqual("non-consecutive repeats do not collapse across other rows", separated.map(\.count), [1, 1, 1])

    let mixedSources = grouped([
        FakeEntry(id: 20, source: "playbackHistory", key: "song-a"),
        FakeEntry(id: 21, source: "recentlyPlayed", key: "song-a"),
        FakeEntry(id: 22, source: "recentlyPlayed", key: "song-a"),
        FakeEntry(id: 23, source: "playbackHistory", key: "song-a")
    ])
    expectEqual("different sources break grouping while identical consecutive sources group together", mixedSources.map(\.count), [1, 2, 1])

    let reviewScoped = grouped([
        FakeEntry(id: 30, source: "playbackHistory", key: "song-a"),
        FakeEntry(id: 31, source: "playbackHistory", key: "song-a"),
        FakeEntry(id: 32, source: "recentlyPlayed", key: "song-b"),
        FakeEntry(id: 33, source: "recentlyPlayed", key: "song-b")
    ])
    expectEqual("both playbackHistory and recentlyPlayed sources group when consecutive", reviewScoped.map(\.count), [2, 2])

    section("Consecutive play selection")

    let selectedOnce = ConsecutivePlayGrouper.toggleSelection(for: [40, 41, 42], in: [])
    expectEqual("group selection expands to all underlying IDs", selectedOnce, Set([40, 41, 42]))
    expect("fully selected groups report selected state", ConsecutivePlayGrouper.isFullySelected(memberIDs: [40, 41, 42], selectedIDs: selectedOnce))

    let selectedTwice = ConsecutivePlayGrouper.toggleSelection(for: [40, 41, 42], in: selectedOnce)
    expectEqual("tapping an already-selected group clears all underlying IDs", selectedTwice, Set<Int>())

    let remainingIDs = [40, 41, 42, 50].filter { !selectedOnce.contains($0) }
    expectEqual("deleting a grouped selection removes every underlying pending entry", remainingIDs, [50])

    section("Consecutive play limits")

    let limitedEntries = (0..<50).map { index in
        FakeEntry(id: index, source: "playbackHistory", key: "song-a")
    }
    let limitedGroups = grouped(limitedEntries)
    expectEqual("grouping runs after the existing 50-entry fetch limit", limitedEntries.count, 50)
    expectEqual("grouping preserves all fetched members even when rows collapse", limitedGroups.flatMap(\.memberIDs).count, 50)
}
