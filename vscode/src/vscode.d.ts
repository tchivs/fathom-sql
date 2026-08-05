// The VS Code extension host provides the `vscode` module at runtime; it is
// not an npm package. @types/vscode is intentionally NOT a devDependency here
// (it is not available in the offline cache), so `tsc -p .` compiles against
// this ambient declaration. The host contract itself is exercised by
// `node --test vscode/src/extension.test.ts` on the TS sources and by the
// protocol launch smoke.
declare module 'vscode';
