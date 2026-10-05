#!/usr/bin/env node
// Writes Tests/Fixtures/pnv-media-fixture.json: rows from the live pnv_media view (the sample in
// Tests/Fixtures/pnv-rows-sample.json) plus hand-made edge cases, each with what the site's own
// KJMedia (scripts/kj-media.js) answers for thumb, mediumThumb, poster and full, and for the page's
// tile and viewer choices. PnvMedia in KhajistanTV/Core/PicsVids.swift is tested against these, so
// the expectations come from running the JS, never from reasoning about it.
//
//   node tvos/scripts/pnv-media-fixture.mjs
//
// kj-media.js lives in the site tree, which is this checkout's root. Set KJ_MEDIA_JS for another
// copy. The output is deterministic.

import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const mediaPath = process.env.KJ_MEDIA_JS || resolve(here, '../../scripts/kj-media.js');
const samplePath = resolve(here, '../Tests/Fixtures/pnv-rows-sample.json');
const outPath = resolve(here, '../Tests/Fixtures/pnv-media-fixture.json');

global.window = global;
createRequire(import.meta.url)(mediaPath);
const M = global.KJMedia;
if (!M || typeof M.full !== 'function') throw new Error('KJMedia not found after loading ' + mediaPath);

const row = (o) => ({ media_key: 'x', account: 'a', account_key: 'a', kind: 'image', resource_type: 'image', media_host: 'supabase', resource_endpoint: '1', width: null, height: null, ...o });
const edge = [
  row({ media_key: 'edge-spaces', media_host: 'r2', resource_endpoint: 'some account/media/a b/a b' }),
  row({ media_key: 'edge-unicode', media_host: 'r2', kind: 'video', resource_type: 'video', resource_endpoint: 'عروسی/media/x/x' }),
  row({ media_key: 'edge-plus-slash', media_host: 'ktv', kind: 'video', resource_type: 'video', resource_endpoint: 'tv a+b/c?d&e=f#g' }),
  row({ media_key: 'edge-ktv-image', media_host: 'ktv', resource_endpoint: 'tv-x-mp4' }),
  row({ media_key: 'edge-parens', media_host: 'supabase', kind: 'video', resource_type: 'video', resource_endpoint: "it's (1)!~*" }),
  row({ media_key: 'edge-empty', media_host: 'r2', resource_endpoint: '' }),
  row({ media_key: 'edge-null', media_host: 'supabase', resource_endpoint: null }),
  row({ media_key: 'edge-nohost', media_host: null, resource_endpoint: '77' }),
];
const rows = [...JSON.parse(readFileSync(samplePath, 'utf8')), ...edge];

const none = (v) => (v === '' || v == null ? null : v);
const cases = rows.map((r) => ({
  row: r,
  thumb: none(M.thumb(r)),
  medium: none(M.mediumThumb(r)),
  poster: none(M.poster(r)),
  full: none(M.full(r)),
  // kj-browse-archive.js tile(): a video's poster or thumb, a picture's medium or thumb.
  tile: none(r.kind === 'video' ? (M.poster(r) || M.thumb(r)) : (M.mediumThumb(r) || M.thumb(r))),
  // srcCandidates of a picture in the viewer: [full, medium, thumb], blanks dropped.
  candidates: [M.full(r), M.mediumThumb(r), M.thumb(r)].filter(Boolean),
}));
writeFileSync(outPath, JSON.stringify({ source: 'scripts/kj-media.js', cases }, null, 1) + '\n');
console.log(`${cases.length} cases -> ${outPath}`);
