import pathlib,json,sys
from PIL import Image,ImageDraw
root=pathlib.Path(__file__).resolve().parent
mode=sys.argv[1]
rows=json.loads((root/mode/'cells.json').read_text())
refs=pathlib.Path.home()/'.figma_cache/Cleaner-9/audit-2026-11-10/renders'
for start in range(0,len(rows),6):
    if len(rows[start:start+6])<6 and '--final' not in sys.argv:continue
    canvas=Image.new('RGB',(1500,1260),'#dddddd');d=ImageDraw.Draw(canvas)
    for j,row in enumerate(rows[start:start+6]):
        x=(j%3)*500;y=(j//3)*630
        d.text((x+4,y+2),row['key']+' '+row['name'][:35],fill='black')
        paths=row['evidence'][:1]
        if mode=='max_text':paths.append(str(refs/(row['id_or_route'].replace(':','-')+'.png')))
        for k,path in enumerate(paths):
            im=Image.open(path).convert('RGBA');bg=Image.new('RGBA',im.size,'white');bg.alpha_composite(im);im=bg.convert('RGB')
            scale=.2 if k==0 else .6
            im=im.resize((round(im.width*scale),round(im.height*scale)))
            canvas.paste(im,(x+k*270,y+28))
    canvas.save(root/mode/f'sheet-{start//6:02}.jpg',quality=94)
print(len(rows))
