import Foundation
import PagesRelay

// The native messaging host the Workbench browser extension calls. The browser starts it, writes framed messages to
// stdin and reads one framed reply per message from stdout, keeping stdin open until it has each reply. The host
// passes each message to the Workbench app over a local socket; only the app opens the store. WORKBENCH_PAGES_SOCKET
// names another socket, for tests.
let socketPath =
    ProcessInfo.processInfo.environment["WORKBENCH_PAGES_SOCKET"]
    ?? PagesSocket.path(in: URL.applicationSupportDirectory.appending(path: "Workbench"))
PagesRelay.run(input: STDIN_FILENO, output: STDOUT_FILENO, socketPath: socketPath)
