import Foundation

/// A thing a person can set up from the gallery with one click: the folder it makes, the machine it starts, and the
/// first blocks of the machine's page. It is data only. The filing API makes the folder and the page; the blocks use
/// the kinds of the page's block catalog (research 76 §4.3, §4.10).
public struct GalleryTemplate: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    /// An SF Symbol name. Only Mochi has a face.
    public let icon: String
    /// What it gives the person, in one line.
    public let detail: String
    public let folder: FolderStart
    /// The machine it starts. Nil when the template only sets up a folder for work the person starts by hand.
    public let machine: MachineTemplate?
    /// The page's header: the job, in one sentence.
    public let job: String
    public let blocks: [StartBlock]
    /// What the app must have before this template can be set up. Empty: it can be set up now.
    public let needs: Set<Need>

    public init(
        id: String, name: String, icon: String, detail: String, folder: FolderStart, machine: MachineTemplate?,
        job: String, blocks: [StartBlock], needs: Set<Need> = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.detail = detail
        self.folder = folder
        self.machine = machine
        self.job = job
        self.blocks = blocks
        self.needs = needs
    }

    /// The gallery template of this id. A machine template with no gallery entry of its own gives a plain one: its
    /// source's picker and its facts, in the general folder.
    public static func of(id: String) -> GalleryTemplate? {
        all.first { $0.id == id } ?? MachineTemplate.of(id: id).map(plain)
    }

    static func plain(_ machine: MachineTemplate) -> GalleryTemplate {
        let kind = machine.spec.source.kind
        return GalleryTemplate(
            id: machine.id, name: machine.name, icon: "gearshape", detail: machine.detail,
            folder: FolderStart(name: generalFolder), machine: machine, job: machine.detail,
            blocks: (StartBlock.pickable.contains(kind) ? [.picker(kind)] : []) + [
                .facts(task: machine.id, view: "table")
            ])
    }

    /// The folder that holds a machine made from the machine template `template` when no folder is named.
    public static func folder(forMachine template: String) -> FolderStart {
        of(id: template)?.folder ?? FolderStart(name: generalFolder)
    }

    public static let generalFolder = "General"

    /// The folder a template makes: its name, and the type of the objects it holds (nil for a plain folder).
    public struct FolderStart: Sendable, Equatable {
        public let name: String
        public let holds: TypeID?

        public init(name: String, holds: TypeID? = nil) {
            self.name = name
            self.holds = holds
        }
    }

    /// A first block of the page, from the page's block catalog.
    public enum StartBlock: Sendable, Equatable {
        /// The person chooses what the machine may read. The person's click is the grant; the block holds only the
        /// kind of source.
        case picker(SourceKind)
        /// A value of the machine's spec that the person sets on the page.
        case input(SetupQuestion.Kind)
        /// The facts of one task, in one of the views its spec can fill (`HelperSpec.views`).
        case facts(task: String, view: String)

        /// Whether the block waits for the person's act.
        public var isPrompt: Bool {
            switch self {
            case .picker, .input: true
            case .facts: false
            }
        }

        /// The kinds of source a person can choose on a page: a chat or group, a mail label, sites, files.
        public static let pickable: Set<SourceKind> = [.whatsapp, .mail, .screenText, .dropped]
    }

    public enum Need: String, Sendable, Hashable {
        /// A model with tools that looks things up for the person (I1).
        case taskRunner

        public var words: String {
            switch self {
            case .taskRunner: "a model with tools"
            }
        }
    }

    /// The blocks that wait for the person: the pickers and the inputs.
    public var prompts: [StartBlock] { blocks.filter(\.isPrompt) }

    /// The machine's spec showing its facts in the view the template names. A view the spec cannot fill leaves it as it
    /// is; `problems` reports that.
    func defaultView(of spec: HelperSpec) -> HelperSpec {
        var spec = spec
        for case .facts(let task, let view) in blocks where task == spec.task {
            spec.view = spec.views[view] ?? spec.view
        }
        return spec
    }

    /// Why this template's data does not hold together, or an empty list. A picker must ask for the source its machine
    /// reads; a facts view must be one the machine's spec can fill; an input must be a value the spec has.
    public var problems: [String] {
        var problems: [String] = []
        let spec = machine?.spec
        for block in blocks {
            switch block {
            case .picker(let kind):
                if let spec, spec.source.kind != kind {
                    problems.append("picker asks for \(kind.rawValue), the machine reads \(spec.source.kind.rawValue)")
                }
            case .input(let kind):
                if spec.map({ spec in !spec.settingValues.contains { $0.kind == kind } }) ?? true {
                    problems.append("input \(kind.rawValue) is not a value of the machine")
                }
            case .facts(let task, let view):
                if let spec, spec.task == task, spec.views[view] == nil {
                    problems.append("view \(view) is not one the machine can fill")
                }
            }
        }
        return problems
    }
}
