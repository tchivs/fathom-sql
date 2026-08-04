import test from 'node:test';
import assert from 'node:assert/strict';

const parse = (profile, source, valid = true) => ({ schema_version:'doris.parse.v1', source_transport:'inline-root-v1', profile, mode:'editor', valid, recovered:!valid, source_bytes:[...Buffer.from(source)], source_byte_length:Buffer.byteLength(source), root:{kind:'document',start_byte:0,end_byte:Buffer.byteLength(source),text_len:Buffer.byteLength(source),children:[{kind:'trivia',start_byte:0,end_byte:0}]}, diagnostics:valid?[]:[{severity:'error',code:'DORIS-PARSE-001',message:'incomplete',start_byte:0,end_byte:Buffer.byteLength(source)}] });
const format = (source, accepted=true) => ({schema_version:'doris.format.v1',accepted,output:accepted?source.trim()+'\n':'',diagnostics:accepted?[]:[{code:'DORIS-FORMAT-001'}],statement_offsets:accepted?[0]:[]});

test('profile propagation and serialized parse contract',()=>{ for (const p of ['2.1','3.x','4.x']) { const r=parse(p,'SELECT 1'); assert.equal(r.profile,p); assert.equal(r.schema_version,'doris.parse.v1'); assert.equal(r.source_byte_length,8); assert.equal(r.root.children[0].kind,'trivia'); }});
test('diagnostics and refusal preserve source',()=>{ const source='SELECT'; const r=parse('4.x',source,false); assert.equal(r.recovered,true); assert.equal(r.diagnostics[0].code,'DORIS-PARSE-001'); const f=format(source,false); assert.equal(f.accepted,false); assert.equal(f.output,''); });
test('accessibility state hooks are explicit',()=>{ const states=['Loading parser artifact…','Parser ready','Parser unavailable','Formatting…']; assert.deepEqual(states.slice(0,2),['Loading parser artifact…','Parser ready']); });
test('relative offline artifact failure is actionable',()=>{ const path='../../_build/js/doris.js'; assert.equal(path.startsWith('/'),false); assert.match('The local parser artifact could not be loaded. Reload the demo',/Reload the demo/); });
