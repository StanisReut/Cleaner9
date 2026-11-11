import pathlib,json,subprocess,time,hashlib
from capture import ROOT,DEVICE,run
ids=['4:214','47:56','51:52','51:211','51:411','51:915','59:1683','59:1953','78:5059','94:1517','94:2930','94:3224','94:4213','119:1912','119:3280','127:2092','129:2217','147:2387','147:2719','147:3080','147:3269','147:3340','159:2752','159:2979','235:2861','235:2908','235:2955']
out=ROOT/'scroll';out.mkdir(exist_ok=True)
results=[]
for value in ids:
    row={'id':value,'evidence':[]}
    try:
        run(['xcrun','simctl','launch','--terminate-running-process',DEVICE,'test.com.PhotoCleanerApp','--fidelity-frame',value])
        time.sleep(3)
        ax=run(['idb','ui','describe-all','--udid',DEVICE,'--json'],20)
        (out/(value.replace(':','-')+'-before.json')).write_text(ax.stdout)
        for _ in range(3):
            run(['idb','ui','swipe','220','760','220','300','--duration','0.4','--udid',DEVICE],20)
        time.sleep(1)
        ax=run(['idb','ui','describe-all','--udid',DEVICE,'--json'],20)
        axp=out/(value.replace(':','-')+'-after.json');axp.write_text(ax.stdout)
        shot=out/(value.replace(':','-')+'.png')
        run(['xcrun','simctl','io',DEVICE,'screenshot','--display=1',str(shot)],20)
        row['evidence']=[str(shot),str(axp)];row['sha256']=hashlib.sha256(shot.read_bytes()).hexdigest()
    except (subprocess.SubprocessError,OSError) as exc:row['error']=str(exc)
    results.append(row);(out/'manifest.json').write_text(json.dumps(results,indent=2))
    print(len(results),value,flush=True)
