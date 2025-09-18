# IDE Switcher 🔄

[![Windows](https://img.shields.io/badge/platform-Windows-blue)](https://github.com/yourusername/ide-switcher)
[![Delphi](https://img.shields.io/badge/Delphi-RAD%20Studio%2010%2B-red)](https://www.embarcadero.com/products/rad-studio)
[![VS Code](https://img.shields.io/badge/VS%20Code-1.50%2B-007ACC)](https://code.visualstudio.com/)

Seamlessly switch between Delphi IDE and VS Code/WindSurf with a single hotkey, preserving file context and cursor position. Perfect for developers who want to leverage Delphi's powerful RAD designer alongside VS Code's modern editing capabilities.

## ✨ Features

- 🚀 **Instant Switching**: Press `Ctrl+Shift+D` to jump between IDEs
- 📍 **Context Preservation**: Maintains exact cursor position and file location
- 💾 **Auto-Save**: Automatically saves files before switching
- ↔️ **Bidirectional**: Works from Delphi → VS Code and VS Code → Delphi
- ⚡ **Fast Communication**: Uses Windows named pipes for < 200ms switch time
- 🎯 **Smart Focus**: Automatically brings target IDE to foreground

## 📦 Installation

### Prerequisites

- Delphi RAD Studio (10.0 or later, tested with version 12)
- VS Code (1.50+) or WindSurf
- Windows 7 or later (uses Windows named pipes)

### Quick Install

#### Option 1: From Releases (Recommended)

1. **Download the latest release** from the [Releases](https://github.com/yourusername/ide-switcher/releases) page
2. **Install Delphi Plugin**
   - Open `IDESwitcher.dpk` in Delphi IDE
   - Right-click the project → Install
   - You should see "Package IDESwitcher.bpl has been installed"

3. **Install VS Code Extension**
   ```bash
   # Install the VSIX file
   code --install-extension ide-switcher-1.0.0.vsix
   ```

#### Option 2: Build from Source

See [Building from Source](#building-from-source) section below.

For detailed installation steps and troubleshooting, see [installation-guide.md](installation-guide.md).

## 🚀 Usage

1. **Open your project** in both Delphi and VS Code
2. **Edit a file** in either IDE
3. **Press `Ctrl+Shift+D`** to switch

The target IDE will automatically:
- Come to the foreground
- Open the same file
- Position the cursor at the exact location
- Save any pending changes

![IDE Switcher Demo](https://github.com/yourusername/ide-switcher/raw/main/demo.gif)

### Customizing the Hotkey

Both IDEs must use the same hotkey. To change it:

**Delphi**: Edit `DelphiIDESwitcherPlugin.pas`:
```pascal
BindingServices.AddKeyBinding([TextToShortCut('Ctrl+Alt+S')], ...)
```

**VS Code**: Edit `package.json`:
```json
"keybindings": [{
  "command": "ide-switcher.switchToDelphi",
  "key": "ctrl+alt+s"
}]
```

See [user-manual.md](user-manual.md) for more customization options.

## 🔨 Building from Source

### Prerequisites
- Node.js (14.x or later)
- npm (comes with Node.js)
- Delphi compiler (dcc32/dcc64)

### Delphi Plugin

1. Clone the repository
2. Open `IDESwitcher.dpk` in Delphi IDE
3. Build and install:
```bash
# Or from command line:
dcc32 -B IDESwitcher.dpk
```

### VS Code Extension

1. Extract embedded configs from `vscode-extension-complete.ts`:
```bash
# The file contains package.json and tsconfig.json in comments
# Extract them to vscode-extension/ directory
```

2. Build the extension:
```bash
cd vscode-extension
npm install
npm run compile
npm install -g vsce  # If not already installed
vsce package        # Creates .vsix file
```

## 🏗️ Architecture

The system uses Windows named pipes for reliable inter-process communication:

```
┌─────────────┐     JSON Messages      ┌──────────────┐
│ Delphi IDE  │ ←─────────────────────→ │   VS Code    │
│   Plugin    │   Windows Named Pipes   │  Extension   │
└─────────────┘                         └──────────────┘
       ↓                                        ↓
  OTA Wizard                            TypeScript Ext
  Hotkey Hook                           Command Handler
```

### Communication Protocol
```json
{
  "action": "switch",
  "filePath": "C:\\Projects\\MyApp\\Unit1.pas",
  "line": 42,
  "column": 15,
  "source": "delphi",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Key Components
- **Delphi Plugin**: OTA (Open Tools API) wizard with keyboard binding
- **VS Code Extension**: TypeScript extension with command registration
- **Named Pipes**: `\\.\pipe\IDESwitcher_ToVSCode` and `\\.\pipe\IDESwitcher_ToDelphi`
- **Thread Safety**: All IDE operations synchronized to main thread

See [implementation-guidelines.md](implementation-guidelines.md) for detailed technical documentation.

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [Installation Guide](installation-guide.md) | Step-by-step setup instructions |
| [User Manual](user-manual.md) | Usage, configuration, and tips |
| [Implementation Guidelines](implementation-guidelines.md) | Technical architecture details |
| [AI Agent Instructions](ai-agent-instructions.md) | Development and modification guidance |

## 🛠️ Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| "Could not connect to pipe" | Ensure both components are installed and IDEs are running |
| Wrong cursor position | Check tab size settings match in both IDEs |
| Hotkey doesn't work | Check for conflicts in IDE keyboard shortcuts |
| File not found | Ensure using absolute paths and file exists |

### Debug Mode

Enable debug output to diagnose issues:

**Delphi**: Check Windows Debug Output (use DebugView)
**VS Code**: View → Output → Select "IDE Switcher" channel

## 📋 Requirements

- **OS**: Windows 7 or later (uses Windows named pipes)
- **Delphi**: RAD Studio 10.0+ (requires OTA support)
- **VS Code**: Version 1.50+ or WindSurf
- **Permissions**: Standard user permissions (no admin required)

## 🤝 Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Read [implementation-guidelines.md](implementation-guidelines.md) for architecture details
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built for developers who need the best of both worlds: Delphi's RAD designer and VS Code's editing power
- Thanks to the Delphi OTA documentation and VS Code extension API teams
- Inspired by similar IDE integration tools in other ecosystems

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/ide-switcher/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/ide-switcher/discussions)
- **Wiki**: [Project Wiki](https://github.com/yourusername/ide-switcher/wiki)

---

**Note**: Remember to update `yourusername` in URLs to your actual GitHub username before publishing.