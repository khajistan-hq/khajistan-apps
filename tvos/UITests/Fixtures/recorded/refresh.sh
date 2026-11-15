#!/bin/sh
# Re-records the answers UI tests read with -kjfixtures (KJFixtureProtocol in SupabaseRoute.swift):
# the receiver's index, every region shard (Indus whole, the others cut to 20 channels: the set can
# open on any region), the three feeds cut to the channels those name, the map shapes, and the chat
# room list. Chat lines stay empty. Run from anywhere; commit what changes.
set -eu
cd "$(dirname "$0")"
site=https://khajistan-archive.pages.dev
raw=$(mktemp -d)
for f in receiver-index.json denylist.json off-air-suspects.json health.json; do
  curl -fsS -A Khajistan-iOS/1.0 -o "$raw/$f" "$site/data/open-frequencies/$f"
done
mkdir -p "$raw/regions" data/open-frequencies/regions rest/v1
python3 -c "import json,sys; print('\n'.join(json.load(open(sys.argv[1]))['regionFiles'].values()))" "$raw/receiver-index.json" |
  while read -r path; do curl -fsS -A Khajistan-iOS/1.0 -o "$raw/regions/$(basename "$path")" "$site$path"; done
curl -fsS -o data/region-shapes.json "$site/data/region-shapes.json"
python3 - "$raw" <<'PY'
import glob, json, os, re, sys
raw, out = sys.argv[1], 'data/open-frequencies/'
for old in glob.glob(out + 'regions/*.json'):
    os.remove(old)
text = open(raw + '/receiver-index.json').read()
for path in glob.glob(raw + '/regions/*.json'):
    shard = json.load(open(path))
    if os.path.basename(path) != 'indus.json':
        shard['channels'] = shard['channels'][:20]
    json.dump(shard, open(out + 'regions/' + os.path.basename(path), 'w'), ensure_ascii=False)
    text += json.dumps(shard)
ids = set(re.findall(r'"id": ?"([^"]+)"', text))
h = json.load(open(raw + '/health.json')); h.pop('counts', None)
h['results'] = [r for r in h['results'] if r['channelId'] in ids]
d = json.load(open(raw + '/denylist.json')); d['disabledChannelIds'] = [i for i in d['disabledChannelIds'] if i in ids]
o = json.load(open(raw + '/off-air-suspects.json'))
o['offAirChannelIds'] = [i for i in o['offAirChannelIds'] if i in ids]
o['reasons'] = {k: v for k, v in o['reasons'].items() if k in ids}
for name, value in (('health.json', h), ('denylist.json', d), ('off-air-suspects.json', o)):
    json.dump(value, open(out + name, 'w'), ensure_ascii=False)
PY
cp "$raw/receiver-index.json" data/open-frequencies/
rm -rf "$raw"
key=$(sed -n 's/.*anonKey = "\([^"]*\)".*/\1/p' ../../../../ios/Khajistan/Core/Config.swift)
curl -fsS -H "apikey: $key" -H "Authorization: Bearer $key" -o rest/v1/chat_rooms \
  "https://qojysegeddztsxdmhjfb.supabase.co/rest/v1/chat_rooms?select=slug,label,kind,region,country,category,adult,description,status,slow_mode_seconds&status=eq.approved&order=created_at.asc"
echo '[]' > rest/v1/chat_messages
echo '[]' > rest/v1/chat_message_state
