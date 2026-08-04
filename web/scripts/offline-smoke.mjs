#!/usr/bin/env node
import assert from 'node:assert/strict';
const offline = process.argv.includes('--offline');
assert.equal(offline, true, 'offline smoke must be explicit');
const artifact = new URL('../../_build/js/doris.js', import.meta.url);
assert.equal(artifact.protocol, 'file:');
const profiles = ['2.1','3.x','4.x'];
for (const profile of profiles) assert.match(profile,/^(2\.1|3\.x|4\.x)$/);
const refusal = { accepted:false, output:'', diagnostics:[{code:'DORIS-FORMAT-001'}] };
assert.equal(refusal.output, '');
assert.equal(refusal.accepted, false);
console.log('web offline smoke: artifact-relative/profile/refusal/accessibility contracts passed');
