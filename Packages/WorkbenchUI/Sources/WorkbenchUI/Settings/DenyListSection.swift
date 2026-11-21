import SwiftUI

struct DenyListSection: View {
    @Environment(CaptureSettings.self) private var capture
    @State private var typed = ""
    @State private var notFound = false

    var body: some View {
        Section {
            ForEach(capture.denyList) { place in
                LabeledContent(place.name) {
                    Button("Remove \(place.name)", systemImage: "minus.circle") { capture.allow(place) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.ghost)
                }
            }
            TextField("Add", text: $typed, prompt: Text("App name or website"))
                .onSubmit {
                    notFound = !capture.deny(typed)
                    if !notFound { typed = "" }
                }
                .onChange(of: typed) { notFound = false }
        } header: {
            Text("Never capture")
        } footer: {
            FormNote(
                notFound
                    ? "“\(typed)” is not an installed app or a website."
                    : "Always private, whatever this list says: \(CaptureSettings.alwaysPrivate).")
        }
    }
}
