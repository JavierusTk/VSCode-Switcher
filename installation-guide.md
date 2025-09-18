# IDE Switcher Installation Guide

## Overview
IDE Switcher allows seamless switching between Delphi IDE and VS Code/WindSurf with a single hotkey (Ctrl+Shift+D), preserving file context and cursor position.

## How It Works

### When you press Ctrl+Shift+D:

**From Delphi → VS Code:**
1. Delphi plugin automatically **saves** the current file
2. Gets the file path and exact cursor position
3. Sends this info to VS Code via named pipe
4. VS Code **opens** the file (or switches to it if already open)
5. Moves cursor to the exact position
6. VS Code window becomes active

**From VS Code → Delphi:**
1. VS Code extension automatically **saves** the current file
2. Gets the file path and cursor position
3. Sends this info to Delphi via named pipe
4. Delphi **opens** the file (or switches to it if already open)
5. Moves cursor to the exact position
6. Delphi window becomes active

## Part 1: Installing the Delphi IDE Plugin

### Method A: As a Package (Recommended)

1. **Create a new Package in Delphi:**
   - File → New → Other → Delphi Projects → Package
   - Save as `IDESwitcher.dpk`

2. **Add the plugin unit:**
   - Add `DelphiIDESwitcherPlugin.pas` to the package
   - Make sure "Designtime only" is checked in Project Options

3. **Compile and Install:**
   - Right-click the package in Project Manager
   - Click "Install"
   - You should see "IDE Switcher Plugin Loaded" message

### Method B: As a DLL Expert

1. **Create a new DLL project:**
   - File → New → Other → Delphi Projects → Dynamic-Link Library

2. **Add the plugin code and export function:**

```pascal
library IDESwitcherExpert;

uses
  DelphiIDESwitcherPlugin;

exports
  InitWizard name WizardEntryPoint;

begin
end.
```

3. **Build the DLL**

4. **Register with Delphi:**
   - Add to registry at: `HKEY_CURRENT_USER\Software\Embarcadero\BDS\[version]\Experts`
   - Add string value: `IDESwitcher` = `C:\Path\To\IDESwitcherExpert.dll`

## Part 2: Installing the VS Code Extension

### Method A: From VSIX (Production)

1. **Build the extension:**
```bash
# In the extension directory
npm install
npm run compile
vsce package
```

2. **Install in VS Code:**
   - Open VS Code/WindSurf
   - Press Ctrl+Shift+P
   - Run "Extensions: Install from VSIX..."
   - Select the generated `.vsix` file

### Method B: Development Mode

1. **Set up the extension:**
```bash
# Create extension directory
mkdir ide-switcher-vscode
cd ide-switcher-vscode

# Initialize
npm init -y
npm install --save-dev @types/vscode @types/node typescript

# Create folder structure
mkdir src
mkdir out
```

2. **Add the files:**
   - Copy `extension.ts` to `src/extension.ts`
   - Copy `package.json` (from the comments in the artifact)
   - Copy `tsconfig.json` (from the comments in the artifact)

3. **Compile:**
```bash
npm run compile
```

4. **Run in development:**
   - Open the extension folder in VS Code
   - Press F5 to run a new VS Code instance with the extension

## Part 3: Configuration

### Delphi Side
No additional configuration needed - the plugin uses Delphi's Open Tools API to access everything.

### VS Code Side
Optional settings in VS Code (File → Preferences → Settings):
- `ideSwitcher.autoSave`: Enable/disable auto-save (default: true)
- `ideSwitcher.delphiExecutable`: Path to Delphi if not in default location

## Testing

1. Open the same project/files in both IDEs
2. In Delphi, open a `.pas` file and place cursor anywhere
3. Press **Ctrl+Shift+D**
4. VS Code should activate with the same file and cursor position
5. Make some changes, press **Ctrl+Shift+D** again
6. Delphi should activate with your changes and cursor position

## Troubleshooting

### "Could not connect" errors
- Ensure both the Delphi plugin and VS Code extension are installed and running
- Check Windows Defender/Antivirus isn't blocking named pipes
- Try running both IDEs as Administrator (once, to establish pipe permissions)

### Hotkey conflicts
- If Ctrl+Shift+D is already used, you can change it:
  - **Delphi**: Modify `TextToShortCut('Ctrl+Shift+D')` in the plugin
  - **VS Code**: Modify keybinding in `package.json` or use Keyboard Shortcuts settings

### File not opening correctly
- Ensure the file paths are accessible from both IDEs
- Use absolute paths for files outside the project directory
- Check that both IDEs have the same working directory or project root

### Cursor position is wrong
- This usually happens with different tab settings
- Ensure both IDEs use the same tab size (spaces vs tabs)

## Architecture Notes

- **No global hotkey needed** - each IDE handles its own hotkey
- **No external process needed** - plugins communicate directly via named pipes
- **Automatic file handling** - files are saved/opened automatically
- **Fast switching** - typically < 200ms to switch
- **Reliable position tracking** - uses IDE APIs for exact positions

## Advanced: Customization

### Change the pipe names
In both Delphi plugin and VS Code extension:
```pascal
// Delphi
PIPE_NAME_TO_VSCODE = '\\.\pipe\YourCustomPipe_ToVSCode';
PIPE_NAME_FROM_VSCODE = '\\.\pipe\YourCustomPipe_ToDelphi';
```

```typescript
// VS Code
const PIPE_TO_DELPHI = '\\\\.\\pipe\\YourCustomPipe_ToDelphi';
const PIPE_FROM_DELPHI = '\\\\.\\pipe\\YourCustomPipe_ToVSCode';
```

### Add more context
Modify the JSON structure to include:
- Selected text
- Bookmarks
- Breakpoints
- Folded regions
- Multiple cursor positions

## Uninstalling

### Delphi Plugin
- If installed as package: Component → Install Packages → Remove
- If installed as DLL: Remove registry entry and delete DLL

### VS Code Extension
- Extensions panel → IDE Switcher → Uninstall