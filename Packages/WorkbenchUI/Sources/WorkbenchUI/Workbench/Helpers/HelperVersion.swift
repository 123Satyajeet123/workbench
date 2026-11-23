import WorkbenchCore

extension HelperModel {
    /// What a trial changes: the brief, the example policy and the model, together. Trust is earned per version.
    struct Version: Equatable {
        var brief: String
        var examples: Int?
        var runner: String?

        init(brief: String, examples: Int?, runner: String?) {
            self.brief = brief
            self.examples = examples
            self.runner = runner
        }

        init(_ spec: HelperSpec) { self.init(brief: spec.brief, examples: spec.examples, runner: spec.runner) }

        init(decision: Decision) {
            self.init(
                brief: decision.brief, examples: Int(decision.detail["examples", default: ""]),
                runner: decision.detail["runner"].flatMap(\.cleaned))
        }

        init(parentOf decision: Decision) {
            self.init(
                brief: decision.parentBrief, examples: Int(decision.detail["parentExamples", default: ""]),
                runner: decision.detail["parentRunner"].flatMap(\.cleaned))
        }

        func apply(to spec: HelperSpec) -> HelperSpec {
            var spec = spec
            spec.brief = brief
            spec.examples = examples
            spec.runner = runner
            return spec
        }

        func detail(parent: Version) -> [String: String] {
            [
                "examples": examples.map(String.init) ?? "", "parentExamples": parent.examples.map(String.init) ?? "",
                "runner": runner ?? "", "parentRunner": parent.runner ?? "",
            ]
        }
    }
}
