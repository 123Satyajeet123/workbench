import Darwin
import Foundation

/// Which browser sent a message, learned from the process tree and not from the message: a page cannot forge it, and
/// it works in every browser. The browser starts the native host, so the host's parent process is the browser. The
/// bundle id is that of the `.app` the parent process runs from. Anything else (a helper process, launchd, a
/// program outside an app) gives nil, and the connection's pages are dropped.
enum PeerBrowser {
    /// The bundle id of the browser behind a connected socket, or nil.
    static func bundleID(ofPeer client: Int32) -> String? {
        guard let host = peerProcess(of: client), let parent = parentProcess(of: host),
            let path = executablePath(of: parent)
        else { return nil }
        return bundleID(ofExecutable: path)
    }

    static func bundleID(ofExecutable path: String) -> String? {
        appBundle(ofExecutable: path).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    /// The `.app` that holds the executable at `path`, only when it sits at `<name>.app/Contents/MacOS/<file>`. A
    /// helper inside a browser is its own `.app` and gives that helper, not the browser around it.
    static func appBundle(ofExecutable path: String) -> URL? {
        let url = URL(filePath: path)
        let macOS = url.deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard macOS.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents",
            app.pathExtension == "app"
        else { return nil }
        return app
    }

    /// The process on the other end of a connected Unix socket.
    static func peerProcess(of client: Int32) -> pid_t? {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { return nil }
        return pid
    }

    static func parentProcess(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid > 1 else { return nil }
        return pid_t(info.pbi_ppid)
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
