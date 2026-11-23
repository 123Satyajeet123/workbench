import Foundation

/// The objects of one type laid out in columns, one per stage.
public enum ObjectBoard {
    public struct Column: Equatable, Identifiable {
        public var stage: StageDef
        public var objects: [WorkObject]

        public var id: StageID { stage.id }
    }

    /// One column for each stage of the type, in order, then one for every other stage an object stands in, so no
    /// object drops off the board. A retired stage shows only while an object stands in it. An object with two
    /// standing stages shows in both.
    public static func columns(of objects: [WorkObject], type: ObjectType) -> [Column] {
        let standing = Set(objects.flatMap(\.stages))
        let listed = type.orderedStages.filter { !$0.retired || standing.contains($0.id) }
        let unlisted = standing.subtracting(type.stages.map(\.id)).sorted().map(type.resolveStage)
        return (listed + unlisted).map { stage in
            Column(stage: stage, objects: objects.filter { $0.stages.contains(stage.id) })
        }
    }
}
