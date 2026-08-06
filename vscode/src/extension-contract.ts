export const SERVER_FAILURE_MESSAGE = 'Fathom SQL language server unavailable. Check the local executable path and try again.';
export const SUPPORTED_DIALECTS = Object.freeze(['doris', 'flink']);
export const SUPPORTED_PROFILES = Object.freeze(['2.1', '3.x', '4.x']);

// D-02: no default dialect and no default profile — a missing or unsupported
// selection is an explicit configuration error, never a silent fallback.
// The legacy normalizeProfile('4.x') fallback is deleted, not adjusted.
export function resolveFathomConfiguration(configuration) {
  const dialect = configuration.get('dialect');
  const profile = configuration.get('profile');
  return {
    dialect: SUPPORTED_DIALECTS.includes(dialect) ? dialect : undefined,
    profile: SUPPORTED_PROFILES.includes(profile) ? profile : undefined,
    serverPath: configuration.get('serverPath', 'fathom-lsp') || 'fathom-lsp',
  };
}
