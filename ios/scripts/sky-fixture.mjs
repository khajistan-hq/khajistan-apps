#!/usr/bin/env node
// Writes Tests/Fixtures/sky-fixture.json: what the website's own sky (KJSky in
// archive/scripts/kj-theme-boot.js) answers for every zone it carries, its renames and three
// zones it does not, at sixteen instants. Sky in Khajistan/Core/Sky.swift is tested against these
// answers, so the expectations come from running the JS, never from reasoning about it.
//
//   node ios/scripts/sky-fixture.mjs
//
// The boot file lives in the archive repo, which this sparse worktree does not carry. Set
// KJ_THEME_BOOT_JS to point at another copy. The output is deterministic.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const bootPath = process.env.KJ_THEME_BOOT_JS || '/Users/home/CZURImages/filmart/archive/scripts/kj-theme-boot.js';
const outPath = resolve(here, '../Tests/Fixtures/sky-fixture.json');

// The sky's own lines, from the table to the line that publishes them, run as they are written.
const source = readFileSync(bootPath, 'utf8');
const from = source.indexOf("var TZ = '");
const to = source.indexOf('root.KJSky =');
if (from < 0 || to < from) throw new Error('KJSky not found in ' + bootPath);
const RealDate = Date;

function skyFor(zone) {
  const FakeIntl = { DateTimeFormat: () => ({ resolvedOptions: () => ({ timeZone: zone }) }) };
  // The fallback reads local hours: give it the zone's own, whatever the machine's zone is.
  class ZoneDate {
    constructor(ms) { this.ms = ms; }
    static now() { return RealDate.now(); }
    getHours() {
      return Number(new Intl.DateTimeFormat('en-US', { timeZone: zone, hour: 'numeric', hourCycle: 'h23' }).format(new RealDate(this.ms)));
    }
  }
  const make = new Function('Intl', 'Date', source.slice(from, to) + '\nreturn { skyTheme, position, elevation };');
  return make(FakeIntl, ZoneDate);
}

const TZ = source.slice(from).match(/var TZ = '([^']*)'/)[1];
const zones = [];
const aliases = [];
for (const area of TZ.split('~').filter(Boolean)) {
  const rows = area.split('|');
  if (rows[0].includes('>')) { for (const row of rows) aliases.push(row.split('>')[0]); continue; }
  for (const row of rows.slice(1)) zones.push(rows[0] + '/' + row.split(' ')[0]);
}
// Valid zones the table does not carry: the hour bands answer for them.
const unplaced = ['UTC', 'Etc/GMT-3', 'Etc/GMT+10'];

const instants = [];
for (const day of ['2026-03-20', '2026-10-05']) {
  for (let h = 0; h < 24; h += 3) instants.push(RealDate.parse(`${day}T${String(h).padStart(2, '0')}:00:00Z`));
}

const cases = [];
for (const zone of [...zones, ...aliases, ...unplaced]) {
  const sky = skyFor(zone);
  const place = sky.position();
  for (const ms of instants) {
    const c = { zone, ms, theme: sky.skyTheme(ms) };
    if (place) c.elevation = sky.elevation(ms, place[0], place[1]);
    cases.push(c);
  }
}
writeFileSync(outPath, JSON.stringify({ source: 'archive/scripts/kj-theme-boot.js', zones: zones.length, aliases: aliases.length, unplaced, cases }) + '\n');
console.log(`${cases.length} cases, ${zones.length} zones, ${aliases.length} renames, ${unplaced.length} unplaced -> ${outPath}`);
