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
    static func read(_ executable: String, _ arguments: [String], timeout: TimeInterval = 2) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }

        // Drain stdout while the child is running. Waiting first can deadlock once
        // the child fills the pipe buffer (a full `ps` listing can easily do so).
        let captured = ProcessOutput()
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            captured.store(output.fileHandleForReading.readDataToEndOfFile())
            reader.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            _ = reader.wait(timeout: .now() + 0.5)
            return ""
        }
        reader.wait()
        return String(data: captured.read(), encoding: .utf8) ?? ""
    }
}
