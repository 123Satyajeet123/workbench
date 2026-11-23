import Foundation
import WorkbenchCore

extension PlanLimits {
    public static func last(inClaude stdout: String, at now: Date) -> PlanLimits? {
        stdout.split(separator: "\n").reversed().lazy.compactMap { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                object["type"] as? String == "rate_limit_event",
                let info = object["rate_limit_info"] as? [String: Any]
            else { return nil }
            let windows =
                info["unifiedWindows"] as? [String: [String: Any]]
                ?? (info["rateLimitType"] as? String).map { [$0: info] } ?? [:]
            let limits = PlanLimits(
                fiveHour: windows["five_hour"].flatMap(window), week: windows["seven_day"].flatMap(window), at: now)
            return limits.fiveHour == nil && limits.week == nil ? nil : limits
        }.first
    }

    private static func window(_ value: [String: Any]) -> Window? {
        guard let used = (value["utilization"] as? NSNumber)?.doubleValue, used >= 0 else { return nil }
        return Window(
            used: used,
            resetsAt: (value["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
            isAtLimit: value["status"] as? String == "rejected")
    }
}
