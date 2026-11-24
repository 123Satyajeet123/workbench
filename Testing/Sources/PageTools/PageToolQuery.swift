import Foundation

/// The numbers and lists the tools give, computed by code over the fixture. Pure: no I/O.
struct PageToolQuery {
    struct Filter {
        var field: String
        var values: [String]
    }

    let fixture: PageToolFixture
    let filters: [Filter]
    let groupBy: String?

    /// The fields a filter, a grouping or a `fields` list may name: the spec's fields and the day.
    var knownFields: [String] {
        (fixture.facts.first?.fields.map(\.name) ?? []) + [PageToolFixture.Fact.dayName]
    }

    /// The fields a `fields` list may name: those, and the exact words.
    var shownFields: [String] { knownFields + [PageToolFixture.Fact.quoteName] }

    /// Says which name is not among `known`, and which are.
    static func unknownFieldMessage(in names: [String], known: [String]) -> String? {
        guard let unknown = names.first(where: { !known.contains($0) }) else { return nil }
        return "Unknown field \"\(unknown)\". Known fields: \(known.joined(separator: ", "))."
    }

    var matching: [PageToolFixture.Fact] {
        fixture.facts.filter { fact in
            filters.allSatisfy { $0.values.isEmpty || $0.values.contains(fact.value(of: $0.field) ?? "") }
        }
    }

    /// The matching facts by the value of the grouping field, in the order the values first appear.
    var groups: [(value: String, facts: [PageToolFixture.Fact])] {
        guard let groupBy else { return [] }
        return matching.reduce(into: [(value: String, facts: [PageToolFixture.Fact])]()) { groups, fact in
            let value = fact.value(of: groupBy) ?? ""
            if let index = groups.firstIndex(where: { $0.value == value }) {
                groups[index].facts.append(fact)
            } else {
                groups.append((value, [fact]))
            }
        }
    }

    func count() -> [String: Any] {
        var answer: [String: Any] = ["total": matching.count]
        if groupBy != nil { answer["groups"] = groups.map { ["value": $0.value, "count": $0.facts.count] } }
        return answer
    }

    /// At most `limit` facts, each as its handle and the asked fields; the number that matched in all.
    func facts(fields: [String], limit: Int) -> (answer: [String: Any], handles: [String]) {
        let asked = fields.isEmpty ? knownFields : fields
        func shown(_ fact: PageToolFixture.Fact) -> [String: Any] {
            asked.reduce(into: ["handle": fact.handle] as [String: Any]) { row, name in
                row[name] = name == PageToolFixture.Fact.quoteName ? fact.quote : fact.value(of: name)
            }
        }
        var answer: [String: Any] = ["matched": matching.count]
        var handles: [String] = []
        if groupBy == nil {
            let facts = Array(matching.prefix(limit))
            handles = facts.map(\.handle)
            answer["shown"] = facts.count
            answer["facts"] = facts.map(shown)
        } else {
            var room = limit
            var shownGroups: [[String: Any]] = []
            for group in groups {
                let facts = Array(group.facts.prefix(room))
                room -= facts.count
                handles += facts.map(\.handle)
                shownGroups.append(["value": group.value, "matched": group.facts.count, "facts": facts.map(shown)])
            }
            answer["shown"] = handles.count
            answer["groups"] = shownGroups
        }
        return (answer, handles)
    }
}
