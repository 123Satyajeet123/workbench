import Foundation

/// The deals laid out in columns, one per stage.
public enum DealBoard {
    public struct Column: Equatable, Identifiable {
        public var stage: String
        public var deals: [WorkObject]

        public var id: String { stage }
    }

    /// One column for each listed stage, in order, then one for every other stage a deal stands in (a stage a
    /// teammate typed, or one an older version used), so no deal drops off the board. A deal with two standing
    /// stages shows in both.
    public static func columns(of deals: [WorkObject], stages: [String]) -> [Column] {
        let unlisted = Set(deals.flatMap(\.stages)).subtracting(stages).sorted()
        return (stages + unlisted).map { stage in
            Column(stage: stage, deals: deals.filter { $0.stages.contains(stage) })
        }
    }
}
