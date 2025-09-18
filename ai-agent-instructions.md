# IDE Switcher - AI Agent Instructions (for Claude Code)

## Project Overview for AI Agents

You are working with **IDE Switcher**, a tool that enables seamless switching between Delphi IDE and VS Code/WindSurf while preserving file context and cursor position.

### Quick Context
- **Purpose**: Switch between IDEs with a hotkey (Ctrl+Shift+D)
- **Architecture**: Two components communicating via Windows named pipes
- **Languages**: Pascal/Delphi (plugin) and TypeScript (VS Code extension)
- **Platform**: Windows only (uses named pipes)

## Component Structure

### 📁 Project Files

```
ide-switcher/
├── delphi-plugin/
│   ├── DelphiIDESwitcherPlugin.pas    # Main plugin source
│   ├── IDESwitcher.dpk                # Delphi package file
│   └── README.md                      # Plugin documentation
├── vscode-extension/
│   ├── src/
│   │   └── extension.ts               # Main extension source
│   ├── package.json                   # Extension manifest
│   ├── tsconfig.json                  # TypeScript config
│   └── README.md                      # Extension documentation
└── docs/
    ├── user-manual.md                 # For end users
    ├── implementation-guidelines.md   # For developers
    └── ai-agent-instructions.md      # This file
```

## Key Concepts for AI Understanding

### 1. Inter-Process Communication (IPC)
The two IDEs communicate using **Windows Named Pipes**:
- **Synchronous**: Request-response pattern
- **JSON messages**: Structured data exchange
- **Two pipes**: One for each direction

### 2. IDE APIs
Each component uses its IDE's native API:
- **Delphi**: Open Tools API (OTA)
- **VS Code**: Extension API

### 3. No Global State
- Each IDE maintains its own state
- No shared memory or files
- Communication is stateless

## Common Modification Requests

### Request: "Add support for multiple files"

**Current State**: Switches single active file
**Modification Points**:

1. **Protocol Change** (both components):
```json
// Change from:
{"filePath": "...", "line": 1, "column": 1}
// To:
{"files": [{"path": "...", "line": 1, "column": 1, "active": true}]}
```

2. **Delphi Plugin** - Modify `GetCurrentEditorInfo`:
```pascal
// Iterate through all open modules
for I := 0 to ModuleServices.ModuleCount - 1 do
  Module := ModuleServices.Modules[I];
```

3. **VS Code Extension** - Modify `switchToDelphi`:
```typescript
// Get all visible editors
const editors = vscode.window.visibleTextEditors;
```

### Request: "Change the hotkey"

**Modification Points**:

1. **Delphi Plugin** - In `BindKeyboard` method:
```pascal
// Change this line:
BindingServices.AddKeyBinding([TextToShortCut('Ctrl+Shift+D')], HandleSwitchToVSCode, nil);
// To your desired shortcut:
BindingServices.AddKeyBinding([TextToShortCut('Ctrl+Alt+S')], HandleSwitchToVSCode, nil);
```

2. **VS Code Extension** - In `package.json`:
```json
"keybindings": [{
  "command": "ideSwitcher.switchToDelphi",
  "key": "ctrl+alt+s",  // Changed from ctrl+shift+d
  "when": "editorTextFocus"
}]
```

### Request: "Add configuration settings"

**For VS Code** (already has infrastructure):
1. Add to `package.json` under `contributes.configuration`
2. Access in code: `vscode.workspace.getConfiguration('ideSwitcher')`

**For Delphi** (needs implementation):
1. Add INI file handling:
```pascal
uses IniFiles;

procedure LoadSettings;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'IDESwitcher.ini');
  try
    FPipeName := Ini.ReadString('Settings', 'PipeName', PIPE_NAME_DEFAULT);
    FShortcut := Ini.ReadString('Settings', 'Shortcut', 'Ctrl+Shift+D');
  finally
    Ini.Free;
  end;
end;
```

