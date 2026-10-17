"""Extracts GM8 constants, functions and built-in variables from OpenGMK's mappings.rs.

Usage: python3 -I gen_builtins.py <OpenGMK/gm8emulator/src/gml/mappings.rs> <out.json>
"""
import json, re, sys

src = open(sys.argv[1]).read()
consts_block = src[src.index("pub const CONSTANTS"):src.index("pub const INSTANCE_VARIABLES")]
vars_block = src[src.index("pub const INSTANCE_VARIABLES"):src.index("pub const FUNCTIONS")]
funcs_block = src[src.index("pub const FUNCTIONS"):]

# Constants are written as `"name" => constants::NAME` in the map and `pub const NAME: f64 = v;` above.
values = {k: float(v) for k, v in re.findall(r"pub const ([A-Z0-9_]+): f64 = ([-0-9.e]+);", src)}
constants = {}
for name, ref in re.findall(r'"([a-z0-9_]+)"\s*=>\s*([^,\n]+),', consts_block):
    ref = ref.strip()
    if ref.startswith("constants::"):
        constants[name] = values.get(ref.split("::")[1], 3.141592653589793 if ref.endswith("::PI") else None)
    else:
        try:
            constants[name] = float(ref)
        except ValueError:
            pass

variables = re.findall(r'\("([a-z0-9_]+)",\s*InstanceVariable::', vars_block)
functions = re.findall(r'"([a-zA-Z0-9_]+)"\s*=>\s*Function::', funcs_block)
json.dump({"constants": constants, "variables": variables, "functions": functions},
          open(sys.argv[2], "w"), indent=1)
print(f"{len(constants)} constants, {len(variables)} variables, {len(functions)} functions")
