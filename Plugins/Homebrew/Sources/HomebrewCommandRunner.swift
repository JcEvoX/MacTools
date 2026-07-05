import Foundation

public protocol HomebrewCommandRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        onOutput: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) async throws -> Int32
    
    func cancel() async
}

public actor HomebrewCommandRunner: HomebrewCommandRunning {
    private var activeProcess: Process?

    public init() {}

    /// Runs a command asynchronously, streaming output and error chunks to the provided handlers.
    /// Returns the termination status (exit code).
    public func run(
        executable: String,
        arguments: [String],
        onOutput: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) async throws -> Int32 {
        if activeProcess != nil {
            throw NSError(
                domain: "HomebrewCommandRunner",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "A process is already running."]
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        
        // Setup environment path, ensuring homebrew binaries are visible
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? ""
        let brewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        var pathComponents = path.components(separatedBy: ":")
        for p in brewPaths {
            if !pathComponents.contains(p) {
                pathComponents.insert(p, at: 0)
            }
        }
        env["PATH"] = pathComponents.joined(separator: ":")
        env["HOMEBREW_NO_EMOJI"] = "1"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        process.environment = env
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        self.activeProcess = process

        // Attach readability handlers to stream output in real-time
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let string = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    onOutput(string)
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let string = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    onError(string)
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] proc in
                // Clear readability handlers to prevent resource leaks
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                Task { [weak self] in
                    guard let self = self else { return }
                    await self.clearProcess()
                    continuation.resume(returning: proc.terminationStatus)
                }
            }

            do {
                try process.run()
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                Task {
                    self.clearProcess()
                }
                continuation.resume(throwing: error)
            }
        }
    }

    public func cancel() {
        if let process = activeProcess, process.isRunning {
            process.terminate()
        }
        activeProcess = nil
    }

    private func clearProcess() {
        self.activeProcess = nil
    }
}
