import json
import sys
from store import LuaOut as LuaOut
from pulpscript import transpile_event, PulpScriptContext, istoken

if len(sys.argv) >= 1:
    file = sys.argv[1]
else:
    print("usage: python3 " + sys.argv[0] + " pulp.json")
    exit(1)

with open(file) as f:
    pulp = json.load(f)

ctx = PulpScriptContext()

code = "import \"pulp\""

def getScriptName(type, id):
    if type == 0 and id == 0:
        return "game"
    elif type == 1 and id < len(pulp["rooms"]):
        return pulp["rooms"][id]["name"]
    elif type == 2 and id < len(pulp["tiles"]):
        return pulp["tiles"][id]["name"]
    
    ctx.errors += [f"unknown script, type {type}, id {id}"]
    return f"__UNKNOWN_SCRIPT_{type}_{id}"

class Script:
    def __init__(self, id, type) -> None:
        self.id = id
        self.type = type
        self.code = ""
        self.name = getScriptName(type, id)
        
        self.code += f"__pulp:newScript(\"{self.name}\")"
        
        if istoken(self.name):
            self.code += self.name + f" = __pulp:getScript(\"{self.name}\")"
        
    
    def addEvent(self, key, blocks, blockidx):
        ctx.blocks = blocks
        self.code += "\n\n" + transpile_event(self.name, key, ctx, blockidx)

for pulpscript in pulp["scripts"]:
    script = Script(pulpscript["id"], pulpscript["type"])
    for key in pulpscript["data"]:
        if not key.startswith("__"):
            assert pulpscript["data"][key][0] == "block"
            blockidx = pulpscript["data"][key][1]
            script.addEvent(key, pulpscript["data"]["__blocks"], blockidx)
    code += script.code
    LuaOut.scripts.append(script)

print(code)

for error in list(set(ctx.errors)):
    print("--" + str(error))
print("--" + str(pulp.keys()))