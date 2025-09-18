"use strict";
// extension.ts - Main VS Code extension for IDE Switcher
Object.defineProperty(exports, "__esModule", { value: true });
exports.deactivate = exports.activate = void 0;
const vscode = require("vscode");
const net = require("net");
const PIPE_TO_DELPHI = '\\\\.\\pipe\\IDESwitcher_ToDelphi';
const PIPE_FROM_DELPHI = '\\\\.\\pipe\\IDESwitcher_ToVSCode';
let pipeServer;
function activate(context) {
    console.log('IDE Switcher extension is now active');
    // Start the pipe server to receive requests from Delphi
    startPipeServer();
    // Register the command and keyboard shortcut
    const switchCommand = vscode.commands.registerCommand('ideSwitcher.switchToDelphi', () => {
        switchToDelphi();
    });
    context.subscriptions.push(switchCommand);
    // Show notification that extension is ready
    vscode.window.showInformationMessage('IDE Switcher Ready - Press Ctrl+Shift+D to switch to Delphi');
}
exports.activate = activate;
function deactivate() {
    if (pipeServer) {
        pipeServer.close();
    }
}
exports.deactivate = deactivate;
/**
 * Handles switching from VS Code to Delphi
 * 1. Saves current file
 * 2. Gets current file path and cursor position
 * 3. Sends this info to Delphi
 */
async function switchToDelphi() {
    try {
        const editor = vscode.window.activeTextEditor;
        if (!editor) {
            vscode.window.showWarningMessage('No active editor to switch from');
            return;
        }
        // Step 1: Save the current file
        if (editor.document.isDirty) {
            await editor.document.save();
        }
        // Step 2: Get current file info with process ID
        const fileInfo = {
            action: 'switch',
            filePath: editor.document.fileName,
            line: editor.selection.active.line + 1,
            column: editor.selection.active.character + 1,
            source: 'vscode',
            pid: process.pid,
            timestamp: new Date().toISOString()
        };
        console.log('Switching to Delphi with:', fileInfo);
        // Step 3: Send to Delphi
        await sendToDelphi(fileInfo);
    }
    catch (error) {
        vscode.window.showErrorMessage(`Error switching to Delphi: ${error}`);
        console.error('Switch error:', error);
    }
}
/**
 * Sends file information to Delphi via named pipe
 */
function sendToDelphi(fileInfo) {
    return new Promise((resolve, reject) => {
        const client = net.createConnection(PIPE_TO_DELPHI, () => {
            const message = JSON.stringify(fileInfo);
            client.write(message);
            client.end();
            resolve();
        });
        client.on('error', (err) => {
            console.error('Pipe connection error:', err);
            // If pipe fails, try to activate Delphi window anyway
            const { exec } = require('child_process');
            // Try to bring Delphi to foreground using Windows commands
            exec('powershell -Command "' +
                '$delphi = Get-Process | Where-Object {$_.MainWindowTitle -like \'*Delphi*\' -or $_.ProcessName -like \'*bds*\'}; ' +
                'if ($delphi) { ' +
                '  Add-Type @\\"' +
                '    using System;' +
                '    using System.Runtime.InteropServices;' +
                '    public class Win32 {' +
                '      [DllImport(\\"user32.dll\\")]' +
                '      public static extern bool SetForegroundWindow(IntPtr hWnd);' +
                '      [DllImport(\\"user32.dll\\")]' +
                '      public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);' +
                '    }' +
                '\\"@; ' +
                '  [Win32]::ShowWindow($delphi[0].MainWindowHandle, 9); ' +
                '  [Win32]::SetForegroundWindow($delphi[0].MainWindowHandle) ' +
                '}"', (error) => {
                if (error) {
                    reject(new Error('Could not connect to Delphi. Is the IDE plugin installed?'));
                }
                else {
                    resolve();
                }
            });
        });
        // Set a timeout for the connection
        setTimeout(() => {
            client.destroy();
            reject(new Error('Connection to Delphi timed out'));
        }, 5000);
    });
}
/**
 * Starts the pipe server to receive requests from Delphi
 */
