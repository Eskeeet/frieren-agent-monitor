import Foundation

private final class ProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ data: Data) {
        lock.lock()
        self.data = data
        lock.unlock()
    }

    func read() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

enum ProcessRunner {
    struct Result {
        let standardOutput: String
        let standardError: String
        let exitCode: Int32
        let timedOut: Bool
    }

    static func read(_ executable: String, _ arguments: [String], timeout: TimeInterval = 2) -> String {
        let result = run(executable, arguments, timeout: timeout)
        return result.exitCode == 0 && !result.timedOut ? result.standardOutput : ""
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 2) -> Result {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch {
            return Result(standardOutput: "", standardError: error.localizedDescription, exitCode: -1, timedOut: false)
        }

        // Drain stdout while the child is running. Waiting first can deadlock once
        // the child fills the pipe buffer (a full `ps` listing can easily do so).
        let captured = ProcessOutput()
        let capturedErrors = ProcessOutput()
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            captured.store(output.fileHandleForReading.readDataToEndOfFile())
            reader.leave()
        }
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            capturedErrors.store(errors.fileHandleForReading.readDataToEndOfFile())
            reader.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            _ = reader.wait(timeout: .now() + 0.5)
            return Result(
                standardOutput: String(data: captured.read(), encoding: .utf8) ?? "",
                standardError: String(data: capturedErrors.read(), encoding: .utf8) ?? "",
                exitCode: -1,
                timedOut: true
            )
        }
        reader.wait()
        return Result(
            standardOutput: String(data: captured.read(), encoding: .utf8) ?? "",
            standardError: String(data: capturedErrors.read(), encoding: .utf8) ?? "",
            exitCode: process.terminationStatus,
            timedOut: false
        )
    }
}
