import SwiftUI
import WorkbenchCore

/// The one list of every source and what stops it, in Settings › Capture. The Sources page reads the same model.
struct SourceHealthSection: View {
    @Environment(CaptureSettings.self) private var capture

    var body: some View {
        Section {
            ForEach(capture.sourceHealth) { health in
                LabeledContent {
                    Image(systemName: health.isReady ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(health.isReady ? Tone.good.color : Tone.attention.color)
                } label: {
                    Text(health.source.name)
                    Text(health.isReady ? "Ready." : health.sentences.joined(separator: " "))
                }
            }
        } header: {
            Text("Source health")
        }
    }
}

/// A small mark on a machine that uses one source: nothing while the source is ready, else what stops it.
struct SourceHealthMark: View {
    @Environment(CaptureSettings.self) private var capture
    let source: SourceHealth.Source

    var body: some View {
        if let health = capture.health(of: source), !health.isReady {
            Label(health.sentences.joined(separator: " "), systemImage: "exclamationmark.triangle")
                .foregroundStyle(Tone.attention.color)
                .textStyle(.callout)
                .onAppear(perform: capture.refreshHealth)
        }
    }
}