function startPipeServer() {
    pipeServer = net.createServer((client) => {
        let data = '';
        client.on('data', (chunk) => {
            data += chunk.toString();
        });
        client.on('end', () => {
            try {
                const request = JSON.parse(data);
                handleDelphiRequest(request);
            }
            catch (error) {
                console.error('Error parsing request from Delphi:', error);
            }
        });
        client.on('error', (err) => {
            console.error('Pipe server error:', err);
        });
    });
    pipeServer.listen(PIPE_FROM_DELPHI, () => {
        console.log('IDE Switcher pipe server listening for Delphi requests');
    });
    pipeServer.on('error', (err) => {
        console.error('Failed to start pipe server:', err);
        // Retry after a delay
        setTimeout(() => {
            if (pipeServer) {
                pipeServer.close();
            }
            startPipeServer();
        }, 5000);
    });
}
/**
 * Handles requests received from Delphi
 * Opens the specified file at the given position
 */
async function handleDelphiRequest(request) {
    console.log('Received request from Delphi:', request);
    if (request.action !== 'switch' || !request.filePath) {
        return;
    }
    try {
        // Open the document
        const document = await vscode.workspace.openTextDocument(request.filePath);
        // Show the document in the editor
        const editor = await vscode.window.showTextDocument(document);
        // Set cursor position
        const position = new vscode.Position(Math.max(0, (request.line || 1) - 1), // Convert to 0-based
        Math.max(0, (request.column || 1) - 1));
        const selection = new vscode.Selection(position, position);
        editor.selection = selection;
        // Center the cursor in the viewport
        editor.revealRange(new vscode.Range(position, position), vscode.TextEditorRevealType.InCenter);
        // Focus VS Code window
        vscode.commands.executeCommand('workbench.action.focusActiveEditorGroup');
        // Bring VS Code/WindSurf to foreground using Windows automation
        const { exec } = require('child_process');
        // Create a PowerShell script that finds and focuses the window
        // This works for both VS Code and Windsurf
        const focusScript = `
            Add-Type @"
                using System;
                using System.Runtime.InteropServices;
                using System.Diagnostics;

                public class Win32Window {
                    [DllImport("user32.dll")]
                    public static extern bool SetForegroundWindow(IntPtr hWnd);

                    [DllImport("user32.dll")]
                    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

                    [DllImport("user32.dll")]
                    public static extern bool BringWindowToTop(IntPtr hWnd);

                    [DllImport("user32.dll")]
                    public static extern IntPtr GetForegroundWindow();

                    [DllImport("user32.dll")]
                    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

                    [DllImport("user32.dll")]
                    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

                    [DllImport("kernel32.dll")]
                    public static extern uint GetCurrentThreadId();

                    public static void ForceForegroundWindow(IntPtr hWnd) {
                        uint foreThread = GetWindowThreadProcessId(GetForegroundWindow(), out uint temp);
                        uint appThread = GetCurrentThreadId();

                        if (foreThread != appThread) {
                            AttachThreadInput(foreThread, appThread, true);
                            BringWindowToTop(hWnd);
                            ShowWindow(hWnd, 9); // SW_RESTORE
                            SetForegroundWindow(hWnd);
                            AttachThreadInput(foreThread, appThread, false);
                        } else {
                            BringWindowToTop(hWnd);
                            ShowWindow(hWnd, 9);
                            SetForegroundWindow(hWnd);
                        }
                    }
                }
"@

            # Try to find Windsurf first, then VS Code
            $process = Get-Process -Name "Windsurf","Code" -ErrorAction SilentlyContinue |
                       Where-Object { $_.MainWindowHandle -ne 0 } |
                       Select-Object -First 1

            if ($process) {
                [Win32Window]::ForceForegroundWindow($process.MainWindowHandle)
                Write-Output "Window focused"
            } else {
                Write-Output "No window found"
            }
        `.replace(/\n/g, ' ');
        // Execute the PowerShell script
        exec(`powershell -WindowStyle Hidden -Command "${focusScript}"`, (error, stdout, stderr) => {
            if (error) {
                console.error('Failed to focus window:', error);
            }
            else {
                console.log('Window focus result:', stdout);
            }
        });
    }
    catch (error) {
        console.error('Error opening file from Delphi:', error);
        vscode.window.showErrorMessage(`Could not open file: ${request.filePath}`);
    }
}
//# sourceMappingURL=extension.js.map