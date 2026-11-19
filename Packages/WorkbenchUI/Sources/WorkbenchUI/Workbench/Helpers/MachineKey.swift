import Foundation
import LocalSources
import WorkbenchCore

/// The store keys of one machine's settings, named by its task. These names are in founders' stores already.
enum MachineKey {
    static func nudge(_ task: String) -> StateKey<NudgeSchedule> { .json("\(task).nudge") }
    /// The last day a nudge went out.
    static func nudged(_ task: String) -> StateKey<WorkDay> { .day("\(task).nudged") }
    static func watch(_ task: String) -> StateKey<WatchSchedule> { .json("\(task).watch") }
    /// The last time the reading hours read.
    static func watched(_ task: String) -> StateKey<Date> { .moment("\(task).watched") }
    /// The last line a reading of `day` saw.
    static func lastLine(_ task: String, scope: String, day: WorkDay) -> StateKey<Int64> {
        .text("\(task).read.\(scope).\(day)")
    }
    static func trial(_ task: String) -> StateKey<SavedTrial> { .json("\(task).trial") }
    static func sites(_ task: String) -> StateKey<[String]> { .json("\(task).sites") }
    static func chats(_ task: String) -> StateKey<[WhatsAppChat]> { .json("\(task).chats") }
    static func members(_ task: String) -> StateKey<[WhatsAppMember]> { .json("\(task).members") }
    /// The version a drift warning was given for.
    static func drift(_ task: String) -> StateKey<String> { .text("\(task).drift") }
}
