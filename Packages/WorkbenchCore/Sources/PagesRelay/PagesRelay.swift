import Foundation

/// The native host's whole work: pass each frame the browser sends to the app, and pass the app's answer back. It
/// opens no store and reads no message. When the app does not run, it refuses each message, so no page text is kept
/// anywhere while the app is away.
public enum PagesRelay {
    public static let notRunning = "Workbench is not running, so nothing was kept."

    private struct Refusal: Encodable {
        var kept = false
        var error: String
    }

    /// Serves one browser session: reads a frame from `input`, answers it on `output`, and repeats until the input
    /// ends. A broken or oversize frame is answered and ends the session. The app is connected to on the first
    /// message, and again after a message found it gone.
    public static func run(input: Int32, output: Int32, socketPath: String) {
        var app: Int32?
        defer { app.map { _ = close($0) } }
        while true {
            switch NativeMessage.next(read: { PagesSocket.read(input, count: $0) }) {
            case .end:
                return
            case .broken(let failure):
                PagesSocket.write(output, refusal("\(failure)"))
                return
            case .message(let message):
                if app == nil { app = PagesSocket.connect(to: socketPath) }
                guard let connection = app, let reply = ask(connection, message) else {
                    app.map { _ = close($0) }
                    app = nil
                    PagesSocket.write(output, refusal(notRunning))
                    continue
                }
                PagesSocket.write(output, NativeMessage.frame(reply))
            }
        }
    }

    private static func ask(_ app: Int32, _ message: Data) -> Data? {
        guard PagesSocket.write(app, NativeMessage.frame(message)),
            case .message(let reply) = NativeMessage.next(read: { PagesSocket.read(app, count: $0) })
        else { return nil }
        return reply
    }

    private static func refusal(_ reason: String) -> Data {
        NativeMessage.frame((try? JSONEncoder().encode(Refusal(error: reason))) ?? Data())
    }
}
