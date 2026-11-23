import SwiftUI
import WorkbenchCore

/// A sheet that adds a fact by hand. The words come first, then who, which project and when. Return adds it, Escape closes.
struct AddFactSheet: View {
    let model: AddFactModel
    let close: () -> Void
    @FocusState private var focused: Bool
    @State private var picksDay = false
    @State private var pickedDay = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            TextField("What is true, or must happen?", text: Bindable(model).words, axis: .vertical)
                .textFieldStyle(.plain)
                .textStyle(.title3)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit(add)
            Divider()
            HStack(spacing: Space.s) {
                Picker("Kind", selection: Bindable(model).kind) {
                    ForEach(model.kinds, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                personField
                TextField("Project", text: Bindable(model).project).textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                dueMenu
            }
            if let problem = model.problem { Text(problem).text(.caption) }
            HStack {
                Spacer()
                Button(action: close) {
                    HStack {
                        Text("Cancel")
                        KeyHint("esc")
                    }
                }
                .buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button(action: add) {
                    HStack {
                        Text("Add")
                        KeyHint("↩")
                    }
                }
                .buttonStyle(.primary).disabled(!model.canAdd)
            }
        }
        .padding(Space.l)
        .frame(width: 520)
        .background(.pageFill)
        .onAppear { focused = true }
    }

    private var personField: some View {
        HStack(spacing: Space.xs) {
            TextField("Person", text: Bindable(model).person).textFieldStyle(.roundedBorder).frame(maxWidth: 140)
            if !model.people.isEmpty {
                Menu {
                    ForEach(model.people, id: \.self) { name in Button(name) { model.person = name } }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
    }

    private var dueMenu: some View {
        Menu(model.due.title) {
            ForEach(DueChoice.quick, id: \.self) { choice in Button(choice.title) { model.due = choice } }
            Divider()
            Button("Pick a day") { picksDay = true }
        }
        .menuStyle(.borderlessButton).fixedSize()
        .popover(isPresented: $picksDay) {
            DatePicker("", selection: $pickedDay, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                .padding(Space.m)
                .onChange(of: pickedDay) {
                    model.due = .day(WorkDay(containing: pickedDay))
                    picksDay = false
                }
        }
    }

    private func add() {
        if model.submit() { close() }
    }
}
