import json, pathlib, subprocess, time, hashlib
from PIL import Image, ImageStat

ROOT = pathlib.Path(__file__).resolve().parent
DEVICE = '199C3299-1F62-4EFF-B5B2-9429867F57EA'
APP = 'test.com.PhotoCleanerApp'
PLAN = json.loads((ROOT.parent/'plan.json').read_text())

def run(args, timeout=25):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'{args}: {result.stderr}')
    return result.stdout

def capture(key, args, kind):
    record = {'id': key, 'kind': kind, 'device': DEVICE, 'status': 'pending', 'findings': []}
    image = ROOT/(key.replace(':','-')+'.png')
    try:
        run(['xcrun','simctl','launch','--terminate-running-process',DEVICE,APP]+args, 45)
        time.sleep(3)
        for attempt in range(2):
            run(['xcrun','simctl','io',DEVICE,'screenshot','--display=1',str(image)], 25)
            with Image.open(image) as im:
                w,h=im.size
                stats=ImageStat.Stat(im.convert('RGB').crop((w*.1,h*.15,w*.9,h*.85)))
                blank=all(v>250 for v in stats.mean) and max(stats.stddev)<3
            if not blank: break
            record['findings'].append('Blank transition capture; retried once after 4 seconds.')
            if attempt==0: time.sleep(4)
        record['capture_status']='blank' if blank else 'captured'
        if blank: record['status']='blocked'
        record['screenshot']=str(image)
        record['sha256']=hashlib.sha256(image.read_bytes()).hexdigest()
    except (subprocess.TimeoutExpired, RuntimeError) as error:
        record['status']='blocked'; record['capture_status']='failed'; record['findings'].append(str(error))
    (ROOT/(key.replace(':','-')+'.json')).write_text(json.dumps(record,indent=2))
    print(key, record.get('capture_status'),flush=True)

if __name__=='__main__':
    run(['xcrun','simctl','ui',DEVICE,'content_size','accessibility-extra-extra-extra-large'])
    for fid in PLAN['fidelity_ids_at_max_text']:
        capture('maxtext-'+fid,['--fidelity-frame',fid],'max-text')
    run(['xcrun','simctl','ui',DEVICE,'content_size','large'])
    for route in PLAN['real_routes']:
        capture('real-'+route,['--qa-screen',route],'real-default-text')
