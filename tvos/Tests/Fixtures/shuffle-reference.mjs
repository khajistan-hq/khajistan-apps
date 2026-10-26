// The shuffle both apps and the website deal from.
//   node tvos/Tests/Fixtures/shuffle-reference.mjs
// rewrites shuffle_fixture.json beside this file.
//
// mulberry32(seed) returns a Double in [0, 1). The steps are UInt32 wrapping
// arithmetic so they match JavaScript's Math.imul and >>> and the Swift port.
// Fisher-Yates runs i from n-1 down to 1. There is no draw at i = 0.
// j = floor(rand() * (i + 1)).
// When a deck is built, including the fresh deal after the previous one is
// exhausted, the channel already playing counts as last-played. If the deck
// has more than one channel and the first card is that channel, swap index 0
// with index 1. Do not reshuffle and do not draw another random number.
// A single playable channel may repeat. An empty scope deals nothing.
// A selected region wins over Beyond. Beyond with no region is extension
// channels only (tiers other than heartbeat and core). Country, language,
// genre and search never narrow the deck.

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const MAIN = new Set(["heartbeat", "core"]);

function mulberry32(seed) {
  let state = seed >>> 0;
  return function word() {
    state = (state + 0x6D2B79F5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1) >>> 0;
    const mixed = Math.imul(t ^ (t >>> 7), t | 61) >>> 0;
    t = (t ^ ((t + mixed) >>> 0)) >>> 0;
    return (t ^ (t >>> 14)) >>> 0;
  };
}

function classicMulberry32(seed) {
  let a = seed >>> 0;
  return function word() {
    let t = (a += 0x6D2B79F5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return (t ^ (t >>> 14)) >>> 0;
  };
}

function assertSameGenerator() {
  for (const seed of [0, 1, 7, 42, 99, 0x6d2b79f5, 0xffffffff]) {
    const a = mulberry32(seed);
    const b = classicMulberry32(seed);
    for (let i = 0; i < 10000; i++) {
      if (a() !== b()) throw new Error(`mulberry32 diverged at seed ${seed} draw ${i}`);
    }
  }
}

function unit(word) {
  return word() / 4294967296;
}

function permute(ids, word) {
  const a = ids.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(unit(word) * (i + 1));
    const tmp = a[i];
    a[i] = a[j];
    a[j] = tmp;
  }
  return a;
}

function avoidFirst(order, lastPlayed) {
  if (order.length > 1 && lastPlayed != null && order[0] === lastPlayed) {
    const tmp = order[0];
    order[0] = order[1];
    order[1] = tmp;
  }
  return order;
}

function playable(channels, medium, scope, region) {
  const ids = [];
  const seen = new Set();
  const selected = region && region !== "all" ? region : null;
  for (const entry of channels) {
    if (entry.offline || entry.medium !== medium || seen.has(entry.id)) continue;
    seen.add(entry.id);
    if (scope === "main" && !MAIN.has(entry.tier)) continue;
    if (scope === "region") {
      if (!selected || entry.region !== selected) continue;
    }
    if (scope === "beyond") {
      if (selected) {
        if (entry.region !== selected) continue;
      } else if (MAIN.has(entry.tier)) continue;
    }
    ids.push(entry.id);
  }
  return ids;
}

function fresh(seed) {
  return { word: mulberry32(seed), key: null, order: [], cursor: 0, observed: null };
}

function samePool(state, key, ids) {
  if (state.key !== key || state.order.length !== ids.length) return false;
  const have = new Set(state.order);
  return ids.every((id) => have.has(id));
}

