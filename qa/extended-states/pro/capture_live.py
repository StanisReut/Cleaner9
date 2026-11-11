import json, pathlib, subprocess, time

root = pathlib.Path(__file__).resolve().parent
plan = json.loads((root.parent / 'plan.json').read_text())
device = plan['devices']['pro']
app = 'test.com.PhotoCleanerApp'

def run(args, timeout=45):
    return subprocess.run(args, capture_output=True, text=True, check=True, timeout=timeout)

def capture(mode, route):
    out = root / mode
    out.mkdir(exist_ok=True)
    run(['xcrun', 'simctl', 'launch', '--terminate-running-process', device, app, '--qa-screen', route])
    time.sleep(4)
    run(['xcrun', 'simctl', 'io', device, 'screenshot', '--display=1', str(out / (route + '.png'))])
    tree = run(['idb', '--companion', 'localhost:19077', 'ui', 'describe-all', '--udid', device, '--json'])
    (out / (route + '-ax.json')).write_text(tree.stdout)
    print(mode, route, flush=True)

run(['xcrun', 'simctl', 'ui', device, 'content_size', 'large'])
for route in plan['real_routes']:
    capture('real', route)
for service in ['photos', 'contacts', 'calendar']:
    run(['xcrun', 'simctl', 'privacy', device, 'revoke', service, app])
for route in plan['denied_routes']:
    capture('denied', route)
for service in ['photos', 'contacts', 'calendar']:
    run(['xcrun', 'simctl', 'privacy', device, 'grant', service, app])
