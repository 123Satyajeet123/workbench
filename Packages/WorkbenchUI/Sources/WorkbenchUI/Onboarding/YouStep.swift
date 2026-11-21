import SwiftUI

struct YouStep: View {
    @Environment(OnboardingModel.self) private var model
    @FocusState private var isNameFocused: Bool

    var body: some View {
        @Bindable var identity = model.identityModel
        TextField("Your name", text: $identity.identity.name, prompt: Text("Your name"))
            .textFieldStyle(.plain)
            .textStyle(.title3)
            .focused($isNameFocused)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s + Space.xs / 2)
            .background(.calloutFill, in: .rect(cornerRadius: Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(
                        isNameFocused ? Color.accentFill : Color.dividerLine, lineWidth: isNameFocused ? 2 : 1)
            }
            .frame(maxWidth: 360)
            .onSubmit(model.next)
            .onAppear { isNameFocused = true }
    }
}
