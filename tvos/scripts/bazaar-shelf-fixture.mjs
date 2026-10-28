// Writes what the website's own code puts on each Bazaar shelf, for the core test that holds the
// app's port (Core/Bazaar.swift) to it:
//   node scripts/bazaar-shelf-fixture.mjs <archive checkout> <out.json>
// It runs archive/scripts/kj-typetag.js unchanged and applies bazaar.html's fromCatalog() test:
// `p.i && kjCatalogMerchCategory(p)`, shelf `kjMerchShelf(PT_CAT[p.pt], p)`.
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';

const [archive, out] = process.argv.slice(2);
if (!archive || !out) { console.error('usage: bazaar-shelf-fixture.mjs <archive> <out.json>'); process.exit(2); }
const window = {};
vm.runInNewContext(fs.readFileSync(path.join(archive, 'scripts/kj-typetag.js'), 'utf8'), { window });
const catalog = JSON.parse(fs.readFileSync(path.join(archive, 'data/catalog.json'), 'utf8'));
const shelves = {};
for (const p of catalog.products || []) {
  if (!p.h) continue;
  shelves[p.h] = (p.i && window.kjCatalogMerchCategory(p)) ? window.kjMerchShelf(window.kjMerchProductTypes[p.pt], p) : null;
}
fs.writeFileSync(out, JSON.stringify(shelves));
const on = Object.values(shelves).filter(Boolean).length;
console.log(`${Object.keys(shelves).length} products, ${on} on a shelf`);
