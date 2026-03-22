// PerspectiveCLI.swift
// PerspectiveCLI
//
// Open-source CLI for running Apple Foundation Models and MLX models
// with extensible tool support.
//
// Copyright (c) 2026 Michael Doise
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import FoundationModels

// MARK: - Entry Point

@main
struct PerspectiveCLI {
    static func main() async {
        // mlx-swift uses dladdr to find mlx.metallib next to the binary.
        // When installed via symlink (e.g. Homebrew) or relocated, that lookup
        // can fail. Resolve the real executable path and chdir there so the
        // colocated metallib search succeeds regardless of install location.
        Self.chdirToExecutableDirectory()

        let args = CLIArguments()

        if args.help {
            printUsage()
            return
        }

        await CLIApp.shared.run(with: args)
    }

    /// Change working directory to the real (symlink-resolved) executable directory.
    private static func chdirToExecutableDirectory() {
        let execPath = ProcessInfo.processInfo.arguments[0]
        let execURL = URL(fileURLWithPath: execPath).resolvingSymlinksInPath()
        let dir = execURL.deletingLastPathComponent().path
        FileManager.default.changeCurrentDirectoryPath(dir)
    }
}

// MARK: - Error Types

enum CLIError: LocalizedError {
    case sessionNotInitialized
    case backendUnavailable(String)
    case adapterNotFound(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotInitialized:
            return "Session not initialized. Try /reset to reinitialize."
        case .backendUnavailable(let reason):
            return "Backend unavailable: \(reason)"
        case .adapterNotFound(let path):
            return "Adapter file not found: \(path)"
        }
    }
}

// MARK: - CLI Arguments

struct CLIArguments {
    var backend: Backend?
    var mlxModel: String?
    var prompt: String?
    var temperature: Float?
    var stream: Bool = false
    var systemPrompt: String?
    var tools: Bool = false
    var adapter: String?
    var help: Bool = false

    init() {
        let args = CommandLine.arguments.dropFirst() // skip executable path
        var iter = args.makeIterator()
        while let arg = iter.next() {
            switch arg {
            case "--fm":
                backend = .fm
            case "--mlx":
                backend = .mlx
            case "--model", "--mlx-model", "-m":
                mlxModel = iter.next()
            case "--prompt", "-p":
                prompt = iter.next()
            case "--temperature", "-t":
                if let val = iter.next() { temperature = Float(val) }
            case "--stream", "-s":
                stream = true
            case "--system":
                systemPrompt = iter.next()
            case "--tools":
                tools = true
            case "--adapter":
                adapter = iter.next()
            case "--help", "-h":
                help = true
            default:
                printError("Unknown argument: \(arg)")
                help = true
                return
            }
        }
    }
}

// MARK: - Backend Selection

enum Backend: String {
    case fm = "FM"
    case mlx = "MLX"
}

// MARK: - Main CLI Application

