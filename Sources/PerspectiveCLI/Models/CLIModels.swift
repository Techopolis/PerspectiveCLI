// CLIModels.swift
// PerspectiveCLI
//
// In-memory conversation and message models for CLI chat tracking.
//
// Copyright (c) 2026 Michael Doise
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

// MARK: - CLI Message

/// In-memory message for tracking conversation history
final class CLIMessage: @unchecked Sendable {
    let id: UUID
    let content: String
    let isFromUser: Bool
    let timestamp: Date

    init(content: String, isFromUser: Bool, timestamp: Date = Date()) {
        self.id = UUID()
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
    }
}

// MARK: - CLI Conversation

/// In-memory conversation tracking for context management
final class CLIConversation: @unchecked Sendable {
    let id: UUID

    private var messages: [CLIMessage] = []
    private let lock = NSLock()

    init() {
        self.id = UUID()
    }

    func addUserMessage(_ content: String) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(CLIMessage(content: content, isFromUser: true))
    }

    func addAssistantMessage(_ content: String) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(CLIMessage(content: content, isFromUser: false))
    }

    func messageCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return messages.count
    }

    func clearMessages() {
        lock.lock()
        defer { lock.unlock() }
        messages.removeAll()
    }

    /// Get messages as formatted context string
    func buildContextString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return messages.map { msg in
            let role = msg.isFromUser ? "User" : "Assistant"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n")
    }
}
