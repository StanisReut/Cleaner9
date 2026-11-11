from PIL import Image, ImageDraw
import json,pathlib
root=pathlib.Path(__file__).resolve().parent
plan=json.loads((root.parent/'plan.json').read_text())
keys=['maxtext-'+x.replace(':','-') for x in plan['fidelity_ids_at_max_text']]+['real-'+x for x in plan['real_routes']]+['denied-'+x for x in plan['denied_routes']]
for start in range(0,len(keys),6):
    subset=keys[start:start+6]
    if not all((root/(k+'.png')).exists() for k in subset):continue
    sheet=Image.new('RGB',(1125,1394),'#ddd');draw=ImageDraw.Draw(sheet)
    for n,key in enumerate(subset):
        im=Image.open(root/(key+'.png')).convert('RGB').resize((375,667))
        x=(n%3)*375;y=(n//3)*697
        draw.text((x+4,y+8),key,fill='black');sheet.paste(im,(x,y+30))
    sheet.save(root/f'sheet-{start:02}.jpg',quality=92)
