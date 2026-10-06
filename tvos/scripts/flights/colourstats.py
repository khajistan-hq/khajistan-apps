import sys, json, numpy as np, cv2
sys.path.insert(0,'/tmp/kjhf'); from greykey import frames, probe, key
def stats(src, picks):
    w,h=probe(src); fr=list(frames(src,w,h)); B=np.median(np.stack(fr[-4:]).astype(np.float32),axis=0)
    px=[]
    for i in picks:
        P,a=key(fr[i],B); m=a>0.97
        F=(P[m]/np.maximum(a[m][:,None],1e-3)).astype(np.float32)/255
        lab=cv2.cvtColor(F.reshape(-1,1,3),cv2.COLOR_RGB2LAB).reshape(-1,3); px.append(lab)
    L=np.concatenate(px); return {'mean':L.mean(0).tolist(),'std':L.std(0).tolist(),'n':int(len(L))}
ref=[stats('take-1.mp4',[40,60,80]), stats('across-0.mp4',[20,40,55])]
refm={'mean':np.mean([r['mean'] for r in ref],0).tolist(),'std':np.mean([r['std'] for r in ref],0).tolist()}
out={'ref':refm}
for n,p in [('twirl','sd-twirl.mp4'),('swoop','sd-swoop.mp4'),('spiral','sd-spiral.mp4')]:
    w,h=probe(p); n_fr=sum(1 for _ in frames(p,w,h))
    out[n]=stats(p,[int(n_fr*0.25),int(n_fr*0.45),int(n_fr*0.6)])
json.dump(out,open('colour.json','w'),indent=1)
for k,v in out.items(): print(k,[round(x,1) for x in v['mean']],[round(x,1) for x in v['std']])
