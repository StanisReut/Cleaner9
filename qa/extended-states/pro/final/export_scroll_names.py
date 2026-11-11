import json,pathlib,shutil,re
from PIL import Image,ImageDraw
root=pathlib.Path(__file__).resolve().parent
manifest=json.loads((root/'scroll-attachments/manifest.json').read_text())
out=root/'scroll';out.mkdir(exist_ok=True)
for test in manifest:
 for a in test.get('attachments',[]):
  name=a.get('suggestedHumanReadableName',a.get('name','')); m=re.match(r'(max-[0-9]+-[0-9]+-(?:top|scroll-[0-9]+)(?:-ax)?)',name); name=m.group(1) if m else name;src=root/'scroll-attachments'/a['exportedFileName']
  if src.suffix.lower() in ['.png','.txt']:
   shutil.copy2(src,out/(name+src.suffix))
print('files',len(list(out.iterdir())))
