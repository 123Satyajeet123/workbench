import Foundation

public enum DealBoard {
    public struct Column: Equatable, Identifiable {
        public var stage: String
        public var deals: [WorkObject]

        public var id: String { stage }
    }

    public static func columns(of deals: [WorkObject], stages: [String]) -> [Column] {
        let unlisted = Set(deals.flatMap(\.stages)).subtracting(stages).sorted()
        return (stages + unlisted).map { stage in
            Column(stage: stage, deals: deals.filter { $0.stages.contains(stage) })
        }
    }
}
