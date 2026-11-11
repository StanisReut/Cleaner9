from PIL import Image, ImageDraw
from pathlib import Path
import json

p = Path(__file__).resolve().parent
qa = p.parents[1]
frames = json.loads((qa / 'figma-frames.json').read_text())
wanted = json.loads((p.parent / 'plan.json').read_text())['fidelity_ids_at_max_text']
rows = [r for r in frames if r['id'] in wanted]
(p / 'sheets').mkdir(exist_ok=True)
for batch in range((len(rows) + 5) // 6):
    subset = rows[batch * 6:batch * 6 + 6]
    if not all((p / 'max-text' / (r['id'].replace(':', '-') + '.png')).exists() for r in subset):
        continue
    sheet = Image.new('RGB', (1500, 1160), '#dddddd')
    draw = ImageDraw.Draw(sheet)
    for j, row in enumerate(subset):
        x, y = (j % 3) * 500, (j // 3) * 580
        draw.text((x + 4, y + 4), row['id'] + ' ' + row['name'], fill='black')
        paths = [p / 'max-text' / (row['id'].replace(':', '-') + '.png'), Path.home() / '.figma_cache/Cleaner-9/audit-2026-11-10/renders' / (row['id'].replace(':', '-') + '.png')]
        for k, path in enumerate(paths):
            image = Image.open(path).convert('RGBA')
            bg = Image.new('RGBA', image.size, 'white')
            bg.alpha_composite(image)
            image = bg.convert('RGB')
            image.thumbnail((245, 550))
            sheet.paste(image, (x + k * 250, y + 24))
    sheet.save(p / 'sheets' / f'max-{batch:02}.jpg')
