export const SERVER_FAILURE_MESSAGE = 'Doris language server unavailable. Check the local executable path and try again.';
export const SUPPORTED_PROFILES = Object.freeze(['2.1', '3.x', '4.x']);

export function normalizeProfile(value) {
  return SUPPORTED_PROFILES.includes(value) ? value : '4.x';
}

export function resolveDorisConfiguration(configuration) {
  return {
    profile: normalizeProfile(configuration.get('profile', '4.x')),
    serverPath: configuration.get('serverPath', 'doris-lsp') || 'doris-lsp',
  };
}
