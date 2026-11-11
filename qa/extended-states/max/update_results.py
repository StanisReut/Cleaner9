import json,pathlib,hashlib
root=pathlib.Path(__file__).resolve().parent
notes=json.loads((root/'notes.json').read_text()) if (root/'notes.json').exists() else {}
refs=pathlib.Path.home()/'.figma_cache/Cleaner-9/audit-2026-11-10/renders'
rows=[]
for mode in ['max_text','real','denied']:
    p=root/mode/'cells.json'
    if not p.exists():continue
    for row in json.loads(p.read_text()):
        key=row['id_or_route'] if mode=='max_text' else row['key']
        if key in notes:
            n=notes[key]
            row['status']=n['status'];row['findings']=n['findings']
            row['evidence']+=n.get('evidence',[])
        if row.get('source_frame'):
            ref=refs/(row['source_frame'].replace(':','-')+'.png')
            row['reference_sha256']=hashlib.sha256(ref.read_bytes()).hexdigest()
            row['reference']=str(ref)
        rows.append(row)
(root/'results.json').write_text(json.dumps(rows,indent=2))
print(len(rows))
