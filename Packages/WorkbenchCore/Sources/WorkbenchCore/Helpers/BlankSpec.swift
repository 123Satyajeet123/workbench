import Foundation

extension HelperSpec {
    /// The task a blank spec carries until a machine is made from it; the store gives each machine its own.
    static let blankTask = "machine"

    /// The one field every fact of a blank machine has: the fact in the machine's own words.
    static let blankFactField = "text"

    /// A machine made from a source and a job in one sentence, and from nothing else. Each part is general: the
    /// brief is the job and the instructions that every spec gets; the one field states a fact whatever the source
    /// is; the cite and the quote that every fact has are checked by code from the source's citation mode; and no
    /// part is kept that only some jobs need: no lifecycle, criteria, nudge or followed machine. Nil when the job
    /// has no words.
    public init?(blankOver source: SourceDescriptor, job: String) {
        guard let job = job.cleaned else { return nil }
        self.init(
            task: Self.blankTask, source: source,
            brief: """
                You keep the facts of one job from what a source gives you. The job, in the person's words: \(job)

                Give one item for each fact in the lines that serves the job. Use only what a line says. A line that \
                does not serve the job gives no item.
                """,
            job: job,
            fields: [
                Field(
                    Self.blankFactField, .text(required: true),
                    meaning: "The fact, in one short line of plain words.")
            ],
            citation: source.citation, view: .table, title: Self.blankFactField, badges: [], tones: [:],
            itemsNoun: "facts", nudge: nil)
    }
}
