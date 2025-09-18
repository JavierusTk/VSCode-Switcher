# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

IDE Switcher enables seamless switching between Delphi IDE and VS Code/WindSurf with a single hotkey (Ctrl+Shift+D), preserving file context and cursor position. It consists of two components communicating via Windows named pipes using JSON messages.

## Project Structure

```
ide-switcher/
├── delphi-ide-plugin-complete.pas    # Complete Delphi plugin source
├── vscode-extension-complete.ts      # Complete VS Code extension (includes package.json and tsconfig.json in comments)
├── installation-guide.md              # Step-by-step installation instructions
├── user-manual.md                     # End-user documentation
├── implementation-guidelines.md      # Technical architecture details
├── ai-agent-instructions.md         # AI-specific development guidance
└── documentation-overview.md         # Documentation map
```

## Architecture

### Components
- **Delphi Plugin** (`DelphiIDESwitcherPlugin.pas`): OTA wizard with keyboard binding and pipe server thread
- **VS Code Extension** (`vscode-extension-complete.ts`): TypeScript extension with command registration and pipe communication

### Communication Protocol
```json
{
  "action": "switch",
  "filePath": "C:\\Projects\\Unit1.pas",
  "line": 42,
  "column": 15,
  "source": "delphi|vscode",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

### Named Pipes
- `\\.\pipe\IDESwitcher_ToVSCode` (Delphi → VS Code)
- `\\.\pipe\IDESwitcher_ToDelphi` (VS Code → Delphi)

## Build Commands

### Delphi Plugin
```bash
# Create package project (IDESwitcher.dpk) with DelphiIDESwitcherPlugin.pas
# Set as "Designtime only" in Project Options
# Then compile:
compilar IDESwitcher.dpk
```

### VS Code Extension
```bash
# Extract package.json and tsconfig.json from vscode-extension-complete.ts comments
# Place extension.ts in src/ directory
npm install
npm run compile
vsce package  # Creates .vsix for installation
```

## Critical Implementation Details

### Thread Safety (Delphi)
⚠️ **ALWAYS** use `TThread.Synchronize` for OTA calls from pipe server thread:
```pascal
TThread.Synchronize(nil, procedure
begin
  HandleVSCodeRequest(Message);  // OTA calls must be in main thread
end);
```

### Index Conversion
⚠️ VS Code uses 0-based indexing, Delphi uses 1-based:
```typescript
// VS Code → Delphi: add 1
line: editor.selection.active.line + 1

// Delphi → VS Code: subtract 1
new vscode.Position((request.line || 1) - 1, (request.column || 1) - 1)
```

### Pipe Name Matching
⚠️ Must match exactly between components (note escaping differences):
```pascal
// Delphi
PIPE_NAME_TO_VSCODE = '\\.\pipe\IDESwitcher_ToVSCode';
```
```typescript
// VS Code (extra escaping needed)
const PIPE_FROM_DELPHI = '\\\\.\\pipe\\IDESwitcher_ToVSCode';
```

## Common Modifications

### Change Hotkey
1. **Delphi**: In `BindKeyboard` method:
```pascal
BindingServices.AddKeyBinding([TextToShortCut('Ctrl+Alt+S')], HandleSwitchToVSCode, nil);
```

2. **VS Code**: In package.json keybindings:
```json
"key": "ctrl+alt+s"
```

### Add Logging
**Delphi**:
```pascal
OutputDebugString(PChar('IDESwitcher: ' + Message));
```

**VS Code**:
```typescript
const outputChannel = vscode.window.createOutputChannel('IDE Switcher');
outputChannel.appendLine(message);
```

## Testing Checklist

- [ ] Both components installed and loaded
- [ ] Same file opens in target IDE
- [ ] Cursor position preserved exactly
- [ ] File auto-saves before switch
- [ ] Window focus changes correctly
- [ ] Error handling for missing files
- [ ] Retry mechanism for pipe failures

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Could not connect" | Plugin/extension not running | Verify both components installed |
| Wrong cursor position | Different tab settings | Match tab size in both IDEs |
| File not found | Different working directories | Use absolute paths |
| Hotkey doesn't work | Conflict with other extension | Check keyboard shortcuts in both IDEs |

## Documentation Map

- **Quick start**: `installation-guide.md` → `user-manual.md`
- **Development**: `ai-agent-instructions.md` → `implementation-guidelines.md`
- **Troubleshooting**: Check error sections in all docs
- **Architecture details**: `implementation-guidelines.md`

## Performance Targets

- Switch time: < 200ms
- File save: < 50ms
- Pipe communication: < 10ms
- Window activation: < 100ms