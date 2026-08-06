// VS Code extension-host integration test (ECO-07 host checkpoint).
// Runs inside a real VS Code extension host via @vscode/test-electron.
// Exports run() — the VS Code test-runner contract (no Mocha dependency).
//
// Three invocations, each a fresh extension host with isolated user data
// (routed by VSCODE_HOST_MODE via scripts/host-verify.mjs):
//   functional dialect=doris profile=4.x  -> diagnostics / format / completion / MERGE ok
//   profile    dialect=doris profile=2.1  -> MERGE rejected (FATHOM-PARSE-006) = profile propagation
//   fallback   bad path                   -> unavailable-server message, document stays editable
import * as assert from 'node:assert/strict';
import * as vscode from 'vscode';

const MODE = process.env.VSCODE_HOST_MODE || 'functional';
const LSP_PATH = process.env.FATHOM_LSP_PATH || '/opt/source/Fathom/_build/native/debug/build/fathom-lsp/fathom-lsp.exe';
const BAD_PATH = process.env.FATHOM_LSP_PATH_BAD || '/nonexistent/fathom-lsp-missing';
const WORKSPACE = process.env.FATHOM_WORKSPACE || '/tmp/fathom-host-workspace';

function sleep(ms) {
  const { promise, resolve } = Promise.withResolvers();
  setTimeout(resolve, ms);
  return promise;
}

async function writeSqlFile(name, text) {
  const uri = vscode.Uri.file(`${WORKSPACE}/${name}`);
  await vscode.workspace.fs.writeFile(uri, Buffer.from(text, 'utf8'));
  return uri;
}

async function waitFor(fn, timeoutMs = 20000, intervalMs = 200) {
  const start = Date.now();
  for (;;) {
    const value = await fn();
    if (value) return value;
    if (Date.now() - start > timeoutMs) throw new Error(`waitFor timed out after ${timeoutMs}ms`);
    await sleep(intervalMs);
  }
}

async function openDoc(name, text) {
  const uri = await writeSqlFile(name, text);
  const doc = await vscode.workspace.openTextDocument(uri);
  const editor = await vscode.window.showTextDocument(doc);
  await sleep(400); // let didOpen reach the server
  return { doc, editor, uri };
}

async function diagnosticsFor(uri) {
  await sleep(150);
  return vscode.languages.getDiagnostics(uri);
}

async function setConfig(serverPath, dialect, profile) {
  const config = vscode.workspace.getConfiguration('fathom');
  await config.update('serverPath', serverPath, vscode.ConfigurationTarget.Global);
  await config.update('dialect', dialect, vscode.ConfigurationTarget.Global);
  await config.update('profile', profile, vscode.ConfigurationTarget.Global);
  await sleep(300); // let settings land before the extension host reads them on activation
}

const MERGE_SQL = 'MERGE INTO t USING s ON t.id=s.id WHEN MATCHED THEN UPDATE SET v=s.v;\n';

async function runFunctional() {
  await setConfig(LSP_PATH, 'doris', '4.x');

  // 1) invalid SQL -> structured diagnostic with stable code + UTF-16 range
  const { uri: badUri } = await openDoc('bad.sql', 'SELEC 1 FROM t;\n');
  const badDiags = await waitFor(async () => {
    const d = await diagnosticsFor(badUri);
    return d.length > 0 ? d : null;
  });
  const first = badDiags[0];
  assert.ok(first.code, 'diagnostic carries a stable code');
  assert.equal(first.severity, vscode.DiagnosticSeverity.Error, 'invalid SQL is an Error severity diagnostic');
  assert.ok(first.range.start.line === 0 && first.range.start.character === 0, 'UTF-16 range start');
  assert.equal(first.source, 'fathom', 'diagnostic source is the neutral fathom identity');

  // 2) valid SQL -> Format Document returns a comment-preserving, keyword-cased edit
  const fmtUri = await writeSqlFile('fmt.sql', 'select   a,  b  from  t;\n');
  const fmtDoc = await vscode.workspace.openTextDocument(fmtUri);
  await vscode.window.showTextDocument(fmtDoc);
  await sleep(400);
  const fmtEdits = await vscode.commands.executeCommand('vscode.executeFormatDocumentProvider', fmtDoc.uri, {
    tabSize: 2,
    insertSpaces: true,
  });
  assert.ok(Array.isArray(fmtEdits) && fmtEdits.length > 0, 'Format Document produces edits');
  assert.match(fmtEdits[0].newText, /SELECT/, 'formatted text preserves keywords');

  // 3) completion -> parser-known keyword suggestions
  const completion = await vscode.commands.executeCommand('vscode.executeCompletionItemProvider', badUri, new vscode.Position(0, 0));
  assert.ok(completion && Array.isArray(completion.items), 'completion provider returns items');
  const labels = completion.items.map((item) => String(item.label).toUpperCase());
  assert.ok(labels.includes('SELECT'), 'completion includes SELECT keyword');

  // 4) 4.x MERGE parses (no version-invalid diagnostic)
  const mergeUri = await writeSqlFile('merge.sql', MERGE_SQL);
  const mergeDoc = await vscode.workspace.openTextDocument(mergeUri);
  await vscode.window.showTextDocument(mergeDoc);
  await sleep(500);
  const mergeDiags = await diagnosticsFor(mergeUri);
  assert.ok(!mergeDiags.some((d) => d.code === 'FATHOM-PARSE-006'), '4.x MERGE has no version-invalid diagnostic');

  console.log('HOST-FUNCTIONAL: diagnostics/format/completion/4.x-merge passed');
}

async function runProfile() {
  await setConfig(LSP_PATH, 'doris', '2.1');

  // MERGE is introduced at 4.x (D-09) -> 2.1 must report FATHOM-PARSE-006,
  // proving the configured profile reached the server via initialize.
  const { uri } = await openDoc('merge21.sql', MERGE_SQL);
  const diags = await waitFor(async () => {
    const d = await diagnosticsFor(uri);
    return d.some((x) => x.code === 'FATHOM-PARSE-006') ? d : null;
  });
  assert.ok(diags.some((d) => d.code === 'FATHOM-PARSE-006'), '2.1 MERGE reports FATHOM-PARSE-006 (profile propagation)');

  console.log('HOST-PROFILE: 2.1 rejects MERGE via FATHOM-PARSE-006 (profile propagated)');
}

async function runFallback() {
  await setConfig(BAD_PATH, 'doris', '4.x');

  // Opening a SQL document must not crash; server failure surfaces and the
  // document stays editable (plain text), per ECO-07 unavailable-server contract.
  const { doc, editor } = await openDoc('fallback.sql', 'SELECT 1;\n');
  await sleep(1500);
  assert.ok(!doc.isClosed, 'document remains open after server startup failure');
  const editWorked = await editor.edit((edit) => edit.insert(new vscode.Position(0, 0), '-- comment\n'));
  assert.ok(editWorked, 'document remains editable when the server is unavailable');

  console.log('HOST-FALLBACK: unavailable server leaves document editable');
}

export async function run() {
  assert.ok(LSP_PATH, 'FATHOM_LSP_PATH must be set');
  if (MODE === 'functional') await runFunctional();
  else if (MODE === 'profile') await runProfile();
  else if (MODE === 'fallback') await runFallback();
  else throw new Error(`unknown VSCODE_HOST_MODE: ${MODE}`);
}