function draw(state, channels, { medium, scope, region = null, playing = undefined }) {
  const ids = playable(channels, medium, scope, region);
  const key = `${medium}|${scope}|${region && region !== "all" ? region : ""}`;
  if (!ids.length) {
    state.key = key;
    state.order = [];
    state.cursor = 0;
    return null;
  }
  const onScreen = playing === undefined ? null : playing;
  if (!samePool(state, key, ids)) {
    state.key = key;
    state.order = avoidFirst(permute(ids, state.word), onScreen != null ? onScreen : state.observed);
    state.cursor = 0;
  } else if (onScreen != null) {
    const index = state.order.indexOf(onScreen);
    if (index >= 0) state.cursor = index + 1;
  }
  if (state.cursor >= state.order.length) {
    const last = onScreen != null ? onScreen : (state.observed != null ? state.observed : state.order[state.order.length - 1]);
    state.order = avoidFirst(permute(ids, state.word), last);
    state.cursor = 0;
  }
  const id = state.order[state.cursor];
  state.cursor += 1;
  state.observed = id;
  return { id, order: state.order.slice() };
}

function words(seed, count) {
  const word = mulberry32(seed);
  const out = [];
  for (let i = 0; i < count; i++) out.push(word());
  return out;
}

function fullOrder(channels, seed, medium, scope, region, playing) {
  const dealt = draw(fresh(seed), channels, { medium, scope, region, playing });
  if (!dealt) throw new Error(`empty ${medium} ${scope} ${region}`);
  return dealt.order;
}

function boundary(channels, seed, medium, scope, region) {
  const state = fresh(seed);
  const first = draw(state, channels, { medium, scope, region });
  let last = first;
  for (let i = 1; i < first.order.length; i++) last = draw(state, channels, { medium, scope, region });
  const next = draw(state, channels, { medium, scope, region });
  return { tail: last.id, head: next.id };
}

function boundarySeed(channels, medium, scope, region) {
  const ids = playable(channels, medium, scope, region);
  for (let seed = 1; seed < 20000; seed++) {
    const word = mulberry32(seed);
    const first = permute(ids, word);
    const second = permute(ids, word);
    if (second[0] === first[first.length - 1]) return seed;
  }
  throw new Error("no boundary seed");
}

function playingSeed(channels, medium, scope, region) {
  const ids = playable(channels, medium, scope, region);
  for (let seed = 1; seed < 20000; seed++) {
    const word = mulberry32(seed);
    const order = permute(ids, word);
    if (order[0] !== order[1]) return { seed, playing: order[0] };
  }
  throw new Error("no playing seed");
}

function regionChange(channels, seed, medium, scope, from, take, to) {
  const left = fresh(seed);
  const right = fresh(seed);
  let opening = null;
  for (let i = 0; i < take; i++) {
    const dealt = draw(left, channels, { medium, scope, region: from });
    draw(right, channels, { medium, scope, region: from });
    if (i === 0) opening = dealt.order;
  }
  const continued = draw(left, channels, { medium, scope, region: from });
  const reset = draw(right, channels, { medium, scope, region: to });
  return { openingOrder: opening, wouldHaveContinued: continued.id, resetOrder: reset.order };
}

function findRegionChange(channels, medium, scope, from, to, take) {
  for (let seed = 1; seed < 5000; seed++) {
    const sample = regionChange(channels, seed, medium, scope, from, take, to);
    const freshDeal = fullOrder(channels, seed, medium, scope, to, undefined);
    if (
      sample.resetOrder[0] !== sample.wouldHaveContinued &&
      sample.resetOrder.join("|") !== sample.openingOrder.join("|") &&
      sample.resetOrder.join("|") !== freshDeal.join("|")
    ) {
      return { seed, take, ...sample };
    }
  }
  throw new Error(`no region-change seed for ${scope}`);
}

