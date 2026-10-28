# Data contracts the native rooms read

Measured 2026-10-27 against the website checkout. Every path is served from
`https://khajistan-archive.pages.dev/<path>` unless named otherwise. The app reads the same files and
services the website reads; it keeps no second copy of any corpus.

| Room | Source | Shape and size | Filtering the website applies |
|---|---|---|---|
| Reading Room | RPC `reading_room_catalogue()`; edge function `reading-room-page`; `data/rr-modules.json` (behind the site password) | existing Swift `RRCatalogue`, `RRAPI` (tvOS core) | access is the page server's answer per page; rights-pending titles are cover-only |
| Screening Room | `data/khajistan-tv/vod.json` (behind the site password); edge function `vod-token` | existing Swift `Films` | full film only with a token from `vod-token`; sales paused 2026-10-05 |
| Pics/Vids | `pnv_media`, `pnv_accounts`, `pnv_facets()` | existing Swift `PicsVids` | server gates; left out of `KJ_APP_STORE` builds |
| Bazaar | `data/catalog.json` (~2.1 MB, 3,724 products) then Storefront API `product(handle)` for variants | short keys: `h` handle, `t` title, `i` image, `p` price, `c` currency, `pt` type, `r` region, `pp` physical price, `pd` digital price, `so` sold out, `o` original holding | drop no image, `o==1`, non-merch types (`kj-typetag.js` `MERCH_TYPES`), retired shelves, digital-only; over $2,800 shows "Price on request" |
| Bazaar checkout | Storefront GraphQL `cartCreate` → `cart.checkoutUrl` on `khajistan.myshopify.com` | public Storefront token in `scripts/kj-storefront-config.js` | checkout host must be the shop's own |
| Madrassa | 15 reference entries inline in `madrassa.html` (`var ENTRIES`); `data/journal-posts.json` (56 posts, full HTML `body`) | post: `title, handle, blog, publishedAt, theme, image, summary, body, kind` | only `kind == knowledge`; `theme == ARCHIVE FORENSICS` is Forensics |
| Street Dictionary | `data/lughat.json` (829 entries) | `id, lang, word, translit, meaning, region, register, sensitivity, verify, slur, access, concept` | High/Restricted entries set apart with a warning, never removed |
| Pakistan Music Index | `data/radio/tracks.json` (19,363), `channels.json`, `pressings.json` | `id, t, a, al, y, l, f, mood, theme` | metadata only, no playback |
| National Broadcast Register | `data/signal-room/national-services.json` (257 services) | `id, country_name, medium, name, broadcaster, service_scope, evidence_status, official_source_url` | none |
| Logos of the Middle World | `data/logos.json` (3,484) + `data/logos-thumbs.json` | `id, name, country, region, category, image_file, review` | only `review == false` with an `image_file` |
| Cinema of the Middle World | `cinema/iranian-cinema/data/films.json` (1,437), `cinema/pakistani-cinema/data/films.json` (6,179, 13.8 MB), `cinema/idents/data/screen-marks.json` | per sub-database | none |
| Television of the Middle World | `television/pakistani-dramas/data/dramas.json` (1,599) | `id, title, title_native, year, channel, genre, episodes, cast, director, writer` | none |
| Arabic Music Index | `data/arabic-music-index.json` (6,686) | `id, src, era, t, fmt, u` + optional keys | none |
| Persian Music Index | `data/persian-music-index.json` (45,568, 10.9 MB) | values stored as indexes into `dicts` | none |
| Film Censor Certificates | 52 `<article>` blocks inline in `censor-certificates.html` | `data-*` attributes | none; scans link to the Reading Room |

Counts are as measured on this date. The app derives counts from the feeds at run time and never
prints one of these figures as fixed copy.
