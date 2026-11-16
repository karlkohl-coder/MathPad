import Foundation

/// Runs a command line tool and collects its output.
///
/// A GUI app starts with a minimal `PATH`, so the usual install locations are
/// added before launching — otherwise tools that shell out to `node` or `git`
/// fail in ways that are hard to read.
enum ProcessRunner {

    enum RunError: LocalizedError {
        case launchFailed(String)
        case timedOut(seconds: Int)
        case failed(status: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let detail): "Programm konnte nicht gestartet werden: \(detail)"
            case .timedOut(let seconds): "Zeitüberschreitung nach \(seconds) Sekunden."
            case .failed(let status, let output):
                "Programm endete mit Code \(status): \(output.prefix(300))"
            }
        }
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                     "\(home)/.local/bin", "\(home)/.bun/bin"]
        let existing = env["PATH"]?.split(separator: ":").map(String.init) ?? []
        env["PATH"] = (existing + extra.filter { !existing.contains($0) }).joined(separator: ":")
        return env
    }

    static func run(executable: String,
                    arguments: [String],
                    timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = try runSync(executable: executable,
                                             arguments: arguments,
                                             timeout: timeout)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func runSync(executable: String,
                        arguments: [String],
                        timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        // Drain both pipes while the process runs: a full pipe buffer would
        // otherwise block the child forever.
        let collector = OutputCollector()
        stdout.fileHandleForReading.readabilityHandler = { collector.appendOut($0.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { collector.appendError($0.availableData) }

        do {
            try process.run()
        } catch {
            throw RunError.launchFailed(error.localizedDescription)
        }

        let deadline = DispatchTime.now() + timeout
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: watchdog)

        process.waitUntilExit()
        watchdog.cancel()

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        collector.appendOut(stdout.fileHandleForReading.availableData)
        collector.appendError(stderr.fileHandleForReading.availableData)

        let out = collector.standardOutput
        if process.terminationReason == .uncaughtSignal, out.isEmpty {
            throw RunError.timedOut(seconds: Int(timeout))
        }
        guard process.terminationStatus == 0 || !out.isEmpty else {
            throw RunError.failed(status: process.terminationStatus, output: collector.standardError)
        }
        return out
    }
}

/// Thread-safe buffer for the two pipes.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func appendOut(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); out.append(data); lock.unlock()
    }

    func appendError(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); err.append(data); lock.unlock()
    }

    var standardOutput: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: out, encoding: .utf8) ?? ""
    }

    var standardError: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: err, encoding: .utf8) ?? ""
    }
}
