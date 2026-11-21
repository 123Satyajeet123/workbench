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
    /// The weekly search of an outbound machine, and the last time it ran.
    static func weekly(_ task: String) -> StateKey<WeeklySearch> { .json("\(task).weekly") }
    static func weeklyRan(_ task: String) -> StateKey<Date> { .moment("\(task).weeklyRan") }
    /// The last line a reading of `day` saw.
    static func lastLine(_ task: String, scope: String, day: WorkDay) -> StateKey<Int64> {
        .text("\(task).read.\(scope).\(day)")
    }
    /// The last day a machine that follows another read, with or without new lines.
    static func followedRead(_ task: String) -> StateKey<WorkDay> { .day("\(task).followedRead") }
    static func trial(_ task: String) -> StateKey<SavedTrial> { .json("\(task).trial") }
    static func sites(_ task: String) -> StateKey<[String]> { .json("\(task).sites") }
    static func chats(_ task: String) -> StateKey<[WhatsAppChat]> { .json("\(task).chats") }
    static func members(_ task: String) -> StateKey<[WhatsAppMember]> { .json("\(task).members") }
    /// The past deals with the investor's own calls: the held-out set, kept apart from every item.
    static func agreement(_ task: String) -> StateKey<[PastDeal]> { .json("\(task).agreement") }
    /// The version a drift warning was given for.
    static func drift(_ task: String) -> StateKey<String> { .text("\(task).drift") }
}
