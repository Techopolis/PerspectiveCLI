// FoundationModelCoordinator.swift
// PerspectiveCLI
//
// Serializes access to Apple Foundation Models.
// Concurrent generations can wedge the accelerator, so this
// provides a simple exclusive-access queue.
//
// Copyright (c) 2026 Michael Doise
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

actor FoundationModelCoordinator {
    static let shared = FoundationModelCoordinator()

    private var isLocked = false
    private var waitlist: [CheckedContinuation<Void, Never>] = []

    private func enqueue(_ continuation: CheckedContinuation<Void, Never>) {
        waitlist.append(continuation)
    }

    private func resumeNext() {
        if waitlist.isEmpty {
            isLocked = false
        } else {
            let next = waitlist.removeFirst()
            next.resume()
        }
    }

    func beginTask() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            enqueue(continuation)
        }
    }

    func endTask() async {
        resumeNext()
    }

    func withExclusiveAccess<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await beginTask()
        do {
            let value = try await operation()
            await endTask()
            return value
        } catch {
            await endTask()
            throw error
        }
    }
}