const channels = [
  { id: "indus-tv-a", region: "indus", tier: "heartbeat", medium: "tv", country: "Pakistan", language: "Urdu", genre: "News" },
  { id: "indus-tv-b", region: "indus", tier: "heartbeat", medium: "tv", country: "Pakistan", language: "Punjabi", genre: "Music" },
  { id: "indus-radio-a", region: "indus", tier: "heartbeat", medium: "radio", country: "Pakistan", language: "Urdu", genre: "News" },
  { id: "indus-tv-off", region: "indus", tier: "heartbeat", medium: "tv", country: "Pakistan", language: "Urdu", genre: "News", offline: true },
  { id: "anatolia-tv-a", region: "anatolia", tier: "core", medium: "tv", country: "Turkiye", language: "Turkish", genre: "News" },
  { id: "anatolia-tv-b", region: "anatolia", tier: "core", medium: "tv", country: "Turkiye", language: "Turkish", genre: "Music" },
  { id: "anatolia-radio-a", region: "anatolia", tier: "core", medium: "radio", country: "Turkiye", language: "Turkish", genre: "Music" },
  { id: "levant-tv-a", region: "levant", tier: "core", medium: "tv", country: "Lebanon", language: "Arabic", genre: "News" },
  { id: "levant-radio-a", region: "levant", tier: "core", medium: "radio", country: "Lebanon", language: "Arabic", genre: "Music" },
  { id: "levant-radio-b", region: "levant", tier: "core", medium: "radio", country: "Palestine", language: "Arabic", genre: "Talk" },
  { id: "qafqaz-tv-a", region: "qafqaz", tier: "heartbeat", medium: "tv", country: "Azerbaijan", language: "Azerbaijani", genre: "News" },
  { id: "qafqaz-tv-b", region: "qafqaz", tier: "heartbeat", medium: "tv", country: "Georgia", language: "Georgian", genre: "Music" },
  { id: "arabia-tv-a", region: "arabia", tier: "core", medium: "tv", country: "Qatar", language: "Arabic", genre: "News" },
  { id: "arabia-radio-a", region: "arabia", tier: "core", medium: "radio", country: "Saudi Arabia", language: "Arabic", genre: "Quran" },
  { id: "nusantara-tv-a", region: "nusantara", tier: "islamicate", medium: "tv", country: "Indonesia", language: "Indonesian", genre: "News" },
  { id: "nusantara-tv-b", region: "nusantara", tier: "islamicate", medium: "tv", country: "Indonesia", language: "Indonesian", genre: "Music" },
  { id: "nusantara-radio-a", region: "nusantara", tier: "islamicate", medium: "radio", country: "Indonesia", language: "Indonesian", genre: "Music" },
  { id: "horn-tv-a", region: "horn", tier: "islamicate", medium: "tv", country: "Somalia", language: "Somali", genre: "News" },
  { id: "horn-radio-a", region: "horn", tier: "islamicate", medium: "radio", country: "Somalia", language: "Somali", genre: "Talk" },
  { id: "rumelia-radio-a", region: "rumelia", tier: "islamicate", medium: "radio", country: "Bosnia", language: "Bosnian", genre: "Music" },
  { id: "solo-tv", region: "maghreb", tier: "core", medium: "tv", country: "Morocco", language: "Arabic", genre: "News" },
];

assertSameGenerator();

const filters = { country: "Pakistan", language: "Urdu", genre: "News", query: "quran" };
const mainTv = fullOrder(channels, 1, "tv", "main", "indus");
if (!mainTv.includes("levant-tv-a") || !mainTv.includes("anatolia-tv-a")) {
  throw new Error("main order was narrowed by a filter");
}
if (mainTv.includes("indus-tv-off") || mainTv.includes("nusantara-tv-a") || mainTv.includes("solo-tv") === false) {
  // solo-tv is main-atlas (core). It must be in the main television deck.
}
if (!mainTv.includes("solo-tv")) throw new Error("solo-tv missing from main");
if (mainTv.includes("indus-tv-off")) throw new Error("offline channel entered the deck");

const regionIndus = fullOrder(channels, 42, "tv", "region", "indus");
const beyondIndus = fullOrder(channels, 42, "tv", "beyond", "indus");
if (regionIndus.join("|") !== beyondIndus.join("|")) {
  throw new Error("a selected region did not win over Beyond");
}

const played = playingSeed(channels, "tv", "main", null);
const playedOrder = fullOrder(channels, played.seed, "tv", "main", null, played.playing);
if (playedOrder[0] === played.playing) throw new Error("deck opened on the channel already playing");

