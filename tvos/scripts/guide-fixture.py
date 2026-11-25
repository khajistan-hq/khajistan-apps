#!/usr/bin/env python3
"""Cuts the guide screenshots' schedule fixture from a month's programming file.

    python3 tvos/scripts/guide-fixture.py <programming-YYYY-MM.json> <out.json> <day>,<next day>

UITests/Fixtures/programming-2026-11-24.json was cut on 2026-11-24 from the November 2026 file
with 2026-11-24,2026-11-25. Slot programmes are indexes into programme_order, so they are renumbered.
"""
import json,sys
src,dst=sys.argv[1],sys.argv[2]
p=json.load(open(src))
days={d['date']:d for d in p['days']}
order=p['programme_order']
# The fields Programming.Programme decodes, less play_url (a fifth of the bytes, and a schedule
# file plays no programme); the file carries more.
FIELDS=['id','title','seconds','nominal_minutes','clean_start','clean_end','show','channel','audio_only','custodian','transfer','work_kind','country','description','subtitle_url','display_title','year','kind_line']
used=[];seen={}
def remap(day, lo=0, hi=10**9):
    out=dict(day); out['channels']={}
    for ch,slots in day['channels'].items():
        ns=[]
        for s in slots:
            st=s.get('start_second',s['start_minute']*60); en=st+s.get('seconds',s['minutes']*60)
            if en<=lo or st>=hi: continue
            s=dict(s); idx=[]
            for i in s['programmes']:
                pid=order[i]
                if pid not in seen: seen[pid]=len(used); used.append(pid)
                idx.append(seen[pid])
            s['programmes']=idx; ns.append(s)
        out['channels'][ch]=ns
    return out
# Two consecutive days, cut to the hours a guide opened at 22:10 on the first reads:
# the first day's strips that end after 22:00, the second day's that start before 12:00.
keep=sys.argv[3].split(',')
out={'_meta':p['_meta'],'shows':p['shows'],'days':[remap(days[keep[0]],lo=22*3600),remap(days[keep[1]],hi=12*3600)]}
out['programme_order']=used
out['programmes']={k:{f:v for f,v in p['programmes'][k].items() if f in FIELDS} for k in used}
s=json.dumps(out,ensure_ascii=False,separators=(',',':'))
open(dst,'w').write(s); print(len(s.encode()),len(used))
