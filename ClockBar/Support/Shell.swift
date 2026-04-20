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
        } catch {
            return ShellResult(stdout: "", stderr: error.localizedDescription, status: 1)
        }

        // Drain both pipes concurrently. Without this, a child that writes more
        // than the pipe buffer (~64KB) blocks on write while we block on
        // waitUntilExit — deadlock. `pmset -g log` hits this easily.
        let drainQueue = DispatchQueue(label: "clockbar.shell.drain", attributes: .concurrent)
        let group = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()

        group.enter()
        drainQueue.async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        drainQueue.async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return ShellResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }
}
