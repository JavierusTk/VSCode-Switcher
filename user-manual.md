# IDE Switcher User Manual

## Quick Start

Once installed, simply press **Ctrl+Shift+D** in either Delphi or VS Code/WindSurf to switch between them.

## Features

### Automatic File Synchronization
- **Auto-save**: Files are automatically saved before switching
- **Auto-open**: Files automatically open in the target IDE
- **Position preservation**: Cursor position is maintained exactly

### Supported Scenarios

#### Basic Switching
- **Single file editing**: Edit the same file in both IDEs seamlessly
- **Project navigation**: Switch while navigating through multiple files
- **Quick corrections**: Jump to Delphi for IntelliSense, back to WindSurf for AI assistance

#### Advanced Use Cases

1. **Mixed development workflow**
   - Write code structure in Delphi with full IntelliSense
   - Switch to WindSurf for AI-powered completion
   - Switch back to Delphi for debugging

2. **Code review workflow**
   - Review in VS Code with better Git integration
   - Fix issues in Delphi with compiler feedback
   - Seamlessly move between both

3. **Learning workflow**
   - Use WindSurf's AI to generate code examples
   - Study and debug in Delphi's familiar environment

## Usage Instructions

### Basic Operation

1. **Ensure both IDEs have access to the same files**
   - Open the same project/folder in both IDEs
   - Or work with standalone files accessible to both

2. **Start editing in either IDE**
   - Open any source file
   - Position your cursor where you're working

3. **Press Ctrl+Shift+D to switch**
   - Current file is saved
   - Other IDE activates
   - Same file opens at same position

4. **Continue working**
   - Make changes
   - Press Ctrl+Shift+D to switch back
   - Changes are preserved

### Keyboard Shortcuts

| Action | Shortcut | Where |
|--------|----------|-------|
| Switch to other IDE | Ctrl+Shift+D | Both IDEs |
| Cancel switch | Esc | During switch |

### Status Indicators

#### In Delphi
- Plugin loaded: "IDE Switcher Plugin Loaded" message on startup
- Switch initiated: File saves automatically
- Error: Message dialog appears

#### In VS Code/WindSurf
- Extension active: "IDE Switcher Ready" notification
- Switch initiated: File saves automatically  
- Error: Notification in bottom-right corner

## Best Practices

### File Organization
✅ **DO:**
- Keep files in consistent locations
- Use the same project root in both IDEs
- Maintain consistent file encoding (UTF-8 recommended)

❌ **DON'T:**
- Use symbolic links that only one IDE can resolve
- Edit files on network drives with different mappings
- Use different line endings in each IDE

### Workflow Tips

1. **For maximum efficiency:**
   - Set up identical formatting rules in both IDEs
   - Use the same tab size (spaces vs tabs)
   - Configure similar color themes to reduce visual jarring

2. **For debugging:**
   - Set breakpoints in Delphi
   - Write test code in WindSurf with AI help
   - Switch to Delphi to run and debug

3. **For refactoring:**
   - Use Delphi's refactoring tools for type-safe changes
   - Use VS Code's multi-cursor and regex for text manipulation
   - Switch between them as needed

## Troubleshooting

### Common Issues

#### "File not found" after switching
**Cause**: Different working directories
**Solution**: Use absolute paths or ensure both IDEs open the same project folder

#### Cursor position is off by a few characters
**Cause**: Different tab settings
**Solution**: Configure both IDEs to use the same tab width and space/tab preference

#### Switching is slow (>1 second)
**Cause**: Large file being saved or antivirus scanning
**Solution**: 
- Exclude project folders from real-time antivirus scanning
- Ensure files are on local SSD, not network drive

#### Hotkey doesn't work
**Cause**: Another application or IDE plugin using Ctrl+Shift+D
**Solution**: 
- Check keyboard shortcut conflicts in both IDEs
- Temporarily disable other extensions to identify conflicts

### Error Messages

| Error | Meaning | Solution |
|-------|---------|----------|
| "No active file to switch" | No file is open in current IDE | Open a file before switching |
| "Could not connect to [IDE]" | Target IDE plugin/extension not running | Ensure both components are installed and active |
| "File save failed" | Current file couldn't be saved | Check file permissions and disk space |
| "Invalid cursor position" | Position data corrupted | Try switching again, restart if persists |

## Configuration

### VS Code Settings
Access via: File → Preferences → Settings → Extensions → IDE Switcher

- **ideSwitcher.autoSave**: `true/false` - Enable automatic saving
- **ideSwitcher.delphiExecutable**: `"path"` - Custom Delphi IDE location
- **ideSwitcher.showNotifications**: `true/false` - Show status notifications
- **ideSwitcher.switchDelay**: `number` - Milliseconds to wait before switching

### Delphi Settings
Currently configured in source code constants. Future version will have IDE options dialog.

## Limitations

### Current Limitations
- **Windows only**: Uses Windows named pipes for communication
- **Single instance**: Only one instance of each IDE supported
- **Text files only**: Binary files don't preserve cursor position
- **Local files**: Network files may have delays

### Planned Features
- Multiple IDE instance support
- Project-wide state preservation (all open files)
- Bookmark and breakpoint synchronization
- Selected text preservation
- Folded code region synchronization

## Tips & Tricks

### Power User Features

1. **Rapid prototyping:**
   - Generate boilerplate with WindSurf AI
   - Switch to Delphi
   - Compile and test
   - Switch back for AI refinements

2. **Learning new APIs:**
   - Ask WindSurf AI for examples
   - Switch to Delphi to see IntelliSense
   - Understand the types and parameters
   - Switch back to ask follow-up questions

3. **Code review preparation:**
   - Write code in Delphi
   - Switch to VS Code
   - Use GitLens to see history
   - Make review-based changes
   - Switch back to test

### Performance Tips

- **Faster switching**: Keep both IDEs on SSD
- **Reduce delay**: Disable auto-save if you manually save
- **Smoother transition**: Use similar themes in both IDEs
- **Better accuracy**: Use fixed-width fonts in both IDEs

## FAQ

**Q: Can I change the hotkey?**
A: Not through UI yet. Edit source code and recompile.

**Q: Does it work with Lazarus instead of Delphi?**
A: Not tested, but should work with minor modifications.

**Q: Can I use it with other VS Code forks?**
A: Yes, any VS Code-based editor (WindSurf, Cursor, etc.) should work.

**Q: Is my code sent anywhere?**
A: No, all communication is local between your IDEs only.

**Q: Can multiple developers use this on the same machine?**
A: Yes, named pipes are user-session specific.

**Q: Does it work with Remote SSH in VS Code?**
A: No, both IDEs must be on the same machine.

## Support

For issues, feature requests, or contributions:
- Check the Implementation Guidelines document for technical details
- See the AI Agent Instructions for code structure
- Report bugs with: IDE versions, Windows version, error messages

## Version History

- **v1.0.0**: Initial release
  - Basic switching functionality
  - Auto-save and auto-open
  - Cursor position preservation