import AppKit
import SwiftUI
import WorkbenchCore

final class PopupPanel: NSPanel {
    static let width: CGFloat = 380
    static let margin: CGFloat = 8

    private var screenChanges: Task<Void, Never>?
    private var height: CGFloat = 0

    init(session: AppSession) {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = true
        let content = NSHostingView(
            rootView: PopupContent(session: session) { [weak self] height in self?.fit(height) })
        content.sizingOptions = []
        contentView = content
        place()
        screenChanges = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification)
            {
                self?.place()
            }
        }
        orderFrontRegardless()
    }

    deinit { screenChanges?.cancel() }

    override var canBecomeKey: Bool { false }

    private func fit(_ height: CGFloat) {
        self.height = height
        ignoresMouseEvents = height < 1
        place()
    }

    private func place() {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let size = CGSize(width: Self.width, height: max(height, 1))
        setFrame(
            NSRect(
                x: area.maxX - size.width - Self.margin, y: area.maxY - size.height - Self.margin,
                width: size.width, height: size.height), display: true)
    }
}

struct PopupContent: View {
    let session: AppSession
    let fit: (CGFloat) -> Void
    @AppStorage(IslandKey.style) private var style = AlertStyle.notch
    @State private var dismissed: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let cards = cards(at: context.date)
            VStack(alignment: .trailing, spacing: Space.s) {
                ForEach(cards) { card in
                    PopupCardView(card: card, now: context.date, act: { act($0, on: card) })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(Space.m)
            .frame(width: PopupPanel.width, alignment: .topTrailing)
            .animation(Motion.settle(reduceMotion: reduceMotion), value: cards.map(\.id))
            .onGeometryChange(for: CGFloat.self) {
                cards.isEmpty ? 0 : $0.size.height
            } action: {
                fit($0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: style) {
            guard style == .popup else { return }
            while !Task.isCancelled {
                await session.today.refreshMeetings()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    private func cards(at now: Date) -> [PopupCard] {
        guard style == .popup else { return [] }
        return PopupCards.make(
            recording: session.capture.call, offer: session.callWatcher.offer?.source.service,
            meetings: session.today.meetings.meetings, dismissed: dismissed, now: now)
    }

    private func act(_ action: PopupAction, on card: PopupCard) {
        switch action {
        case .end: session.capture.stopCall()
        case .record: session.callWatcher.record()
        case .recordAlways: session.callWatcher.recordAlways()
        case .notNow: session.callWatcher.dismiss()
        case .join:
            if case .meeting(let meeting) = card, let url = meeting.joinURL { NSWorkspace.shared.open(url) }
            dismissed.insert(card.id)
        case .close: dismissed.insert(card.id)
        }
    }
}

enum PopupAction {
    case end, record, recordAlways, notNow, join, close
}

struct PopupCardView: View {
    let card: PopupCard
    let now: Date
    let act: (PopupAction) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            icon.frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.system(size: 13, weight: .semibold)).lineLimit(1)
                detail.font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            buttons.font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s + 2)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var icon: some View {
        switch card {
        case .recording:
            Image(systemName: "record.circle.fill").font(.system(size: 26)).foregroundStyle(.red)
                .symbolEffect(.pulse)
        case .offer: Mascot(look: .echo, size: 30)
        case .meeting: Image(systemName: "video.fill").font(.system(size: 20)).foregroundStyle(.blue)
        }
    }

    @ViewBuilder private var title: some View {
        switch card {
        case .recording: Text("Recording")
        case .offer(let service): Text("\(service) call detected")
        case .meeting(let meeting): Text(meeting.title.isEmpty ? "Meeting" : meeting.title)
        }
    }

    @ViewBuilder private var detail: some View {
        switch card {
        case .recording(let label, let since):
            (Text(since, style: .timer).monospacedDigit() + Text(" · \(label)"))
        case .offer: Text("Record it for notes?")
        case .meeting(let meeting):
            Text([PopupCards.when(meeting, at: now), meeting.joinService].compactMap { $0 }.joined(separator: " · "))
        }
    }

    @ViewBuilder private var buttons: some View {
        switch card {
        case .recording:
            Button("End") { act(.end) }.buttonStyle(PopupButtonStyle(fill: .red))
        case .offer:
            HStack(spacing: Space.xs) {
                Button("Not now") { act(.notNow) }.buttonStyle(PopupButtonStyle(fill: nil))
                Menu("Record") {
                    Button("Record this call") { act(.record) }
                    Button("Always record calls from this app") { act(.recordAlways) }
                } primaryAction: {
                    act(.record)
                }
                .menuStyle(.button).buttonStyle(PopupButtonStyle(fill: .accentFill)).fixedSize()
            }
        case .meeting:
            HStack(spacing: Space.xs) {
                Button("Join") { act(.join) }.buttonStyle(PopupButtonStyle(fill: .accentFill))
                Button("Dismiss", systemImage: "xmark") { act(.close) }.labelStyle(.iconOnly)
                    .buttonStyle(PopupButtonStyle(fill: nil))
            }
        }
    }
}

private struct PopupButtonStyle: ButtonStyle {
    let fill: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(fill == nil ? Color.primary : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(fill ?? Color.primary.opacity(0.1), in: .capsule)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .contentShape(.capsule)
            .pointerStyle(.link)
    }
}
