"""Capture deterministic production-view states; capture is NOT a passing verdict."""
import argparse, json, pathlib, subprocess, time
from PIL import Image, ImageStat

parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--ids', nargs='*')
parser.add_argument('--settle', type=float, default=1.0)
parser.add_argument('--bottom', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent
frames = json.loads((root/'figma-frames.json').read_text())
if args.ids:
    frames = [f for f in frames if f['id'] in args.ids]
out = pathlib.Path(args.output); out.mkdir(parents=True, exist_ok=True)
manifest = []
for index, frame in enumerate(frames):
    screenshot = out/(frame['id'].replace(':','-')+('-bottom' if args.bottom else '')+'.png')
    subprocess.run(['xcrun','simctl','launch','--terminate-running-process',args.device,'test.com.PhotoCleanerApp','--fidelity-frame',frame['id']]+(['--fidelity-bottom'] if args.bottom else []), check=True, capture_output=True)
    time.sleep(max(3.0, args.settle) if index == 0 else args.settle)
    for attempt in range(3):
        result=subprocess.run(['xcrun','simctl','io',args.device,'screenshot','--display=1',str(screenshot)], capture_output=True, text=True, timeout=20)
        if result.returncode:
            (out/'capture-error.txt').write_text(result.stderr)
            raise RuntimeError(f"Screenshot failed ({result.returncode}): {result.stderr}")
        with Image.open(screenshot) as image:
            width,height=image.size
            stats=ImageStat.Stat(image.convert('RGB').crop((width*.1,height*.15,width*.9,height*.85)))
            blank=all(v>250 for v in stats.mean) and max(stats.stddev)<3
        if not blank:break
        time.sleep(1)
    manifest.append(dict(frame, screenshot=str(screenshot), verdict='capture_error' if blank else 'pending'))
    (out/'capture-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
    print(f"Captured {index+1}/{len(frames)}: {frame['id']} {frame['name']}", flush=True)
