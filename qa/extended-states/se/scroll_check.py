import json,subprocess,time,pathlib,hashlib
from capture import ROOT,DEVICE,APP,run,capture

IDS=['51:87','51:145','51:211','51:411','59:1953','78:5059','94:1327','94:1517','94:2057','94:2930','94:4213','119:3280','127:2092','129:2123','141:2383','129:2217','147:2387','147:2719','147:2774','147:3080','147:3269','147:3340','147:3669','235:2861','235:2908','235:2955','94:3869','94:4372','159:3259','159:3189']
run(['xcrun','simctl','ui',DEVICE,'content_size','accessibility-extra-extra-extra-large'])
capture('maxtext-4:214',['--fidelity-frame','4:214'],'max-text')
for fid in ['4:214']+IDS:
    key='scroll-'+fid.replace(':','-');record={'id':fid,'steps':[]}
    try:
        run(['xcrun','simctl','launch','--terminate-running-process',DEVICE,APP,'--fidelity-frame',fid],45)
        time.sleep(3)
        ax=run(['idb','--companion','localhost:10971','ui','describe-all','--json'],20)
        (ROOT/(key+'-before-ax.json')).write_text(ax)
        for n in range(6):
            run(['idb','--companion','localhost:10971','ui','swipe','180','480','180','270','--duration','0.3'],20)
            time.sleep(.2)
            if n in [1,5]:
                image=ROOT/(key+f'-{n+1}.png')
                run(['xcrun','simctl','io',DEVICE,'screenshot','--display=1',str(image)],25)
                record['steps'].append(str(image))
        ax=run(['idb','--companion','localhost:10971','ui','describe-all','--json'],20)
        (ROOT/(key+'-after-ax.json')).write_text(ax)
        record['status']='captured'
    except (RuntimeError,subprocess.TimeoutExpired) as e:
        record['status']='blocked';record['error']=str(e)
    (ROOT/(key+'.json')).write_text(json.dumps(record,indent=2))
    print(key,record['status'],flush=True)
