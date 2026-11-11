import importlib.util,pathlib,json
root=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("cap",root.parent/"capture.py");m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.ROOT=root/"normal";m.ROOT.mkdir(exist_ok=True)
m.run(["xcrun","simctl","ui",m.DEVICE,"content_size","large"])
m.capture("max_text",["119:2804","94:4372","47:56","159:3259","129:2217","127:2092","51:52"])
