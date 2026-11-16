import Foundation

/// Appends a line to the file named by `MATHPAD_LOG`. Off unless that variable
/// is set, so it costs nothing in normal use.
enum Diagnostics {
    private static let path = ProcessInfo.processInfo.environment["MATHPAD_LOG"]

    static func log(_ message: @autoclosure () -> String) {
        guard let path else { return }
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message())\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
