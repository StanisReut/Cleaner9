import json,pathlib,subprocess,time
root=pathlib.Path(__file__).resolve().parent
plan=json.loads((root.parent.parent/'plan.json').read_text())
d='1599FF1F-F246-49A2-9AE7-3CB25F6375B8';app='test.com.PhotoCleanerApp'
def run(a):return subprocess.run(a,check=True,capture_output=True,text=True,timeout=60)
def capture(mode,route):
 p=root/mode;p.mkdir(exist_ok=True)
 run(['xcrun','simctl','launch','--terminate-running-process',d,app,'--qa-screen',route]);time.sleep(8 if route in ['scan','photos','videos','swipe','contacts','calendar'] else 3)
 run(['xcrun','simctl','io',d,'screenshot','--display=1',str(p/(route+'.png'))]);print(mode,route,flush=True)
run(['xcrun','simctl','ui',d,'content_size','large'])
for r in plan['real_routes']:capture('real',r)
for s in ['photos','contacts','calendar']:run(['xcrun','simctl','privacy',d,'revoke',s,app])
for r in plan['denied_routes']:capture('denied',r)
for s in ['photos','contacts','calendar']:run(['xcrun','simctl','privacy',d,'grant',s,app])
