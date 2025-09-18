// extension.ts - Main VS Code extension for IDE Switcher

import * as vscode from 'vscode';
import * as net from 'net';
import * as path from 'path';

const PIPE_TO_DELPHI = '\\\\.\\pipe\\IDESwitcher_ToDelphi';
const PIPE_FROM_DELPHI = '\\\\.\\pipe\\IDESwitcher_ToVSCode';

let pipeServer: net.Server | undefined;

export function activate(context: vscode.ExtensionContext) {
    console.log('IDE Switcher extension is now active');

    // Start the pipe server to receive requests from Delphi
    startPipeServer();

    // Register the command and keyboard shortcut
    const switchCommand = vscode.commands.registerCommand('ideSwitcher.switchToDelphi', () => {
        switchToDelphi();
    });

    context.subscriptions.push(switchCommand);

    // Show notification that extension is ready
    vscode.window.showInformationMessage(
        'IDE Switcher Ready - Press Ctrl+Shift+D to switch to Delphi'
    );
}

export function deactivate() {
    if (pipeServer) {
        pipeServer.close();
    }
}

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

        // Step 2: Get current file info
        const fileInfo = {
            action: 'switch',
            filePath: editor.document.fileName,
            line: editor.selection.active.line + 1, // VS Code uses 0-based indexing
            column: editor.selection.active.character + 1,
            source: 'vscode',
            timestamp: new Date().toISOString()
        };

        console.log('Switching to Delphi with:', fileInfo);

        // Step 3: Send to Delphi
        await sendToDelphi(fileInfo);

    } catch (error) {
        vscode.window.showErrorMessage(`Error switching to Delphi: ${error}`);
        console.error('Switch error:', error);
    }
}

/**
 * Sends file information to Delphi via named pipe
 */
function sendToDelphi(fileInfo: any): Promise<void> {
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
                '}"', 
                (error: any) => {
                    if (error) {
                        reject(new Error('Could not connect to Delphi. Is the IDE plugin installed?'));
                    } else {
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
            } catch (error) {
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
async function handleDelphiRequest(request: any) {
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
        const position = new vscode.Position(
            Math.max(0, (request.line || 1) - 1),  // Convert to 0-based
            Math.max(0, (request.column || 1) - 1)
        );
        
        const selection = new vscode.Selection(position, position);
        editor.selection = selection;
        
        // Center the cursor in the viewport
        editor.revealRange(
            new vscode.Range(position, position),
            vscode.TextEditorRevealType.InCenter
        );
        
        // Focus VS Code window
        vscode.commands.executeCommand('workbench.action.focusActiveEditorGroup');
        
    } catch (error) {
        console.error('Error opening file from Delphi:', error);
        vscode.window.showErrorMessage(`Could not open file: ${request.filePath}`);
    }
}

// === package.json ===
/*
{
    "name": "ide-switcher",
    "displayName": "IDE Switcher",
    "description": "Switch between VS Code/WindSurf and Delphi IDE seamlessly",
    "version": "1.0.0",
    "publisher": "your-publisher-name",
    "engines": {
        "vscode": "^1.74.0"
    },
    "categories": ["Other"],
    "activationEvents": [
        "onStartupFinished"
    ],
    "main": "./out/extension.js",
    "contributes": {
        "commands": [
            {
                "command": "ideSwitcher.switchToDelphi",
                "title": "Switch to Delphi IDE"
            }
        ],
        "keybindings": [
            {
                "command": "ideSwitcher.switchToDelphi",
                "key": "ctrl+shift+d",
                "when": "editorTextFocus"
            }
        ],
        "configuration": {
            "title": "IDE Switcher",
            "properties": {
                "ideSwitcher.delphiExecutable": {
                    "type": "string",
                    "default": "",
                    "description": "Path to Delphi IDE executable (optional)"
                },
                "ideSwitcher.autoSave": {
                    "type": "boolean",
                    "default": true,
                    "description": "Automatically save files before switching"
                }
            }
        }
    },
    "scripts": {
        "vscode:prepublish": "npm run compile",
        "compile": "tsc -p ./",
        "watch": "tsc -watch -p ./"
    },
    "devDependencies": {
        "@types/vscode": "^1.74.0",
        "@types/node": "^16.x",
        "typescript": "^4.9.5"
    }
}
*/

// === tsconfig.json ===
/*
{
    "compilerOptions": {
        "module": "commonjs",
        "target": "ES2020",
        "outDir": "out",
        "lib": ["ES2020"],
        "sourceMap": true,
        "rootDir": "src",
        "strict": true
    },
    "exclude": ["node_modules", ".vscode-test"]
}
*/

// === README.md ===
/*
# IDE Switcher - VS Code Extension

Seamlessly switch between VS Code/WindSurf and Delphi IDE while maintaining file context and cursor position.

## Features

- **Ctrl+Shift+D**: Switch to Delphi IDE with current file and cursor position
- Automatically saves files before switching
- Receives switch requests from Delphi and opens files at the correct position
- No external programs needed - communication via named pipes

## Installation

1. Install the Delphi IDE plugin (DelphiIDESwitcherPlugin.pas)
2. Install this VS Code extension
3. Both IDEs will now be connected!

## Usage

Press `Ctrl+Shift+D` in either IDE to switch to the other:
- Files are automatically saved
- The same file opens in the target IDE
- Cursor position is preserved

## Requirements

- Windows OS (uses Windows named pipes)
- Delphi IDE with the companion plugin installed
- VS Code 1.74.0 or higher

## Configuration

- `ideSwitcher.delphiExecutable`: Path to Delphi IDE (optional)
- `ideSwitcher.autoSave`: Automatically save files before switching (default: true)
*/