#!/usr/bin/env node
// Runs the WEBSITE'S own grouping code over a catalogue feed and writes what it produces, so the
// Swift port (KhajistanTV/Core/ReadingRoom.swift, RRCatalogue.titles) is checked against the site's
// code and not against itself.
//
//   node scripts/rr-grouping-fixture.mjs <archive-dir> <out-dir>
//
// Reads  <archive-dir>/data/reading-room-catalogue.json  (the baked reading_room_catalogue() feed)
//        <archive-dir>/scripts/reading-room-app.js        (the functions below are cut out of it)
// Writes <out-dir>/rr-full-expected.json   every card the site builds from the whole feed
//        <out-dir>/rr-sample-catalogue.json   a closed subset of the feed (whole groups, whole families)
//        <out-dir>/rr-sample-expected.json    the site's cards for that subset
// The sample is what is checked in under Tests/Fixtures; the full pair is for a one-off parity run
// (KJ_RR_FEED and KJ_RR_EXPECTED, read by the core test of the same name).
//
// What is cut out and run, unchanged: rrSplitTitle .. rrFamilyLabel, and boot()'s absorb, bucket and
// dbMags passes. What is stubbed: the 24 hand-typed seeds (no seed, so no seeded names or issue
// labels) and RR_FEED_OPEN, which the app replaces by asking the page server.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const [archive, outDir] = process.argv.slice(2);
if (!archive || !outDir) {
  console.error('usage: rr-grouping-fixture.mjs <archive-dir> <out-dir>');
  process.exit(2);
}
const source = fs.readFileSync(path.join(archive, 'scripts/reading-room-app.js'), 'utf8');
const bake = JSON.parse(fs.readFileSync(path.join(archive, 'data/reading-room-catalogue.json'), 'utf8'));

function between(from, to) {
  const a = source.indexOf(from);
  const b = source.indexOf(to, a + from.length);
  if (a < 0 || b < 0) throw new Error(`markers not found: ${from.slice(0, 40)} .. ${to.slice(0, 40)}`);
  return source.slice(a, b);
}

const helpers = between('function rrSplitTitle(t){', '// Every collection_slug the DB feed accounted for');
// The RR_EDITION_LANGUAGES set sits between rrTitleKey and rrIsEditionLanguage, inside the slice above.
const grouping = between('const issuesOf = (c, labelOverride, labelKey) =>', '// A DB-BACKED sampler title absent from a SUCCESSFUL feed');

const code = `
${helpers}
const samplerBySlug = new Map();
const RR_FEED_OPEN = new Set();
const applySeedIssueLabels = (issues) => issues;
function group(cols) {
  ${grouping}
  return dbMags;
}
`;
const context = {};
vm.createContext(context);
vm.runInContext(code, context);

function cards(rows) {
  const copy = JSON.parse(JSON.stringify(rows));
  return context.group(copy).map((m) => ({
    slug: m.slug,
    name: m.name,
    native: m.native,
    region: m.region,
    members: m._memberSlugs,
    issues: m.issues.map((i) => ({ slug: i.slug, id: i.id, label: i.label, pages: i.pages })),
  }));
}

fs.mkdirSync(outDir, { recursive: true });
const full = cards(bake.rows);
fs.writeFileSync(path.join(outDir, 'rr-full-expected.json'), JSON.stringify(full));

// A closed sample: for each interesting card, all its member collections and every collection a
// parent absorbs, so the site's code sees the same groups it saw in the full feed. Big families are
// cut to their first rows; a family is grouped per member, so a cut family groups the same way.
const bySlug = new Map(bake.rows.map((r) => [r.collection_slug, r]));
const picked = new Set();
const takeCard = (card, cap) => {
  card.members.slice(0, cap).forEach((s) => picked.add(s));
};
const interesting = (card) =>
  /^(28-cinema|gol-agha|molla-nasraddin|49-film-and-art|nigar|keyhan-bacheha|dawat|oak-chitrali|shama|oak-shama|naujawano|urdu-afsane|al-saaat|arwah-al-jafr|asrar-ilm|archie|al-wafd)/.test(card.slug) ||
  card.members.length > 1;
full.filter(interesting).forEach((c) => takeCard(c, 8));
// Parents that absorb children: keep the children (and their parent's whole row).
for (const row of bake.rows) {
  const s = row.collection_slug;
  for (let i = s.indexOf('-'); i > 0; i = s.indexOf('-', i + 1)) {
    const p = bySlug.get(s.slice(0, i));
    if (p && (p.issues || []).some((x) => (x.id || '') === s.slice(i + 1))) {
      if (picked.has(p.collection_slug) || /keyhan|bachon-ka-shakespeare/.test(p.collection_slug)) {
        picked.add(s);
        picked.add(p.collection_slug);
      }
      break;
    }
  }
}
// Plain single-collection titles, every 25th, and one per region token.
bake.rows.filter((_, i) => i % 25 === 0).forEach((r) => picked.add(r.collection_slug));
const seenRegion = new Set();
for (const r of bake.rows) {
  if (!seenRegion.has(r.collection_region)) {
    seenRegion.add(r.collection_region);
    picked.add(r.collection_slug);
  }
}
// The titles the app hard-codes by slug: four-digit pages, other-folder pages, declared covers.
const named = ['naujawano-mein-jinsi-khauf-aur-iska-tadaruk-karwan-e-adab-pu', 'urdu-afsane-mein-jins-ki-riwayat-poorab-academy',
  'oak-chitrali', 'oak-shama', 'oak-shama-delhi', 'shama-delhi', 'shama-periodical', 'tilism-e-hoshruba', 'ziya-al-absar', 'peykar', 'moslemin'];
named.forEach((s) => bySlug.has(s) && picked.add(s));

// Rows with hundreds of issues only make the fixture heavy; none of the cases above needs one.
const sample = bake.rows.filter((r) => picked.has(r.collection_slug) && (r.issues || []).length <= 120);
fs.writeFileSync(path.join(outDir, 'rr-sample-catalogue.json'), JSON.stringify(sample));
fs.writeFileSync(path.join(outDir, 'rr-sample-expected.json'), JSON.stringify(cards(sample)));
console.log(`full: ${bake.rows.length} collections -> ${full.length} cards; sample: ${sample.length} collections -> ${cards(sample).length} cards`);
