"""Extracts GM8 constants, functions, built-in variables and function argument types from OpenGMK.

Usage: python3 -I gen_builtins.py <OpenGMK/gm8emulator/src/gml/mappings.rs> <out.json> [kernel.rs]
Argument types come from each kernel function's `expect_args!(args, [int, real, ...])`; GM8 reads a
string passed as real/int as 0 and a real passed as string as "".
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

signatures = {}
if len(sys.argv) > 3:
    kernel = open(sys.argv[3]).read()
    bodies = {}
    starts = [(m.group(1), m.start()) for m in re.finditer(r"pub fn ([a-z0-9_]+)\(", kernel)]
    for (name, a), (_, b) in zip(starts, starts[1:] + [("", len(kernel))]):
        bodies[name] = kernel[a:b]
    for gml_name, fn in re.findall(r'"([a-zA-Z0-9_]+)"\s*=>\s*Function::\w+\(Game::([a-z0-9_]+)\)', funcs_block):
        m = re.search(r"expect_args!\(args, \[([a-z, ]*)\]\)", bodies.get(fn, ""))
        if m:
            signatures[gml_name] = [t.strip() for t in m.group(1).split(",") if t.strip()]

json.dump({"constants": constants, "variables": variables, "functions": functions, "signatures": signatures},
          open(sys.argv[2], "w"), indent=1)
print(f"{len(constants)} constants, {len(variables)} variables, {len(functions)} functions, "
      f"{len(signatures)} signatures")
