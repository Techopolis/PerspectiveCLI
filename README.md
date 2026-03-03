# PerspectiveCLI

A lightweight, open-source Swift CLI for running **Apple Foundation Models** and **MLX models** on your Mac.

## Requirements

- macOS 26+ (Tahoe)
- Apple Silicon (M1 or later)
- Xcode 26+
- Swift 6.0+

Foundation Models requires Apple Intelligence to be enabled. MLX mode works on any Apple Silicon Mac.

## Install from Release

Download the latest release archive, then:

```bash
tar xzf perspective-cli-*.tar.gz
cd perspective-cli-*
./install.sh
```

This installs `perspective` and `mlx.metallib` to `/usr/local/bin/`. To install elsewhere:

```bash
./install.sh /opt/bin
```

To uninstall:

```bash
./install.sh --uninstall
```

## Build from Source

```bash
git clone https://github.com/your-username/PerspectiveCLI.git
cd PerspectiveCLI
./build.sh
swift run PerspectiveCLI
```

To create a release archive:

```bash
./build.sh dist
```

## Usage

Type messages to chat. Use slash commands to control the CLI:

### Backend Commands

| Command | Description |
|---------|-------------|
| `/fm` | Switch to Foundation Models backend |
| `/mlx` | Switch to MLX backend |
| `/mlx-model <id>` | Set MLX model (e.g. `mlx-community/gemma-3-4b-it-4bit`) |
| `/temperature <n>` | Set temperature (FM: 0.0-1.0, MLX: 0.0-2.0, default: 0.7) |
| `/stream` | Toggle streaming (FM only) |
| `/reset` | Reset conversation |

### Tool Commands

Tools are disabled by default. Enable them for the FM backend:

| Command | Description |
|---------|-------------|
| `/tools` | Show tool status and list registered tools |
| `/tools enable` | Enable tool calling (FM only) |
| `/tools disable` | Disable tool calling |

### System Prompt Commands

| Command | Description |
|---------|-------------|
| `/system <prompt>` | Set a custom system prompt |
| `/system` | Show current custom system prompt |
| `/system default` | Show the built-in default system prompt |
| `/system clear` | Clear custom system prompt |

### Other

| Command | Description |
|---------|-------------|
| `/help` | Show help |
| `/quit`, `/exit` | Exit |

### Example

```
[FM] You: What is iOS?
[FM] Assistant: iOS is Apple's mobile operating system...

[FM] You: /tools enable
[OK] Tools enabled

[FM] You: What's the weather in San Francisco?
  [Tool] getWeather: San Francisco
[FM] Assistant: The current weather in San Francisco is 72°F and sunny.

[FM] You: /mlx
[OK] Switched to MLX backend

[MLX:gemma-3-1b-it-qat-4bit] You: Tell me a joke
[MLX] Assistant: Why do programmers prefer dark mode? ...
```

## Adding Your Own Tools

1. Create a tool in `Sources/PerspectiveCLI/Tools/`:

```swift
import Foundation
import FoundationModels

struct MyCustomTool: Tool {
    let name = "myTool"
    let description = "Description of what your tool does."

    @Generable
    struct Arguments {
        @Guide(description: "Parameter description.")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        return "Result for: \(arguments.query)"
    }
}
```

2. Register it in `Sources/PerspectiveCLI/Tools/ToolRegistry.swift`:

```swift
private init() {
    register(ExampleWeatherTool())
    register(MyCustomTool())
}
```

3. Build and run. Enable tools with `/tools enable` to use them.

## Architecture

```
Sources/PerspectiveCLI/
├── PerspectiveCLI.swift               # Entry point + chat loop + commands
├── Backends/
│   ├── FoundationModelsBackend.swift  # Apple FM with native tool calling
│   └── MLXBackend.swift               # MLX open-weight models via mlx-swift
├── Tools/
│   ├── ToolRegistry.swift             # Central tool registry
│   └── ExampleWeatherTool.swift       # Example tool (mock weather data)
└── Models/
    ├── CLIModels.swift                # In-memory conversation tracking
    └── FoundationModelCoordinator.swift
```

- **FM backend**: Tools are passed to `LanguageModelSession` which handles calling them natively. Only active when tools are enabled.
- **MLX backend**: Runs open-weight models from HuggingFace via [mlx-swift](https://github.com/ml-explore/mlx-swift). Models are downloaded and cached on first use. Supports both LLM and VLM models.
- **ToolRegistry**: Register a tool once, it's available to both backends.

## License

MIT License. See [LICENSE](LICENSE) for details.
