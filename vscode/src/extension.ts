import * as vscode from 'vscode';
import { LanguageClient, TransportKind } from 'vscode-languageclient/node';
import {
  SERVER_FAILURE_MESSAGE,
  SUPPORTED_DIALECTS,
  SUPPORTED_PROFILES,
  resolveFathomConfiguration,
} from './extension-contract.ts';

export { SERVER_FAILURE_MESSAGE, SUPPORTED_DIALECTS, SUPPORTED_PROFILES, resolveFathomConfiguration } from './extension-contract.ts';

let client;
let statusItem;

export function createServerOptions(serverPath) {
  const local = { command: serverPath, args: [], transport: TransportKind.stdio };
  return { run: local, debug: local };
}

function showServerFailure(error) {
  const detail = error instanceof Error && error.message ? ` ${error.message}` : '';
  vscode.window.showErrorMessage(`${SERVER_FAILURE_MESSAGE}${detail}`);
  if (statusItem) {
    statusItem.text = 'Fathom: unavailable';
    statusItem.tooltip = SERVER_FAILURE_MESSAGE;
  }
}

async function stopClient() {
  if (!client) return;
  const current = client;
  client = undefined;
  try {
    await current.stop();
  } catch (error) {
    showServerFailure(error);
  }
}

export async function activate(context) {
  // vscode-languageclient@10 requires a LogOutputChannel (`.error`/`.trace`/
  // `onDidChangeLogLevel`), so the channel must be created with `{ log: true }`.
  const outputChannel = vscode.window.createOutputChannel('Fathom SQL Language Server', { log: true });
  statusItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  context.subscriptions.push(outputChannel, statusItem);

  const start = async () => {
    await stopClient();
    const configuration = resolveFathomConfiguration(vscode.workspace.getConfiguration('fathom'));
    // D-02: no implicit dialect/profile fallback. A missing or unsupported
    // selection is an explicit configuration error and the client is never
    // started with a guessed dialect.
    if (!configuration.dialect || !configuration.profile) {
      const missing = [configuration.dialect ? null : 'fathom.dialect (doris|flink)', configuration.profile ? null : 'fathom.profile (2.1|3.x|4.x)']
        .filter(Boolean)
        .join(' and ');
      vscode.window.showErrorMessage(
        `Fathom SQL: no explicit dialect/profile selection. Set ${missing} before opening SQL documents; the language server was not started.`,
      );
      statusItem.text = 'Fathom: no dialect/profile configured';
      statusItem.tooltip = `Set ${missing} to start the language server`;
      statusItem.show();
      return;
    }
    const serverOptions = createServerOptions(configuration.serverPath);
    const clientOptions = {
      documentSelector: [{ scheme: 'file', language: 'sql' }],
      initializationOptions: { dialect: configuration.dialect, profile: configuration.profile },
      outputChannel,
      revealOutputChannelOn: 4,
    };
    client = new LanguageClient('fathom', 'Fathom SQL Language Server', serverOptions, clientOptions);
    const current = client;
    context.subscriptions.push(current);
    try {
      await current.start();
      statusItem.text = `Fathom ${configuration.dialect} ${configuration.profile}`;
      statusItem.tooltip = `Fathom ${configuration.dialect} ${configuration.profile}; local stdio server`;
      statusItem.show();
    } catch (error) {
      if (client === current) client = undefined;
      showServerFailure(error);
    }
  };

  const restart = vscode.commands.registerCommand('fathom.restartLanguageServer', start);
  context.subscriptions.push(restart);
  await start();
}

export async function deactivate() {
  await stopClient();
  statusItem = undefined;
}
