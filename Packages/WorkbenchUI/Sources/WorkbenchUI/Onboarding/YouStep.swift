import SwiftUI

struct YouStep: View {
    @Environment(OnboardingModel.self) private var model
    @FocusState private var isNameFocused: Bool

    var body: some View {
        @Bindable var identity = model.identityModel
        TextField("Your name", text: $identity.identity.name, prompt: Text("Your name"))
            .focused($isNameFocused)
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .onSubmit(model.next)
            .onAppear { isNameFocused = true }
    }
}
