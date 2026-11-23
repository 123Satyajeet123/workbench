import Foundation
import LocalSources
import TelegramReader
import WorkbenchCore

enum MachineKey {
    static func nudge(_ task: String) -> StateKey<NudgeSchedule> { .json("\(task).nudge") }
    static func nudged(_ task: String) -> StateKey<WorkDay> { .day("\(task).nudged") }
    static func watch(_ task: String) -> StateKey<WatchSchedule> { .json("\(task).watch") }
    static func watched(_ task: String) -> StateKey<Date> { .moment("\(task).watched") }
    static func lastLine(_ task: String, scope: String, day: WorkDay) -> StateKey<Int64> {
        .text("\(task).read.\(scope).\(day)")
    }
    static func followedRead(_ task: String) -> StateKey<WorkDay> { .day("\(task).followedRead") }
    static func trial(_ task: String) -> StateKey<SavedTrial> { .json("\(task).trial") }
    static func sites(_ task: String) -> StateKey<[String]> { .json("\(task).sites") }
    static func chats(_ task: String) -> StateKey<[WhatsAppChat]> { .json("\(task).chats") }
    static func everyChat(_ task: String) -> StateKey<Bool> { .onOff("\(task).everyChat") }
    static func members(_ task: String) -> StateKey<[WhatsAppMember]> { .json("\(task).members") }
    static func telegramChat(_ task: String) -> StateKey<TelegramChat> { .json("\(task).telegram.chat") }
    static func telegramConsent(_ task: String) -> StateKey<TelegramConsent> { .json("\(task).telegram.consent") }
    static func agreement(_ task: String) -> StateKey<[PastDeal]> { .json("\(task).agreement") }
    static func drift(_ task: String) -> StateKey<String> { .text("\(task).drift") }
}
