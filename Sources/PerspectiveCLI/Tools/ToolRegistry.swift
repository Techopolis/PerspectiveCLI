// ToolRegistry.swift
// PerspectiveCLI
//
// Lightweight tool registry for managing Foundation Models tools.
// Register tools here and they become available to both FM and MLX backends.
//
// Copyright (c) 2026 Michael Doise
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import FoundationModels

/// Registry that holds tools for the FM backend and provides tool descriptions
/// for the MLX backend's manual tool-call parsing.
///
/// ## Adding a new tool
///
/// 1. Create your tool struct conforming to `Tool` (from FoundationModels)
/// 2. Call `ToolRegistry.shared.register(MyTool())` in the registry's `init`
/// 3. Both FM and MLX backends will pick it up automatically
final class ToolRegistry: @unchecked Sendable {
    static let shared = ToolRegistry()

    private var tools: [any Tool] = []
    private let lock = NSLock()

    private init() {
        // Register default tools
        register(ExampleWeatherTool())
    }

    /// Register a new tool. Call this to add your own tools.
    func register(_ tool: any Tool) {
        lock.lock()
        defer { lock.unlock() }
        tools.append(tool)
    }

    /// All registered tools (for passing to FM LanguageModelSession).
    func allTools() -> [any Tool] {
        lock.lock()
        defer { lock.unlock() }
        return tools
    }

    /// Tool names for display (e.g. /tools command).
    func toolNames() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return tools.map { $0.name }
    }

    /// Tool descriptions for MLX system prompt injection.
    /// Returns a formatted string describing available tools for models
    /// that don't have native tool-calling support.
    func mlxToolDescriptions() -> String {
        lock.lock()
        defer { lock.unlock() }

        if tools.isEmpty { return "No tools available." }

        var desc = "You have access to the following tools:\n\n"
        for tool in tools {
            desc += "- \(tool.name): \(tool.description)\n"
        }
        desc += """

            When you need to use a tool, respond with a JSON block in this exact format:
            ```tool_call
            {"tool": "<tool_name>", "arguments": {<arguments>}}
            ```

            After the tool result is provided, incorporate it into your response naturally.
            """
        return desc
    }
}
