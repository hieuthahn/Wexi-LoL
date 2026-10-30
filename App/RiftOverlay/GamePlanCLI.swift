import Foundation
import RiftCore

/// The local coding-agent CLI that writes game plans, run with a fast model and no tools.
enum GamePlanEngine: String, CaseIterable, Identifiable {
    case off, claude, codex

    var id: String { rawValue }
    var defaultModel: String {
        switch self {
        case .off: return ""
        case .claude: return "haiku"
        case .codex: return "codex/gpt-6-luna"
        }
    }
}

enum GamePlanCLIError: Error { case notFound, timedOut, failed(Int32), emptyReply }

/// Run one CLI call off the main actor and return the JSON object the schema describes.
enum GamePlanCLI {
    static let timeout: TimeInterval = 45

    static func run(_ engine: GamePlanEngine, model: String, prompt: String) async throws -> Data {
        guard let executable = resolve(engine) else { throw GamePlanCLIError.notFound }
        let work = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WexiLoL/GamePlan", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        switch engine {
        case .off:
            throw GamePlanCLIError.notFound
        case .claude:
            // Project-only settings keep the user's hooks and plugins out of a call that must stay fast,
            // so the user settings' env block (gateway URL and token) is passed on by hand.
            let output = try await launch(executable, in: work, environment: userClaudeEnvironment(), arguments: [
                "-p", "--model", model, "--effort", "low", "--tools", "", "--setting-sources", "project",
                "--no-session-persistence", "--output-format", "json", "--json-schema", GamePlan.schema, prompt
            ])
            guard let envelope = try JSONSerialization.jsonObject(with: output) as? [String: Any],
                  let plan = envelope["structured_output"] else { throw GamePlanCLIError.emptyReply }
            return try JSONSerialization.data(withJSONObject: plan)
        case .codex:
            let schema = work.appendingPathComponent("schema.json"), reply = work.appendingPathComponent("reply.json")
            try Data(GamePlan.schema.utf8).write(to: schema)
            try? FileManager.default.removeItem(at: reply)
            _ = try await launch(executable, in: work, arguments: [
                "exec", "-m", model, "-c", "model_reasoning_effort=low", "--sandbox", "read-only", "--skip-git-repo-check",
                "--ephemeral", "-C", work.path, "--output-schema", schema.path, "-o", reply.path, prompt
            ])
            guard let data = try? Data(contentsOf: reply), !data.isEmpty else { throw GamePlanCLIError.emptyReply }
            return data
        }
    }

    /// Find the binary the user's login shell would run, ignoring shell functions, and remember it.
    static func resolve(_ engine: GamePlanEngine) -> URL? {
        guard engine != .off else { return nil }
        let key = "GamePlan.\(engine.rawValue).path"
        if let saved = UserDefaults.standard.string(forKey: key), FileManager.default.isExecutableFile(atPath: saved) {
            return URL(fileURLWithPath: saved)
        }
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lic", "whence -p \(engine.rawValue)"]
        let pipe = Pipe()
        shell.standardOutput = pipe; shell.standardError = FileHandle.nullDevice; shell.standardInput = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return nil }
        let deadline = DispatchWorkItem { if shell.isRunning { shell.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: deadline)
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        shell.waitUntilExit()
        deadline.cancel()
        guard let path = text.split(separator: "\n").map(String.init).last(where: { $0.hasPrefix("/") }),
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        UserDefaults.standard.set(path, forKey: key)
        return URL(fileURLWithPath: path)
    }

    /// The string values of the `env` block in `~/.claude/settings.json`, or none when it is missing.
    static func userClaudeEnvironment() -> [String: String] {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = settings["env"] as? [String: Any] else { return [:] }
        return env.compactMapValues { $0 as? String }
    }

    private static func launch(_ executable: URL, in directory: URL, environment extra: [String: String] = [:],
                               arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment.merging(extra) { _, user in user }
        // Apps launched from Finder get a bare PATH; node-based CLIs need their own bin directory first.
        environment["PATH"] = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                               "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { try process.run() } catch { continuation.resume(throwing: error); return }
                let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                deadline.cancel()
                if process.terminationReason == .uncaughtSignal { continuation.resume(throwing: GamePlanCLIError.timedOut) }
                else if process.terminationStatus != 0 { continuation.resume(throwing: GamePlanCLIError.failed(process.terminationStatus)) }
                else { continuation.resume(returning: data) }
            }
        }
    }
}
