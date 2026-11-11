import json,pathlib,collections
root=pathlib.Path(__file__).resolve().parent
rows=json.loads((root/'figma-frames.json').read_text());reports={}
for device in ['se','pro','max']:
    path=root/f'fidelity-{device}-verdicts.json'
    data=json.loads(path.read_text()) if path.exists() else []
    if isinstance(data,dict):data=data['frames']
    reports[device]={r['id']:r for r in data}
icons={'matched':'✅','mismatch':'❌','partial':'◐','os-owned':'iOS','pending':'⏳'}
totals=collections.Counter(reports[d].get(r['id'],{}).get('status','pending') for r in rows for d in reports)
text='# Figma fidelity audit — 2026-11-10\n\n'
text+='198 frames × 3 sizes = 594 cells. Last inspected captures: '+', '.join(f'{icons[k]} {v} {k}' for k,v in totals.items())+'.\n\n'
text+='A match means inspected geometry, typography, colors and state under the recorded safe-area/adaptive-layout and dynamic-photo exclusions. It is not a pixel-identity guarantee. OS-owned dialogs are tracked separately. An old mismatch remains until its corrected capture is inspected. Per-frame JSON reports contain evidence paths and image hashes.\n\n'
text+='Native interaction evidence is recorded separately in [native-regression/README.md](native-regression/README.md): system handoffs, modal hit targets, contact-backup idempotence, real video seek/replay and deletion of an isolated test duplicate. Visual fixture matches do not establish live provider availability, StoreKit purchases or successful Vision segmentation on a physical device.\n\n'
text+='| Figma frame | Name | SE | Pro | Max |\n|---|---|---|---|---|\n'
for r in rows:
    text+='| ['+r['id']+'](https://www.figma.com/design/RTz6noaj3Ss8uUpCuTOr4T?node-id='+r['id'].replace(':','-')+') | '+r['name'].replace('|','/')+' | '+' | '.join(icons[reports[d].get(r['id'],{}).get('status','pending')] for d in reports)+' |\n'
(root/'FIDELITY.md').write_text(text)
print(dict(totals))
