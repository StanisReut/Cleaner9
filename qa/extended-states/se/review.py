import json,pathlib
ROOT=pathlib.Path(__file__).resolve().parent
FRAMES={r['id']:r for r in json.loads((ROOT.parent.parent/'figma-frames.json').read_text())}

def record(key,status,findings,evidence=None):
    mode,value=key.split(':',1)
    capture_key=('maxtext-' if mode=='max_text' else mode+'-')+value.replace(':','-')
    capture=ROOT/(capture_key+'.json')
    data=json.loads(capture.read_text()) if capture.exists() else {}
    item={'key':key,'mode':mode,'id_or_route':value,'name':FRAMES.get(value,{}).get('name',value),'status':status,'comparison':'adaptation' if mode=='max_text' else 'source_chrome','findings':findings,'evidence':evidence or [data.get('screenshot',str(ROOT/(capture_key+'.png')))]}
    if mode=='max_text':item['source_frame']=value;item['reference_note']='No maximum-text Figma source; usability adaptation assessed, not exact design fidelity.'
    if data.get('sha256'):item['capture_sha256']=data['sha256']
    out=ROOT/'results.json';rows=json.loads(out.read_text()) if out.exists() else []
    rows=[r for r in rows if r['key']!=key]+[item]
    out.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
