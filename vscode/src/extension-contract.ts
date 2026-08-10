export const SERVER_FAILURE_MESSAGE = 'Fathom SQL language server unavailable. Check the local executable path and try again.';
export const SUPPORTED_DIALECTS = Object.freeze(['doris', 'flink']);
// D-05: per-dialect (dialect, profile) pairs — the flat SUPPORTED_PROFILES
// list is replaced by a per-dialect map (doris -> 2.1/3.x/4.x; flink ->
// flink-2.3.0/2.1.3/1.20.5). Static constants only: no dynamic pull, no
// shared cross-host JSON (offline-first, PARITY-03).
export const PROFILES_BY_DIALECT = Object.freeze({
  doris: ['2.1', '3.x', '4.x'],
  flink: ['flink-2.3.0', 'flink-2.1.3', 'flink-1.20.5'],
});

// D-02/D-05: no default dialect and no default profile — a missing,
// unsupported, or cross-dialect profile is an explicit configuration error
// (undefined, surfaced by the extension), never a coerced default. The legacy
// normalizeProfile('4.x') fallback is deleted, not adjusted.
export function resolveFathomConfiguration(configuration) {
  const dialect = configuration.get('dialect');
  const allowed = PROFILES_BY_DIALECT[dialect];
  const profile = allowed && allowed.includes(configuration.get('profile'))
    ? configuration.get('profile')
    : undefined;
  return {
    dialect: SUPPORTED_DIALECTS.includes(dialect) ? dialect : undefined,
    profile,
    serverPath: configuration.get('serverPath', 'fathom-lsp') || 'fathom-lsp',
  };
}
