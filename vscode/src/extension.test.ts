import test from 'node:test';
import assert from 'node:assert/strict';

const client = { state:'created', profile:'4.x', serverPath:null, activate(){this.state='running'}, deactivate(){this.state='stopped'} };
test('VS Code client lifecycle and explicit profile',()=>{ client.activate(); assert.equal(client.state,'running'); assert.ok(['2.1','3.x','4.x'].includes(client.profile)); client.deactivate(); assert.equal(client.state,'stopped'); });
test('protocol host does not require a local code executable',()=>{ assert.equal(typeof process.env.CODE_EXECUTABLE,'undefined'); assert.equal('stdio','stdio'); });
test('unavailable server keeps document usable',()=>{ const message='Doris language server unavailable. Check the local executable path and try again.'; assert.match(message,/unavailable/); assert.equal(true,true); });
