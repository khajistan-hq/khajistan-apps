#!/usr/bin/env node
// Writes Tests/Fixtures/station-clock-fixture.json: a trimmed copy of the October schedule and
// what the site's own clock (archive/scripts/kj-station-clock.js) answers for a set of instants.
// The Swift port in KhajistanTV/Core/StationClock.swift is tested against these answers, so the
// expectations come from running the JS, never from reasoning about it.
//
//   node tvos/scripts/station-clock-fixture.mjs
//
// The clock file lives in the archive repo, which a worktree does not carry. Set
// KJ_STATION_CLOCK_JS to point at another copy. The output is deterministic.

import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const programmingPath = resolve(here, '../../data/khajistan-tv/programming-2026-10.json');
const clockPath = process.env.KJ_STATION_CLOCK_JS || '/Users/home/CZURImages/filmart/archive/scripts/kj-station-clock.js';
const outPath = resolve(here, '../Tests/Fixtures/station-clock-fixture.json');

// The clock file is a browser script: (function (global) { … })(window), assigning global.KJStation.
global.window = global;
createRequire(import.meta.url)(clockPath);
const K = global.KJStation;
if (!K || typeof K.onAir !== 'function') throw new Error('KJStation not found after loading ' + clockPath);

// --- the trimmed programming -------------------------------------------------------------
const full = JSON.parse(readFileSync(programmingPath, 'utf8'));
const FIRST_DAY = '2026-10-10';
const LAST_DAY = '2026-10-13';
const days = full.days.filter((d) => d.date >= FIRST_DAY && d.date <= LAST_DAY);
if (days.length !== 4) throw new Error('expected 4 kept days, got ' + days.length);

// Slots index programme_order by position, so the whole order is kept; only the programme
// records that a kept slot can reach are carried.
const referenced = new Set();
for (const day of days)
  for (const strips of Object.values(day.channels))
    for (const slot of strips)
      for (const index of slot.programmes) referenced.add(full.programme_order[index]);
const programmes = {};
for (const id of Object.keys(full.programmes)) if (referenced.has(id)) programmes[id] = full.programmes[id];
if (Object.keys(programmes).length !== referenced.size) throw new Error('a referenced programme is missing from programmes');

const programming = {
  _meta: full._meta,
  shows: full.shows,
  programme_order: full.programme_order,
  programmes,
  days,
};

// --- the instants -------------------------------------------------------------------------
const PKT_MS = 5 * 3600 * 1000;
const pkt = (day, h, m, s, month = 10) => Date.UTC(2026, month - 1, day, h, m, s) - PKT_MS;

const instants = [];
const stepMs = (17 * 60 + 13) * 1000;
for (let t = pkt(10, 5, 30, 0); t <= pkt(12, 23, 59, 0); t += stepMs) instants.push(t);
for (const [d, h, m, s] of [[10, 5, 59, 59], [10, 6, 0, 0], [10, 6, 0, 1], [10, 23, 59, 59], [11, 0, 0, 0], [11, 0, 0, 1]]) {
  instants.push(pkt(d, h, m, s));
}
// Past the end of the trimmed grid: the trimmed programming has no such day.
for (const [h, m, s] of [[6, 0, 0], [12, 0, 0], [18, 30, 30]]) instants.push(pkt(20, h, m, s));

// --- the expectations, straight from the JS -------------------------------------------------
function expectAt(prog, nowMs, channel) {
  const realNow = Date.now;
  Date.now = () => nowMs;
  try {
    const air = K.onAir(prog, channel);
    if (!air) return null;
    const position = K.positionInSlot(prog, air.slot, K.nowSeconds());
    return {
      channelId: air.channel,
      date: air.date,
      programmeId: air.programmeId,
      rosterIndex: position.index,
      into: air.into,
      seekTo: air.seekTo,
      startLabel: air.startLabel,
      endLabel: air.endLabel,
      nextStart: air.nextStart,
      slotStart: air.slot.start,
      slotStartMinute: air.slot.start_minute,
    };
  } finally {
    Date.now = realNow;
  }
}

const cases = [];
for (const nowMs of instants) {
  for (const channel of [1, 2]) cases.push({ nowMs, channel, expect: expectAt(programming, nowMs, channel) });
}

// --- self-checks, so a bad fixture fails here and not as a mystery in Swift -----------------
let onAir = 0, offAir = 0, trimmed = 0;
for (const c of cases) {
  if (!c.expect) { offAir++; continue; }
  onAir++;
  if (c.expect.seekTo !== c.expect.into) trimmed++;
  if (!programming.programmes[c.expect.programmeId]) throw new Error('on-air programme not carried: ' + c.expect.programmeId);
  // The trim must not change an answer inside the kept days.
  if (c.expect.date <= LAST_DAY) {
    const again = expectAt(full, c.nowMs, c.channel);
    if (JSON.stringify(again) !== JSON.stringify(c.expect)) throw new Error('trim changed the answer at ' + c.nowMs);
  }
}
const lateNull = cases.filter((c) => c.nowMs >= pkt(20, 0, 0, 0)).every((c) => c.expect === null);
if (!lateNull) throw new Error('an instant on 2026-10-20 was expected to be off air');

// --- write ----------------------------------------------------------------------------------
const J = JSON.stringify;
const text =
  '{"source":' + J('programming-2026-10.json') + ',"generatedFrom":' + J('kj-station-clock.js') + ',\n' +
  '"programming":' + J(programming) + ',\n' +
  '"cases":[\n' + cases.map((c) => J(c)).join(',\n') + '\n]}\n';
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, text);

console.log(`cases: ${cases.length} (${onAir} on air, ${offAir} off air, ${trimmed} with a clean_start offset)`);
console.log(`programmes carried: ${Object.keys(programmes).length} of ${Object.keys(full.programmes).length}; days: ${days.map((d) => d.date).join(', ')}`);
console.log(`wrote ${outPath} (${statSync(outPath).size} bytes)`);
