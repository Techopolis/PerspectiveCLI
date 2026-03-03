// ExampleWeatherTool.swift
// PerspectiveCLI
//
// Example tool demonstrating Foundation Models Tool protocol conformance.
// Returns mock weather data. Use this as a template for building your own tools.
//
// Copyright (c) 2026 Michael Doise
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import FoundationModels

/// Example weather tool that returns mock weather data.
///
/// To create your own tool:
/// 1. Create a new file in Sources/PerspectiveCLI/Tools/
/// 2. Define a struct conforming to `Tool` (from FoundationModels)
/// 3. Add `@Generable` arguments and a `@Guide` description for each parameter
/// 4. Implement `call(arguments:)` returning a String
/// 5. Register it in ToolRegistry.swift
struct ExampleWeatherTool: Tool {
    let name = "getWeather"
    let description = """
        Get the current weather for a specific location. ONLY use this tool when \
        the user explicitly asks about current weather, temperature, or forecast \
        for a named city or place. Do NOT use for general knowledge questions.
        """

    @Generable
    struct Arguments {
        @Guide(description: "The city or location to get weather for, e.g. 'San Francisco' or 'New York'.")
        var location: String
    }

    func call(arguments: Arguments) async throws -> String {
        let location = arguments.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayLocation = location.isEmpty ? "San Francisco" : location

        print("\n\u{001B}[90m  [Tool] getWeather: \(displayLocation)\u{001B}[0m")

        let temp = Int.random(in: 55...85)
        let conditions = ["Sunny", "Partly Cloudy", "Cloudy", "Light Rain", "Clear"].randomElement()!

        return """
            Current Weather for \(displayLocation):
            Temperature: \(temp)°F (feels like \(temp + Int.random(in: -3...3))°F)
            Conditions: \(conditions)
            Humidity: \(Int.random(in: 30...80))%
            Wind: \(Int.random(in: 5...20)) mph
            UV Index: \(Int.random(in: 1...10))
            """
    }
}
