"""Report text mismatches for review; never label an image visually passed."""
import argparse,json,pathlib,re
parser=argparse.ArgumentParser();parser.add_argument('--captures',required=True);parser.add_argument('--ocr',required=True);parser.add_argument('--source',required=True)
a=parser.parse_args();capture=pathlib.Path(a.captures);ocr=pathlib.Path(a.ocr);source=pathlib.Path(a.source)
def norm(s):return re.sub(r'[^a-z0-9]','',s.lower())
def intersect(a,b):
    x=max(a['x'],b['x']);y=max(a['y'],b['y']);r=min(a['x']+a['width'],b['x']+b['width']);d=min(a['y']+a['height'],b['y']+b['height'])
    return dict(x=x,y=y,width=max(0,r-x),height=max(0,d-y))
results=[]
for row in json.loads((capture/'capture-manifest.json').read_text()):
    fid=row['id'].replace(':','-');file=ocr/(fid+'.json')
    if not file.exists():continue
    observed=json.loads(file.read_text());joined=norm(' '.join(w['text'] for w in observed));root=json.loads((source/(fid+'.json')).read_text());expected=[]
    def visit(n,clip):
        if n.get('visible') is False or n.get('name')=='StatusBar' or n.get('name','').startswith('iOS / Bottom safe area'):return
        box=n.get('absoluteBoundingBox',clip);visible=intersect(box,clip)
        if n['type']=='TEXT' and box['width']*box['height']>0 and visible['width']*visible['height']/(box['width']*box['height'])>.85:
            text=n.get('characters','');key=norm(text)
            if len(key)>=3:expected.append(text)
        nextclip=intersect(clip,box) if n.get('clipsContent',False) else clip
        for child in n.get('children',[]):visit(child,nextclip)
    visit(root,root['absoluteBoundingBox'])
    missing=[text for text in dict.fromkeys(expected) if norm(text) not in joined and not any(norm(text) in norm(w['text']) for w in observed)]
    results.append(dict(id=row['id'],name=row['name'],missingText=missing,ocrText=[w['text'] for w in observed],status='needs visual review',emptyCapture=len(observed)<2))
(capture/'text-review.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
print('Text reviewed:',len(results),'frames; mismatch signals:',sum(bool(r['missingText']) for r in results),'(signals require human/model inspection)')
