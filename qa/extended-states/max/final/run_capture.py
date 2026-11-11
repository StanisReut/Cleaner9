import importlib.util,pathlib,subprocess,json,sys
root=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("capture",root.parent/"capture.py");m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);m.ROOT=root
mode=sys.argv[1]
size="accessibility-extra-extra-extra-large" if mode=="max_text" else "large"
m.run(["xcrun","simctl","ui",m.DEVICE,"content_size",size])
values=m.PLAN["fidelity_ids_at_max_text" if mode=="max_text" else "real_routes" if mode=="real" else "denied_routes"]
if mode=="denied":
 for permission in ["photos","contacts","calendar"]:m.run(["xcrun","simctl","privacy",m.DEVICE,"revoke",permission,"test.com.PhotoCleanerApp"])
m.capture(mode,values)