### Request: "Add logging"

**For debugging issues**, add logging:

1. **Delphi Plugin**:
```pascal
procedure Log(const Msg: string);
var
  F: TextFile;
begin
  AssignFile(F, 'C:\Temp\IDESwitcher_Delphi.log');
  if FileExists('C:\Temp\IDESwitcher_Delphi.log') then
    Append(F)
  else
    Rewrite(F);
  WriteLn(F, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' - ' + Msg);
  CloseFile(F);
end;
```

2. **VS Code Extension**:
```typescript
const outputChannel = vscode.window.createOutputChannel('IDE Switcher');
outputChannel.appendLine(`[${new Date().toISOString()}] ${message}`);
```

## Critical Code Sections

### ⚠️ Thread Safety (Delphi)

**ALWAYS** use `TThread.Synchronize` when calling OTA from pipe server thread:
```pascal
TThread.Synchronize(nil, procedure
begin
  OpenFileInDelphi(FilePath, Line, Column);  // OTA calls must be in main thread
end);
```

### ⚠️ Index Conversion (VS Code ↔ Delphi)

**Remember**: VS Code uses 0-based indexing, Delphi uses 1-based:
```typescript
// VS Code → Delphi
const delphiLine = vscodeLine + 1;
const delphiColumn = vscodeColumn + 1;

// Delphi → VS Code  
const vscodeLine = delphiLine - 1;
const vscodeColumn = delphiColumn - 1;
```

### ⚠️ Pipe Names

**Must match exactly** between components:
```pascal
// Delphi
PIPE_NAME_TO_VSCODE = '\\.\pipe\IDESwitcher_ToVSCode';
PIPE_NAME_FROM_VSCODE = '\\.\pipe\IDESwitcher_ToDelphi';
```

```typescript
// VS Code (note the extra escaping)
const PIPE_TO_DELPHI = '\\\\.\\pipe\\IDESwitcher_ToDelphi';
const PIPE_FROM_DELPHI = '\\\\.\\pipe\\IDESwitcher_ToVSCode';
```

## Testing Modifications

### After Any Change

1. **Compile Delphi plugin**:
```
- Open IDESwitcher.dpk in Delphi
- Right-click → Install
- Should see "IDE Switcher Plugin Loaded"
```

2. **Build VS Code extension**:
```bash
cd vscode-extension
npm run compile
# Then F5 in VS Code to test
```

3. **Test both directions**:
```
- Open same file in both IDEs
- Press Ctrl+Shift+D in Delphi → VS Code should activate
- Press Ctrl+Shift+D in VS Code → Delphi should activate
- Cursor position should be preserved
```

## Common Errors and Solutions

### Error: "Could not connect to pipe"

**Diagnosis Steps**:
1. Check if both components are running
2. Verify pipe names match exactly
3. Check Windows Defender/antivirus
4. Try running as administrator once

**Code to add for debugging**:
```pascal
ShowMessage('Attempting to connect to pipe: ' + FPipeName);
```

### Error: "File not found after switch"

**Common Causes**:
1. Different working directories
2. Relative vs absolute paths
3. Path separator differences (/ vs \)

**Fix**:
```pascal
FilePath := ExpandFileName(FilePath);  // Convert to absolute
FilePath := StringReplace(FilePath, '/', '\', [rfReplaceAll]);
```

### Error: "Cursor position wrong"

**Check**:
1. Tab size settings in both IDEs
2. Line ending differences (CRLF vs LF)
3. Index conversion (0-based vs 1-based)

## Adding New Features - Checklist

When adding a new feature, ensure you:

- [ ] Update the JSON protocol in both components
- [ ] Handle backward compatibility (version check)
- [ ] Add error handling for edge cases
- [ ] Update both components (Delphi + VS Code)
- [ ] Test bidirectional communication
- [ ] Update user documentation
- [ ] Add configuration option if applicable
- [ ] Consider thread safety in Delphi
- [ ] Handle missing/null values in JSON
- [ ] Test with files of different encodings

