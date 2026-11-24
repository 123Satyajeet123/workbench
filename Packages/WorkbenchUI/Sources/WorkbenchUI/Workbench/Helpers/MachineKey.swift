import Foundation
import LocalSources
import TelegramReader
import WorkbenchCore

/// The store keys of one machine's settings, named by its task. These names are in founders' stores already.
enum MachineKey {
    static func nudge(_ task: String) -> StateKey<NudgeSchedule> { .json("\(task).nudge") }
    static func nudged(_ task: String) -> StateKey<WorkDay> { .day("\(task).nudged") }
    static func watch(_ task: String) -> StateKey<WatchSchedule> { .json(WatchSchedule.stateKey(of: task)) }
    static func watched(_ task: String) -> StateKey<Date> { .moment(WatchSchedule.lastReadKey(of: task)) }
    /// The weekly search of an outbound machine, and the last time it ran.
    static func weekly(_ task: String) -> StateKey<WeeklySearch> { .json("\(task).weekly") }
    static func weeklyRan(_ task: String) -> StateKey<Date> { .moment("\(task).weeklyRan") }
    /// The last day a machine that follows another read, with or without new lines.
    static func followedRead(_ task: String) -> StateKey<WorkDay> { .day("\(task).followedRead") }
    static func trial(_ task: String) -> StateKey<SavedTrial> { .json("\(task).trial") }
    static func sites(_ task: String) -> StateKey<[String]> { .json("\(task).sites") }
    static func chats(_ task: String) -> StateKey<[WhatsAppChat]> { .json("\(task).chats") }
    static func everyChat(_ task: String) -> StateKey<Bool> { .onOff("\(task).everyChat") }
    static func members(_ task: String) -> StateKey<[WhatsAppMember]> { .json("\(task).members") }
    static func telegramChat(_ task: String) -> StateKey<TelegramChat> { .json("\(task).telegram.chat") }
    static func telegramConsent(_ task: String) -> StateKey<TelegramConsent> { .json("\(task).telegram.consent") }
    /// The past deals with the investor's own calls: the held-out set, kept apart from every item.
    static func agreement(_ task: String) -> StateKey<[PastDeal]> { .json("\(task).agreement") }
    static func drift(_ task: String) -> StateKey<String> { .text("\(task).drift") }
}
