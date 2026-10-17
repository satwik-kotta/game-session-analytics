"""Inline results.json and cubes.json into dashboard/template.html -> dashboard/index.html."""
import json, os
root = os.path.join(os.path.dirname(__file__), "..")
t = open(os.path.join(root, "dashboard", "template.html")).read()
res = open(os.path.join(root, "outputs", "results.json")).read()
cubes = open(os.path.join(root, "outputs", "cubes.json")).read()
open(os.path.join(root, "dashboard", "index.html"), "w").write(t.replace("__RES__", res).replace("__CUBES__", cubes))
print("dashboard/index.html written")
