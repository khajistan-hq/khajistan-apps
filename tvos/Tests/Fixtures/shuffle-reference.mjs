// Read-only check of tvos/Tests/Fixtures/shuffle_fixture.json.
//   node tvos/Tests/Fixtures/shuffle-reference.mjs
// The file is the website's fixture, copied as-is. This script does not write it.
//
// mulberry32 is the site's function and returns a Double in [0, 1).
// Fisher-Yates runs i from n-1 down to 1. There is no draw at i = 0.
// j = floor(rand() * (i + 1)).
// The first deck is not rearranged. When it is exhausted, deal again with the
// same stream. If the new deck has more than one id and its first id equals
// the last id drawn, swap index 0 with index 1.
// A directory click is not a draw. If the card at the cursor is the channel
// already playing and the pool has more than one channel, skip it and draw
// the next. If that skip exhausts the deck, reshuffle with the boundary rule,
// treating the playing channel as the last id drawn.

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const fixturePath = join(dirname(fileURLToPath(import.meta.url)), "shuffle_fixture.json");
const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));

function mulberry32(seed) {
  let a = seed >>> 0;
  return function unit() {
    a |= 0;
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function permute(ids, rand) {
  const shuffled = ids.slice();
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    const tmp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = tmp;
  }
  return shuffled;
}

function avoidFirst(order, lastPlayed) {
  if (order.length > 1 && lastPlayed != null && order[0] === lastPlayed) {
    const tmp = order[0];
    order[0] = order[1];
    order[1] = tmp;
  }
  return order;
}

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exitCode = 1;
  }
}

function same(actual, expected, message) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  assert(left === right, `${message}\n  got ${left}\n  want ${right}`);
}

const pools = { main: [], region: [], beyond: [] };
for (const channel of fixture.channels) {
  if (channel.beyond === false) pools.main.push(channel.id);
  if (channel.regions.includes(fixture.regionScope)) pools.region.push(channel.id);
  if (channel.beyond === true) pools.beyond.push(channel.id);
}
same(pools, fixture.pools, "pools");

for (const scope of ["main", "region", "beyond"]) {
  const rand = mulberry32(fixture.seeds[scope]);
  const ids = fixture.pools[scope];
  let order = permute(ids, rand);
  let cursor = 0;
  const dealt = [];
  for (let deck = 0; deck < fixture.draws[scope].decks.length; deck++) {
    const got = [];
    for (let n = 0; n < ids.length; n++) {
      if (cursor >= order.length) {
        order = avoidFirst(permute(ids, rand), order.at(-1));
        cursor = 0;
      }
      got.push(order[cursor]);
      cursor += 1;
    }
    dealt.push(got);
    same(got, order, `${scope} deck ${deck} order`);
  }
  same(dealt, fixture.draws[scope].decks, `${scope} decks`);
}

// main seed 2: one pure Surf, click indus-two, Surf lands on horn-news.
{
  const ids = fixture.pools.main;
  const rand = mulberry32(fixture.seeds.main);
  let order = permute(ids, rand);
  let cursor = 0;
  const first = order[cursor];
  cursor += 1;
  const playing = "indus-two";
  assert(order[cursor] === playing, "the card at the cursor is indus-two");
  if (playing && order.length > 1 && cursor < order.length && order[cursor] === playing) {
    cursor += 1;
  }
  same(order[cursor], "horn-news", "click indus-two, Surf lands on horn-news");
  same(order, fixture.draws.main.decks[0], "the click did not reshuffle");
  assert(first === "horn-diaspora", "the opening Surf is horn-diaspora");
}

// A click does not jump the cursor onto the clicked channel.
{
  const rand = mulberry32(fixture.seeds.main);
  const order = permute(fixture.pools.main, rand);
  const playing = "indus-two";
  let cursor = 0;
  if (playing && order.length > 1 && cursor < order.length && order[cursor] === playing) {
    cursor += 1;
  }
  same(order[cursor], "horn-diaspora", "a cold click of indus-two does not skip ahead");
}

// Skipping the last card reshuffles, treating that channel as the last id drawn.
{
  const ids = fixture.pools.main;
  const rand = mulberry32(fixture.seeds.main);
  let order = permute(ids, rand);
  let cursor = 0;
  for (let n = 0; n < ids.length - 1; n++) {
    cursor += 1;
  }
  const playing = "indus-one";
  let skipped = false;
  if (order.length > 1 && cursor < order.length && order[cursor] === playing) {
    cursor += 1;
    skipped = true;
  }
  assert(skipped && cursor >= order.length, "the skip exhausts the deck");
  order = avoidFirst(permute(ids, rand), playing);
  cursor = 0;
  same(order[cursor], "horn-news", "the reshuffle opens on horn-news");
  same(order, fixture.draws.main.decks[1], "skip-exhaust matches the second deck");
}

const fixtureHash = createHash("sha256").update(readFileSync(fixturePath)).digest("hex");
assert(
  fixtureHash === "3912779bf179b5cabc38e3c63b1bb775db7793d03b1fa219e2640c58e21d2f08",
  `fixture sha256 ${fixtureHash}`
);

// One mulberry32 stream per key. Main and Beyond ignore the region and resume.
// A region's stream does not feed another region's stream.
function hand(seed) {
  return { rand: mulberry32(seed), order: null, cursor: 0 };
}

function drawHand(state, ids, playing) {
  if (!state.order || state.order.length !== ids.length || ids.some((id) => !state.order.includes(id))) {
    state.order = permute(ids, state.rand);
    state.cursor = 0;
  }
  let skipped = false;
  if (playing && state.order.length > 1 && state.cursor < state.order.length && state.order[state.cursor] === playing) {
    state.cursor += 1;
    skipped = true;
  }
  if (state.cursor >= state.order.length) {
    state.order = avoidFirst(permute(ids, state.rand), skipped ? playing : state.order.at(-1));
    state.cursor = 0;
  }
  const id = state.order[state.cursor];
  state.cursor += 1;
  return { id, order: state.order.slice() };
}

{
  const state = hand(fixture.seeds.main);
  const first = drawHand(state, fixture.pools.main, null);
  const second = drawHand(state, fixture.pools.main, null);
  same(first.order, fixture.draws.main.decks[0], "main survives a region change");
  same(second.id, first.order[1], "main continues");
  same(second.order, first.order, "main order held");
}

{
  const state = hand(fixture.seeds.beyond);
  const first = drawHand(state, fixture.pools.beyond, null);
  const second = drawHand(state, fixture.pools.beyond, null);
  same(first.order, fixture.draws.beyond.decks[0], "beyond survives a region change");
  same(second.id, first.order[1], "beyond continues");
  same(second.order, first.order, "beyond order held");
}

{
  const horn = hand(fixture.seeds.region);
  const indus = hand(fixture.seeds.region);
  const opened = drawHand(horn, fixture.pools.region, null);
  const indusPool = ["indus-one", "indus-two"];
  const switched = drawHand(indus, indusPool, null);
  const resumed = drawHand(horn, fixture.pools.region, null);
  same(opened.order, fixture.draws.region.decks[0], "horn opening");
  same(resumed.id, opened.order[1], "horn resumes");
  same(resumed.order, opened.order, "horn order held");
  const again = drawHand(hand(fixture.seeds.region), indusPool, null);
  same(switched.order, again.order, "indus does not continue horn's stream");
  same(switched.id, again.id, "indus opens on its own stream");
}

if (process.exitCode) {
  console.error("shuffle fixture check failed");
} else {
  console.log("shuffle fixture check ok");
}
