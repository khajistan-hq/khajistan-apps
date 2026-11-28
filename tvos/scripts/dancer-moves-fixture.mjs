#!/usr/bin/env node
// Writes Tests/Fixtures/dancer-moves.json: the website dancer's move list and the moves that hold
// for two runs, read out of the site's own archive/scripts/kj-scope.js. CoreTests compares
// DancerMoves to this file on every run, CI included, so the Swift list cannot drift from the
// site's without a red test. Regenerate it whenever the site's moves change:
//
//   KJ_ARCHIVE=<site checkout> node tvos/scripts/dancer-moves-fixture.mjs
//
// MOVES comes from running the file (window.KJScope.MOVES). HOLD is not exported, so it is read
// from its object literal; the script refuses if either is empty.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
if (!process.env.KJ_ARCHIVE) throw new Error('set KJ_ARCHIVE to a checkout of the site');
const src = readFileSync(resolve(process.env.KJ_ARCHIVE, 'scripts/kj-scope.js'), 'utf8');
const window = {};
new Function('window', src)(window);
const moves = window.KJScope && window.KJScope.MOVES;
const holdBody = (src.match(/var HOLD = \{([^}]*)\}/) || [])[1] || '';
const hold = [...holdBody.matchAll(/"([^"]+)"\s*:/g)].map(m => m[1]);
if (!moves || !moves.length || !hold.length) throw new Error('MOVES or HOLD not found in kj-scope.js');
const out = resolve(here, '../Tests/Fixtures/dancer-moves.json');
writeFileSync(out, JSON.stringify({ source: 'archive/scripts/kj-scope.js', moves, hold }, null, 2) + '\n');
console.log(`wrote ${out}: ${moves.length} moves, ${hold.length} held`);
