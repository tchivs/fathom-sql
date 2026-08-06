import * as monaco from 'monaco-editor';
import {
  ARTIFACT_FAILURE,
  DIALECTS,
  PROFILES,
  ParserAdapter,
  byteToPosition,
  diagnosticRange,
  utf8Bytes,
} from './monaco-adapter.ts';

const SAMPLE = 'SELECT /*+ SET_VAR(query_timeout=1000) */\n  id, -- keep this comment\n  name\nFROM demo_table\nWHERE id > 10;';
const dialectSelect = document.querySelector('#dialect');
const profileSelect = document.querySelector('#profile');
const formatButton = document.querySelector('#format');
const editorHost = document.querySelector('#editor');
const diagnosticsHost = document.querySelector('#diagnostics');
const status = document.querySelector('#parser-status');
const profileMetadata = document.querySelector('#profile-metadata');
const resultMessage = document.querySelector('#result-message');
const reloadButton = document.querySelector('#reload');
const artifactError = document.querySelector('#artifact-error');

if (!dialectSelect || !profileSelect || !formatButton || !editorHost || !diagnosticsHost || !status || !profileMetadata || !resultMessage || !reloadButton || !artifactError) {
  throw new Error('Fathom demo markup is incomplete.');
}

// D-02: neither dialect nor profile is preselected — the demo surfaces the
// missing-selection error until the user chooses explicitly.
for (const dialect of DIALECTS) {
  const option = document.createElement('option');
  option.value = dialect;
  option.textContent = dialect;
  dialectSelect.append(option);
}
for (const profile of PROFILES) {
  const option = document.createElement('option');
  option.value = profile;
  option.textContent = profile;
  profileSelect.append(option);
}

monaco.languages.register({ id: 'sql' });
const model = monaco.editor.createModel(SAMPLE, 'sql');
const editor = monaco.editor.create(editorHost, {
  model,
  automaticLayout: true,
  accessibilitySupport: 'on',
  minimap: { enabled: false },
  fontSize: 14,
  lineNumbers: 'on',
  scrollBeyondLastLine: false,
  tabSize: 2,
});

const adapter = new ParserAdapter();
let ready = false;
let formatting = false;
let debounceTimer = 0;
let parseGeneration = 0;
let lastDiagnostics = [];

function announce(message, mode = 'polite') {
  status.textContent = '';
  status.setAttribute('aria-live', mode);
  // Force assistive technology to announce repeated state transitions.
  requestAnimationFrame(() => { status.textContent = message; });
}

function setReadyControls(enabled) {
  dialectSelect.disabled = !enabled;
  profileSelect.disabled = !enabled;
  formatButton.disabled = !enabled || formatting;
  editor.updateOptions({ readOnly: !enabled });
}

function severityLabel(severity) {
  if (severity === 'warning') return ['Warning', '▲', monaco.MarkerSeverity.Warning];
  if (severity === 'info') return ['Info', '●', monaco.MarkerSeverity.Info];
  return ['Error', '■', monaco.MarkerSeverity.Error];
}

function diagnosticText(diagnostic, sourceBytes) {
  const range = diagnosticRange(sourceBytes, diagnostic);
  return {
    range,
    start: `${range.start.line + 1}:${range.start.character + 1}`,
    end: `${range.end.line + 1}:${range.end.character + 1}`,
    bytes: `${diagnostic.start_byte ?? 0}–${diagnostic.end_byte ?? diagnostic.start_byte ?? 0}`,
  };
}

function renderDiagnostics(diagnostics, sourceBytes) {
  lastDiagnostics = diagnostics;
  monaco.editor.setModelMarkers(model, 'sql', diagnostics.map((diagnostic) => {
    const [label, glyph, severity] = severityLabel(diagnostic.severity);
    const range = diagnosticText(diagnostic, sourceBytes).range;
    return {
      severity,
      message: `${label}: ${diagnostic.message}`,
      code: diagnostic.code,
      startLineNumber: range.start.line + 1,
      startColumn: range.start.character + 1,
      endLineNumber: range.end.line + 1,
      endColumn: Math.max(range.end.character + 1, range.start.character + 2),
      tags: glyph === '▲' ? [monaco.MarkerTag.Unnecessary] : undefined,
    };
  }));

  diagnosticsHost.replaceChildren();
  const heading = document.createElement('h2');
  heading.id = 'diagnostics-heading';
  heading.textContent = diagnostics.length === 0 ? 'No diagnostics' : `${diagnostics.length} ${diagnostics.length === 1 ? 'diagnostic' : 'diagnostics'}`;
  diagnosticsHost.append(heading);
  if (diagnostics.length === 0) {
    const empty = document.createElement('p');
    empty.textContent = 'Type or paste SQL to see diagnostics here.';
    diagnosticsHost.append(empty);
    return;
  }
  const list = document.createElement('ol');
  list.className = 'diagnostic-list';
  for (const [index, diagnostic] of diagnostics.entries()) {
    const [label, glyph] = severityLabel(diagnostic.severity);
    const text = diagnosticText(diagnostic, sourceBytes);
    const row = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'diagnostic-row';
    button.dataset.index = String(index);
    button.setAttribute('aria-label', `${label} ${diagnostic.code}: ${diagnostic.message}; lines ${text.start} to ${text.end}`);
    const codeNode = document.createElement('code');
    // MI-08: build the code node via textContent (never innerHTML) — the
    // diagnostic code must stay inert even if it ever carries a
    // dialect/source-derived string.
    codeNode.textContent = diagnostic.code;
    button.innerHTML = `<span class="severity" aria-hidden="true">${glyph}</span><span class="severity-label">${label}</span><span class="diagnostic-message"></span><span class="diagnostic-range">${text.start}–${text.end}</span><span class="diagnostic-bytes">UTF-8 bytes ${text.bytes}</span>`;
    button.querySelector('.diagnostic-message').textContent = diagnostic.message;
    // Insert before the message span so the DOM order matches the previous
    // markup (severity, label, code, message, range, bytes).
    button.insertBefore(codeNode, button.querySelector('.diagnostic-message'));
    button.addEventListener('click', () => selectDiagnostic(index, text.range));
    button.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        selectDiagnostic(index, text.range);
      }
    });
    row.append(button);
    list.append(row);
  }
  diagnosticsHost.append(list);
}

