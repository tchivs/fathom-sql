import * as vscode from 'vscode';
import { LanguageClient, TransportKind } from 'vscode-languageclient/node';
import {
  SERVER_FAILURE_MESSAGE,
  SUPPORTED_PROFILES,
  normalizeProfile,
  resolveDorisConfiguration,
} from './extension-contract.ts';

export { SERVER_FAILURE_MESSAGE, SUPPORTED_PROFILES, normalizeProfile, resolveDorisConfiguration } from './extension-contract.ts';

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
    statusItem.text = 'Doris: unavailable';
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
  const configuration = resolveDorisConfiguration(vscode.workspace.getConfiguration('doris'));
  const outputChannel = vscode.window.createOutputChannel('Doris SQL Language Server');
  statusItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  statusItem.text = `Doris ${configuration.profile}`;
  statusItem.tooltip = `Doris profile ${configuration.profile}; local stdio server`;
  statusItem.show();
  context.subscriptions.push(outputChannel, statusItem);

  const start = async () => {
    await stopClient();
    const serverOptions = createServerOptions(configuration.serverPath);
    const clientOptions = {
      documentSelector: [{ scheme: 'file', language: 'doris' }],
      initializationOptions: { profile: configuration.profile },
      outputChannel,
      revealOutputChannelOn: 4,
    };
    client = new LanguageClient('doris', 'Doris SQL Language Server', serverOptions, clientOptions);
    const current = client;
    context.subscriptions.push(current);
    try {
      await current.start();
      statusItem.text = `Doris ${configuration.profile}`;
    } catch (error) {
      if (client === current) client = undefined;
      showServerFailure(error);
    }
  };

  const restart = vscode.commands.registerCommand('doris.restartLanguageServer', start);
  context.subscriptions.push(restart);
  await start();
}

export async function deactivate() {
  await stopClient();
  statusItem = undefined;
}