## Performance Considerations

### Current Benchmarks
- Switch time: ~150-200ms
- File save: ~20-50ms  
- Pipe communication: ~5-10ms
- Window activation: ~100ms

### When Optimizing

**DO**:
- Profile first to find actual bottlenecks
- Cache window handles
- Reuse pipe connections
- Use async operations where possible

**DON'T**:
- Pre-optimize without measuring
- Keep pipes open indefinitely
- Poll for changes
- Block the UI thread

## Code Style Guidelines

### Delphi/Pascal
```pascal
// Use meaningful names
procedure OpenFileInDelphi(const FilePath: string; Line, Column: Integer);

// Not:
procedure OpenFile(f: string; l, c: Integer);

// Always free objects
JSONObject := TJSONObject.Create;
try
  // Use JSONObject
finally
  JSONObject.Free;
end;
```

### TypeScript
```typescript
// Use async/await over callbacks
async function switchToDelphi(): Promise<void> {
  await saveFile();
  await sendToDelphi(data);
}

// Type everything
interface IDEMessage {
  action: string;
  filePath: string;
  line: number;
  column: number;
}
```

## Extending the Protocol

### Current Protocol v1.0
```typescript
interface SwitchMessage {
  action: 'switch';
  filePath: string;
  line: number;
  column: number;
  source: 'delphi' | 'vscode';
  timestamp: string;
}
```

### To Add New Action Types

1. **Define the message type**:
```typescript
interface SyncBookmarksMessage {
  action: 'syncBookmarks';
  bookmarks: Array<{line: number; description: string}>;
  filePath: string;
}
```

2. **Update message handlers**:
```typescript
// VS Code
switch (message.action) {
  case 'switch':
    handleSwitch(message);
    break;
  case 'syncBookmarks':  // New
    handleSyncBookmarks(message);
    break;
}
```

3. **Implement in both components**
4. **Consider backward compatibility**

## Deployment Checklist

Before releasing a new version:

- [ ] Test on clean Delphi installation
- [ ] Test on clean VS Code installation  
- [ ] Test with different Delphi versions (XE7, 10.x, 11.x, 12.x)
- [ ] Test with VS Code and WindSurf
- [ ] Update version numbers in both components
- [ ] Update documentation
- [ ] Create release notes
- [ ] Build release artifacts (.dpk and .vsix)
- [ ] Test upgrade from previous version

## Quick Reference for AI Agents

### To modify Delphi plugin:
1. Main file: `DelphiIDESwitcherPlugin.pas`
2. Key class: `TIDESwitcherWizard`
3. Hotkey handler: `HandleSwitchToVSCode`
4. Pipe server: `TPipeServerThread.Execute`
5. Compile: Open `.dpk` → Install

### To modify VS Code extension:
1. Main file: `src/extension.ts`
2. Entry point: `activate()` function
3. Hotkey handler: `switchToDelphi()`
4. Pipe server: `startPipeServer()`
5. Build: `npm run compile`

### Communication flow:
```
User presses Ctrl+Shift+D in Delphi
→ HandleSwitchToVSCode() saves file
→ Gets file info via OTA
→ Sends JSON to VS Code pipe
→ VS Code receives in pipe server
→ Opens file and positions cursor
→ Activates VS Code window
```

## Final Notes for AI Agents

- **Always preserve backward compatibility** when possible
- **Test bidirectionally** - both IDE directions must work
- **Keep it simple** - this tool should be invisible to users
- **Document changes** - update this file for future AI agents
- **Consider Windows-only** - all path handling is Windows-specific
- **Respect IDE quirks** - Each IDE has unique behaviors

When in doubt, maintain the current architecture's simplicity rather than adding complexity. The tool's beauty is in its seamless, invisible operation.