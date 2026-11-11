import json, pathlib, subprocess, time, hashlib
from PIL import Image, ImageStat

ROOT = pathlib.Path(__file__).resolve().parent
DEVICE = '5E42ECEA-6985-4514-8348-CFC60913613B'
PLAN = json.loads((ROOT.parent/'plan.json').read_text())
FRAMES = {x['id']: x for x in json.loads((ROOT.parents[1]/'figma-frames.json').read_text())}

def run(args, timeout=45):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=True)

def capture(mode, values):
    manifest = []
    out = ROOT/mode
    out.mkdir(exist_ok=True)
    for value in values:
        name = FRAMES[value]['name'] if mode == 'max_text' else value
        row = dict(key=f'{mode}:{value}', mode=mode, id_or_route=value, name=name,
                   status='blocked', comparison='adaptation' if mode=='max_text' else 'source_chrome',
                   findings=[], evidence=[])
        if mode == 'max_text': row['source_frame'] = value
        try:
            run(['xcrun','simctl','launch','--terminate-running-process',DEVICE,
                 'test.com.PhotoCleanerApp','--fidelity-frame' if mode=='max_text' else '--qa-screen',value])
            time.sleep(4)
            shot = out/(value.replace(':','-')+'.png')
            for attempt in range(2):
                run(['xcrun','simctl','io',DEVICE,'screenshot','--display=1',str(shot)],20)
                with Image.open(shot) as im:
                    w,h=im.size
                    s=ImageStat.Stat(im.convert('RGB').crop((w*.1,h*.15,w*.9,h*.85)))
                    blank=all(v>250 for v in s.mean) and max(s.stddev)<3
                if not blank: break
                time.sleep(5)
            row['evidence']=[str(shot)]
            row['capture_sha256']=hashlib.sha256(shot.read_bytes()).hexdigest()
            row['findings']=['Blank capture after bounded retry.' if blank else 'Pending visual inspection; capture alone is not a pass.']
        except (subprocess.SubprocessError, OSError) as exc:
            row['findings']=[str(exc)]
        manifest.append(row)
        (out/'cells.json').write_text(json.dumps(manifest,indent=2))
        print(mode,value,len(manifest),'/',len(values),flush=True)

if __name__ == '__main__':
    import sys
    mode=sys.argv[1]
    values=PLAN['fidelity_ids_at_max_text' if mode=='max_text' else 'real_routes' if mode=='real' else 'denied_routes']
    capture(mode,values)