function selectDiagnostic(index, range) {
  const selection = {
    startLineNumber: range.start.line + 1,
    startColumn: range.start.character + 1,
    endLineNumber: range.end.line + 1,
    endColumn: Math.max(range.end.character + 1, range.start.character + 2),
  };
  editor.setSelection(selection);
  editor.revealRangeInCenter(selection);
  editor.focus();
  diagnosticsHost.querySelector(`[data-index="${index}"]`)?.classList.add('selected');
}

async function parseNow() {
  if (!ready) return;
  const generation = ++parseGeneration;
  const source = model.getValue();
  const sourceBytes = utf8Bytes(source);
  try {
    const result = await adapter.parse(source, dialectSelect.value, profileSelect.value);
    if (generation !== parseGeneration) return;
    profileMetadata.textContent = `dialect ${result.dialect ?? dialectSelect.value}; profile ${result.profile ?? profileSelect.value}`;
    renderDiagnostics(result.diagnostics ?? [], sourceBytes);
    if (result.recovered) {
      announce('Parser ready; incomplete SQL is recoverable.');
    } else {
      announce('Parser ready');
    }
  } catch (error) {
    if (generation !== parseGeneration) return;
    announce(error.message || 'Parser unavailable', 'assertive');
    resultMessage.textContent = error.message || 'Parser unavailable';
  }
}

function scheduleParse() {
  window.clearTimeout(debounceTimer);
  debounceTimer = window.setTimeout(parseNow, 150);
}

async function formatDocument() {
  if (!ready || formatting) return;
  formatting = true;
  formatButton.disabled = true;
  resultMessage.textContent = '';
  announce('Formatting…');
  const source = model.getValue();
  const originalBytes = utf8Bytes(source);
  try {
    const result = await adapter.format(source, dialectSelect.value, profileSelect.value);
    if (result.accepted) {
      const output = result.output;
      if (output !== source) {
        editor.executeEdits('fathom-format', [{
          range: model.getFullModelRange(),
          text: output,
        }]);
      }
      resultMessage.textContent = 'Formatted; comments and hints preserved.';
      announce('Formatted; comments and hints preserved.');
      renderDiagnostics([], utf8Bytes(output));
    } else {
      // Refusal is absolute: do not call executeEdits and retain exact source bytes.
      resultMessage.textContent = 'Formatting unavailable: resolve the reported syntax errors first.';
      announce('Formatting unavailable: resolve the reported syntax errors first.');
      renderDiagnostics(result.diagnostics ?? lastDiagnostics, originalBytes);
    }
  } catch (error) {
    resultMessage.textContent = error.message || 'Formatting unavailable: resolve the reported syntax errors first.';
    announce(resultMessage.textContent, 'assertive');
  } finally {
    formatting = false;
    formatButton.disabled = false;
  }
}

async function load() {
  setReadyControls(false);
  artifactError.hidden = true;
  announce('Loading parser artifact…');
  try {
    await adapter.load();
    ready = true;
    setReadyControls(true);
    profileMetadata.textContent = 'No dialect or profile selected';
    announce('Parser ready');
    scheduleParse();
  } catch {
    ready = false;
    setReadyControls(false);
    artifactError.hidden = false;
    artifactError.querySelector('.artifact-message').textContent = ARTIFACT_FAILURE;
    announce(ARTIFACT_FAILURE, 'assertive');
  }
}

function selectionChanged() {
  profileMetadata.textContent = `dialect ${dialectSelect.value}; profile ${profileSelect.value}`;
  scheduleParse();
}

dialectSelect.addEventListener('change', selectionChanged);
profileSelect.addEventListener('change', selectionChanged);
formatButton.addEventListener('click', formatDocument);
model.onDidChangeContent(scheduleParse);
reloadButton.addEventListener('click', () => window.location.reload());
window.addEventListener('beforeunload', () => {
  editor.dispose();
  model.dispose();
});

load();

export { adapter, byteToPosition, diagnosticRange, parseNow, renderDiagnostics };
