import Foundation

struct ShellResult {
    let stdout: String
    let stderr: String
    let status: Int32
}

enum Shell {
    static func run(_ executable: String, arguments: [String]) -> ShellResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ShellResult(stdout: "", stderr: error.localizedDescription, status: 1)
        }

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return ShellResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }
}