actor CLIApp {
    static let shared = CLIApp()

    private let fmBackend = FoundationModelsBackend()
    private let mlxBackend = MLXBackend()

    private var activeBackend: Backend = .fm
    private var isRunning = true
    private var customSystemPrompt: String? = nil
    private var toolsEnabled = false

    private init() {}

    /// Apply CLI arguments to configure backends before starting.
    private func applyArgs(_ args: CLIArguments) async {
        if let backend = args.backend {
            activeBackend = backend
        }
        if let system = args.systemPrompt {
            customSystemPrompt = system
        }
        if args.tools {
            toolsEnabled = true
        }
        if args.stream {
            await fmBackend.setStreaming(true)
        }
        if let temp = args.temperature {
            switch activeBackend {
            case .fm:
                await fmBackend.setTemperature(temp)
            case .mlx:
                await mlxBackend.setTemperature(temp)
            }
        }
        if let model = args.mlxModel {
            await mlxBackend.setModelId(model)
        }
        if let adapterPath = args.adapter {
            do {
                try await fmBackend.loadAdapter(from: adapterPath)
                printSuccess("Adapter loaded: \(adapterPath)")
            } catch {
                printError("Failed to load adapter: \(error.localizedDescription)")
            }
        }
    }

    /// Initialize the active backend, returning true on success.
    private func initializeActiveBackend(quiet: Bool = false) async -> Bool {
        switch activeBackend {
        case .fm:
            let (available, msg) = FoundationModelsBackend.checkAvailability()
            if !available {
                printError(msg)
                return false
            }
            if !quiet { printSuccess(msg) }
            do {
                try await fmBackend.initialize(customPrompt: customSystemPrompt, enableTools: toolsEnabled)
            } catch {
                printError("Failed to initialize FM: \(error.localizedDescription)")
                return false
            }
            if !quiet { printSuccess("FM session initialized") }
            return true
        case .mlx:
            do {
                try await mlxBackend.initialize(customPrompt: customSystemPrompt)
                if !quiet { printSuccess("MLX session initialized") }
                return true
            } catch {
                printError("Failed to initialize MLX: \(error.localizedDescription)")
                return false
            }
        }
    }

    /// One-shot mode: send a prompt, print the response, and exit.
    private func runOneShot(_ prompt: String) async {
        guard await initializeActiveBackend(quiet: true) else { return }

        do {
            switch activeBackend {
            case .fm:
                if await fmBackend.isStreaming() {
                    let stream = try await fmBackend.streamMessage(prompt)
                    var lastLength = 0
                    for try await partial in stream {
                        let newContent = String(partial.dropFirst(lastLength))
                        print(newContent, terminator: "")
                        fflush(stdout)
                        lastLength = partial.count
                    }
                    print("")
                } else {
                    let response = try await fmBackend.sendMessage(prompt)
                    print(response)
                }
            case .mlx:
                let stream = try await mlxBackend.streamMessage(prompt)
                var lastLength = 0
                for try await partial in stream {
                    let newContent = String(partial.dropFirst(lastLength))
                    print(newContent, terminator: "")
                    fflush(stdout)
                    lastLength = partial.count
                }
                print("")
            }
        } catch {
            printError("Error: \(error.localizedDescription)")
        }
    }

    func run(with args: CLIArguments) async {
        await applyArgs(args)

        if let prompt = args.prompt {
            await runOneShot(prompt)
            return
        }

        await run()
    }

    func run() async {
        printWelcome()

        // Check Foundation Models availability
        let (fmAvailable, fmMessage) = FoundationModelsBackend.checkAvailability()
        if fmAvailable {
            printSuccess(fmMessage)
        } else {
            printError(fmMessage)
            printInfo("Foundation Models require macOS 26+ with Apple Silicon.")
            printInfo("You can still use MLX mode with /mlx")
        }

        // Initialize FM backend if available
        if fmAvailable && activeBackend == .fm {
            do {
                try await fmBackend.initialize(customPrompt: customSystemPrompt, enableTools: toolsEnabled)
                printSuccess("FM session initialized")
            } catch {
                printError("Failed to initialize FM: \(error.localizedDescription)")
            }
        }

        // Initialize MLX backend if selected via args
        if activeBackend == .mlx {
            do {
                try await mlxBackend.initialize(customPrompt: customSystemPrompt)
                printSuccess("MLX session initialized")
            } catch {
                printError("Failed to initialize MLX: \(error.localizedDescription)")
            }
        }

        printHelp()
        print("")

        // Main chat loop
        while isRunning {
            // Show prompt based on active backend
            switch activeBackend {
            case .fm:
                print("\u{001B}[94m[FM] You:\u{001B}[0m ", terminator: "")
            case .mlx:
                let modelShort = await mlxBackend.getModelId().components(separatedBy: "/").last ?? "MLX"
                print("\u{001B}[93m[MLX:\(modelShort)] You:\u{001B}[0m ", terminator: "")
            }
            fflush(stdout)

            guard let input = readLine(strippingNewline: true) else {
                break  // EOF
            }

            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // Handle commands
            if trimmed.hasPrefix("/") {
                await handleCommand(trimmed)
                continue
            }

            // Allow exit without slash
            let lower = trimmed.lowercased()
            if lower == "exit" || lower == "quit" || lower == "bye" {
                isRunning = false
                continue
            }

            // Send message
            await sendMessage(trimmed)
        }

        printInfo("Goodbye!")
    }

    // MARK: - Command Handling

    private func handleCommand(_ command: String) async {
        let cmd = command.lowercased()

        switch cmd {
        case "/quit", "/exit", "/q":
            isRunning = false

        case "/reset":
            switch activeBackend {
            case .fm:
                await fmBackend.resetSession()
                do {
                    try await fmBackend.initialize(customPrompt: customSystemPrompt, enableTools: toolsEnabled)
                    printSuccess("FM conversation reset")
                } catch {
                    printError("Failed to reinitialize FM: \(error.localizedDescription)")
                }
            case .mlx:
                await mlxBackend.resetSession()
                do {
                    try await mlxBackend.initialize(customPrompt: customSystemPrompt)
                    printSuccess("MLX conversation reset")
                } catch {
                    printError("Failed to reinitialize MLX: \(error.localizedDescription)")
                }
            }

        case "/stream":
            if activeBackend == .fm {
                let enabled = await fmBackend.toggleStreaming()
                printInfo("Streaming: \(enabled ? "enabled" : "disabled")")
            } else {
                printWarning("Streaming is always on for MLX mode")
            }

        case "/fm":
            activeBackend = .fm
            let (available, _) = FoundationModelsBackend.checkAvailability()
            if available {
                do {
                    try await fmBackend.initialize(customPrompt: customSystemPrompt, enableTools: toolsEnabled)
                    printSuccess("Switched to Foundation Models backend")
                } catch {
                    printError("Failed to initialize FM: \(error.localizedDescription)")
                }
            } else {
                printError("Foundation Models not available on this device")
                activeBackend = .mlx
            }

        case "/mlx":
            activeBackend = .mlx
            let modelId = await mlxBackend.getModelId()
            printSuccess("Switched to MLX backend")
            printInfo("Model: \(modelId)")
            printInfo("Model will be downloaded on first use if not cached.")
            do {
                try await mlxBackend.initialize(customPrompt: customSystemPrompt)
                printSuccess("MLX session initialized")
            } catch {
                printError("Failed to initialize MLX: \(error.localizedDescription)")
            }

        case _ where cmd.hasPrefix("/mlx-model "):
            let modelId = String(command.dropFirst("/mlx-model ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if modelId.isEmpty {
                printWarning("Usage: /mlx-model <model-id>")
                printInfo("Example: /mlx-model mlx-community/gemma-3-4b-it-4bit")
            } else {
                await mlxBackend.setModelId(modelId)
                printSuccess("MLX model set to: \(modelId)")
                if activeBackend == .mlx {
                    printInfo("Reinitializing with new model...")
                    do {
                        try await mlxBackend.initialize(customPrompt: customSystemPrompt)
                        printSuccess("Session reinitialized")
                    } catch {
                        printError("Failed to reinitialize: \(error.localizedDescription)")
                    }
                }
            }

        case "/system":
            if let prompt = customSystemPrompt {
                printInfo("Current system prompt:")
                printInfo("  \(prompt)")
            } else {
                printInfo("No custom system prompt set (using default)")
            }

        case "/system clear":
            customSystemPrompt = nil
            printSuccess("Custom system prompt cleared")
            await reinitializeActiveBackend()

        case "/system default":
            switch activeBackend {
            case .fm:
                printInfo("Default FM system prompt:")
                printInfo(FoundationModelsBackend.defaultSystemPrompt())
            case .mlx:
                printInfo("Default MLX system prompt:")
                printInfo(MLXBackend.defaultSystemPrompt())
            }

        case _ where cmd.hasPrefix("/system "):
            let text = String(command.dropFirst("/system ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                printWarning("Usage: /system <prompt text>")
            } else {
                customSystemPrompt = text
                printSuccess("Custom system prompt set")
                await reinitializeActiveBackend()
            }

        case "/tools":
            printInfo("Tools: \(toolsEnabled ? "enabled" : "disabled") (FM only)")
            let names = ToolRegistry.shared.toolNames()
            if names.isEmpty {
                printInfo("No tools registered")
            } else {
                printInfo("Registered tools:")
                for name in names {
                    printInfo("  - \(name)")
                }
            }
            printInfo("Use /tools enable or /tools disable to toggle.")

        case "/tools enable":
            toolsEnabled = true
            printSuccess("Tools enabled")
            await reinitializeActiveBackend()

        case "/tools disable":
            toolsEnabled = false
            printSuccess("Tools disabled")
            await reinitializeActiveBackend()

        case "/temperature":
            let temp: Float = switch activeBackend {
            case .fm: await fmBackend.getTemperature()
            case .mlx: await mlxBackend.getTemperature()
            }
            printInfo("Temperature: \(temp)")

        case _ where cmd.hasPrefix("/temperature "):
            let value = String(command.dropFirst("/temperature ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let maxTemp: Float = activeBackend == .fm ? 1.0 : 2.0
            if let temp = Float(value), temp >= 0.0, temp <= maxTemp {
                switch activeBackend {
                case .fm:
                    await fmBackend.setTemperature(temp)
                case .mlx:
                    await mlxBackend.setTemperature(temp)
                    printInfo("Reinitializing session...")
                    await reinitializeActiveBackend()
                }
                printSuccess("Temperature set to \(temp)")
            } else {
                printWarning("Invalid temperature. Use a value between 0.0 and \(maxTemp)")
            }

        case "/adapter":
            if let path = await fmBackend.currentAdapterPath() {
                printInfo("Current adapter: \(path)")
            } else {
                printInfo("No adapter loaded")
            }

        case "/adapter clear":
            await fmBackend.clearAdapter()
            printSuccess("Adapter cleared")
            if activeBackend == .fm {
                await reinitializeActiveBackend()
            }

        case _ where cmd.hasPrefix("/adapter "):
            let path = String(command.dropFirst("/adapter ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty {
                printWarning("Usage: /adapter <path-to-.fmadapter>")
            } else {
                let resolved = NSString(string: path).expandingTildeInPath
                do {
                    try await fmBackend.loadAdapter(from: resolved)
                    printSuccess("Adapter loaded: \(resolved)")
                    if activeBackend == .fm {
                        printInfo("Reinitializing FM session with adapter...")
                        await reinitializeActiveBackend()
                    }
                } catch {
                    printError("Failed to load adapter: \(error.localizedDescription)")
                }
            }

        case "/status":
            printInfo("Perspective CLI Status")
            printInfo("─────────────────────")
            // Active backend
            printInfo("  Active backend:    \(activeBackend.rawValue)")
            // FM availability
            let (fmOk, fmDetail) = FoundationModelsBackend.detailedAvailability()
            if fmOk {
                printSuccess("Foundation Models: \(fmDetail)")
            } else {
                printError("Foundation Models: \(fmDetail)")
            }
            // FM settings
            let fmTemp = await fmBackend.getTemperature()
            let fmStream = await fmBackend.isStreaming()
            printInfo("  FM temperature:    \(fmTemp)")
            printInfo("  FM streaming:      \(fmStream ? "on" : "off")")
            printInfo("  Tools:             \(toolsEnabled ? "enabled" : "disabled")")
            // Adapter
            if let adapterPath = await fmBackend.currentAdapterPath() {
                printInfo("  FM adapter:        \(adapterPath)")
            } else {
                printInfo("  FM adapter:        none")
            }
            // MLX settings
            let mlxModel = await mlxBackend.getModelId()
            let mlxTemp = await mlxBackend.getTemperature()
            printInfo("  MLX model:         \(mlxModel)")
            printInfo("  MLX temperature:   \(mlxTemp)")
            // System prompt
            if customSystemPrompt != nil {
                printInfo("  System prompt:     custom")
            } else {
                printInfo("  System prompt:     default")
            }

        case "/help", "/?":
            printHelp()

        default:
            printWarning("Unknown command: \(command)")
            printInfo("Type /help for available commands.")
        }
    }

    // MARK: - Backend Reinitialization

    private func reinitializeActiveBackend() async {
        switch activeBackend {
        case .fm:
            await fmBackend.resetSession()
            do {
                try await fmBackend.initialize(customPrompt: customSystemPrompt, enableTools: toolsEnabled)
                printSuccess("FM session reinitialized")
            } catch {
                printError("Failed to reinitialize FM: \(error.localizedDescription)")
            }
        case .mlx:
            await mlxBackend.resetSession()
            do {
                try await mlxBackend.initialize(customPrompt: customSystemPrompt)
                printSuccess("MLX session reinitialized")
            } catch {
                printError("Failed to reinitialize MLX: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Message Sending

    private func sendMessage(_ message: String) async {
        // Show assistant label
        switch activeBackend {
        case .fm:
            print("\u{001B}[94m[FM] Assistant:\u{001B}[0m ", terminator: "")
        case .mlx:
            print("\u{001B}[93m[MLX] Assistant:\u{001B}[0m ", terminator: "")
        }
        fflush(stdout)

        do {
            switch activeBackend {
            case .fm:
                if await fmBackend.isStreaming() {
                    let stream = try await fmBackend.streamMessage(message)
                    var lastLength = 0
                    for try await partial in stream {
                        let newContent = String(partial.dropFirst(lastLength))
                        print(newContent, terminator: "")
                        fflush(stdout)
                        lastLength = partial.count
                    }
                    print("")
                } else {
                    let response = try await fmBackend.sendMessage(message)
                    print(response)
                }

            case .mlx:
                let stream = try await mlxBackend.streamMessage(message)
                var lastLength = 0
                for try await partial in stream {
                    let newContent = String(partial.dropFirst(lastLength))
                    print(newContent, terminator: "")
                    fflush(stdout)
                    lastLength = partial.count
                }
                print("")
            }
        } catch {
            print("")
            printError("Error: \(error.localizedDescription)")
        }

        print("")
    }
}

// MARK: - Terminal Output Helpers

func printWelcome() {
    print("")
    print("\u{001B}[1;34m====================================================\u{001B}[0m")
    print("\u{001B}[1;34m|\u{001B}[0m    \u{001B}[1;37mPerspective CLI\u{001B}[0m                               \u{001B}[1;34m|\u{001B}[0m")
    print("\u{001B}[1;34m|\u{001B}[0m    Foundation Models + MLX on your Mac           \u{001B}[1;34m|\u{001B}[0m")
    print("\u{001B}[1;34m====================================================\u{001B}[0m")
    print("")
}

func printHelp() {
    printInfo("Commands:")
    printInfo("  /fm               - Switch to Foundation Models backend")
    printInfo("  /mlx              - Switch to MLX backend")
    printInfo("  /mlx-model <id>   - Set MLX model (e.g. mlx-community/gemma-3-4b-it-4bit)")
    printInfo("  /system <prompt>  - Set a custom system prompt")
    printInfo("  /system           - Show current custom system prompt")
    printInfo("  /system default   - Show the built-in default system prompt")
    printInfo("  /system clear     - Clear custom system prompt")
    printInfo("  /temperature <n>  - Set temperature (FM: 0.0-1.0, MLX: 0.0-2.0)")
    printInfo("  /stream           - Toggle streaming (FM only)")
    printInfo("  /adapter <path>   - Load a .fmadapter file (FM only)")
    printInfo("  /adapter          - Show current adapter")
    printInfo("  /adapter clear    - Remove loaded adapter")
    printInfo("  /tools            - Show tool status and list")
    printInfo("  /tools enable     - Enable tool calling (FM only)")
    printInfo("  /tools disable    - Disable tool calling")
    printInfo("  /status           - Show Foundation Models availability and settings")
    printInfo("  /reset            - Reset conversation")
    printInfo("  /help             - Show this help")
    printInfo("  /quit, /exit      - Exit")
}

func printSuccess(_ message: String) {
    print("\u{001B}[32m[OK] \(message)\u{001B}[0m")
}

func printError(_ message: String) {
    print("\u{001B}[31m[ERROR] \(message)\u{001B}[0m")
}

func printWarning(_ message: String) {
    print("\u{001B}[33m[WARN] \(message)\u{001B}[0m")
}

func printInfo(_ message: String) {
    print("\u{001B}[90m\(message)\u{001B}[0m")
}

func printUsage() {
    print("Usage: perspective [options]")
    print("")
    print("Options:")
    print("  --fm                  Use Foundation Models backend")
    print("  --mlx                 Use MLX backend")
    print("  -m, --model <id>      Set MLX model (e.g. mlx-community/gemma-3-4b-it-4bit)")
    print("  -p, --prompt <text>   Send a prompt and exit (one-shot mode)")
    print("  -t, --temperature <n> Set temperature (FM: 0.0-1.0, MLX: 0.0-2.0)")
    print("  -s, --stream          Enable streaming output (FM)")
    print("  --system <text>       Set a custom system prompt")
    print("  --tools               Enable tool calling (FM)")
    print("  --adapter <path>      Load a .fmadapter file (FM)")
    print("  -h, --help            Show this help")
    print("")
    print("Examples:")
    print("  perspective --fm --prompt \"What is Swift?\"")
    print("  perspective --mlx --prompt \"Hello\"")
    print("  perspective --mlx --mlx-model mlx-community/gemma-3-4b-it-4bit")
    print("  perspective --temperature 0.5 --prompt \"Be creative\"")
    print("")
    print("Without --prompt, enters interactive REPL mode.")
}