const mainBoundary = boundarySeed(channels, "tv", "main", null);
const regionBoundary = boundarySeed(channels, "tv", "region", "indus");
const mainChange = findRegionChange(channels, "tv", "main", "indus", "anatolia", 2);
const regionScopeChange = findRegionChange(channels, "tv", "region", "indus", "anatolia", 1);

function orderRow(name, seed, medium, scope, region, playing) {
  return {
    name, seed, medium, scope, region: region ?? null, playing: playing ?? null,
    ids: fullOrder(channels, seed, medium, scope, region, playing),
  };
}

const fixture = {
  algorithm: {
    prng: "mulberry32",
    unit: "UInt32 word / 4294967296",
    fisherYates: "i from n-1 down to 1; no draw at i = 0; j = floor(unit * (i + 1)); swap i, j",
    boundary: "if the first card is the channel already playing and the deck has more than one channel, swap index 0 with index 1; do not reshuffle",
    playing: "a channel already playing when a deck is built counts as last-played",
    beyond: "a selected region wins over Beyond; Beyond with no region is extension channels only",
    filters: "country, language, genre and search do not narrow the deck",
    repeat: "one playable channel may repeat; zero playable channels deals nothing",
  },
  filters,
  channels,
  mulberry32: [
    { seed: 1, words: words(1, 8) },
    { seed: 7, words: words(7, 8) },
  ],
  orders: [
    { ...orderRow("main television, seed 1", 1, "tv", "main", "indus"), filters },
    orderRow("main radio, seed 7", 7, "radio", "main", "indus"),
    orderRow("Indus only, seed 42", 42, "tv", "region", "indus"),
    orderRow("Levant radio only, seed 99", 99, "radio", "region", "levant"),
    orderRow("Beyond with Indus selected is Indus, seed 42", 42, "tv", "beyond", "indus"),
    orderRow("Beyond with Horn selected is Horn, seed 3", 3, "tv", "beyond", "horn"),
    orderRow("Beyond with no region, television, seed 42", 42, "tv", "beyond", null),
    orderRow("Beyond with no region, radio, seed 3", 3, "radio", "beyond", null),
    orderRow("already playing is not dealt first", played.seed, "tv", "main", null, played.playing),
  ],
  boundary: [
    { name: "main television wraps the deck", seed: mainBoundary, medium: "tv", scope: "main", region: null, ...boundary(channels, mainBoundary, "tv", "main", null) },
    { name: "a two-channel region wraps the deck", seed: regionBoundary, medium: "tv", scope: "region", region: "indus", ...boundary(channels, regionBoundary, "tv", "region", "indus") },
  ],
  regionChange: [
    {
      name: "main atlas discards when the region changes",
      seed: mainChange.seed, medium: "tv", scope: "main", from: "indus", take: mainChange.take, to: "anatolia",
      openingOrder: mainChange.openingOrder, wouldHaveContinued: mainChange.wouldHaveContinued, resetOrder: mainChange.resetOrder,
    },
    {
      name: "region scope deals only the region switched to",
      seed: regionScopeChange.seed, medium: "tv", scope: "region", from: "indus", take: regionScopeChange.take, to: "anatolia",
      openingOrder: regionScopeChange.openingOrder, wouldHaveContinued: regionScopeChange.wouldHaveContinued, resetOrder: regionScopeChange.resetOrder,
    },
  ],
  repeat: [
    { name: "the only playable channel may repeat", seed: 1, medium: "tv", scope: "region", region: "maghreb", first: "solo-tv", second: "solo-tv" },
  ],
  empty: [
    { name: "a region with nothing of this medium", medium: "tv", scope: "region", region: "rumelia" },
    { name: "Beyond with a region that is not on the list", medium: "radio", scope: "beyond", region: "missing" },
  ],
};

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "shuffle_fixture.json");
writeFileSync(out, JSON.stringify(fixture, null, 2) + "\n");
console.log(`wrote ${out}`);
console.log(`playing ${played.seed} ${played.playing} -> ${playedOrder[0]}`);
console.log(`boundary ${mainBoundary}, ${regionBoundary}`);
console.log(`region-change ${mainChange.seed}, ${regionScopeChange.seed}`);
