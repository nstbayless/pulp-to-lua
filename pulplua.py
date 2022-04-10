from enum import unique
import json
import sys
import os
import shutil
from store import LuaOut as LuaOut
from pulpscript import transpile_event, PulpScriptContext, istoken
from PIL import Image

if len(sys.argv) >= 2:
    file = sys.argv[1]
else:
    print("usage: python3 " + sys.argv[0] + " pulp.json [out/]")
    exit(1)
    
outpath = "out"
if len(sys.argv) >= 3:
    outpath = sys.argv[2]

with open(file) as f:
    pulp = json.load(f)

playerid = pulp["player"]["id"]
startroom = pulp["player"]["room"]

ctx = PulpScriptContext()

def startcode():
    code = "___pulp = {\n" \
        + f"  playerid = {playerid},\n" \
        + f"  startroom = {startroom},\n" \
        + f"  startx = {pulp['player']['x']},\n" \
        + f"  starty = {pulp['player']['y']},\n" \
        + f"  gamename = \"{pulp['name']}\"\n," \
        + f"  tile_img = playdate.graphics.imagetable.new(\"tiles\")\n" \
    + "}\n"
    code += "local __pulp <const> = ___pulp\n"
    code += "import \"pulp\""
    code += "local __sin <const> = math.sin\n"
    code += "local __cos <const> = math.cos\n"
    code += "local __tan <const> = math.tan\n"
    code += "local __floor <const> = math.floor\n"
    code += "local __ceil <const> = math.ceil\n"
    code += "local __round <const> = function(x) return math.ceil(x + 0.5) end\n"
    code += "local __random <const> = math.random\n"
    return code
    
def endcode():
    code = "\n__pulp:load()\n"
    code += "__pulp:start()\n"
    return code
    
# images (tiles)
uniqueimagehashmap = dict()
uniqueimagelist = []
tileimages = []
for frame in pulp["frames"]:
    if frame: #some of these are false? why..?
        h = hash(tuple(frame["data"]))
        if h not in uniqueimagehashmap:
            uniqueimagehashmap[h] = len(uniqueimagelist)
            tileimages.append(len(uniqueimagelist))
            uniqueimagelist.append(frame["data"])
        else:
            tileimages.append(uniqueimagehashmap[h])
    else:
        # TODO: what does 'false' actually mean..?
        tileimages.append(0)
            
frame_img = Image.new("1", (8, 8 * len(uniqueimagelist)))
y = 0
print("writing image data...")
for data in uniqueimagelist:
    i = 0
    for p in data:
        assert p == 0 or p == 1
        frame_img.putpixel((i % 8, y + i // 8), 1 - (p%2))
        i += 1
    y += 8
print("done.")
# scripts

def getScriptName(type, id):
    if type == 0 and id == 0:
        return "game"
    elif type == 1 and id < len(pulp["rooms"]):
        return pulp["rooms"][id]["name"]
    elif type == 2 and id < len(pulp["tiles"]):
        return pulp["tiles"][id]["name"]
    
    ctx.errors += [f"unknown script, type {type}, id {id}"]
    return f"__UNKNOWN_SCRIPT_{type}_{id}"

scripttypes = ["global", "room", "tile"]

class Script:
    def __init__(self, id, type) -> None:
        self.id = id
        self.type = type
        self.code = ""
        self.name = getScriptName(type, id)
        
        self.code += f"\n----------------- {self.name} ----------------------------\n"
        self.code += f"__pulp:newScript(\"{self.name}\")"
        
        if istoken(self.name):
            self.code += "\n" + self.name + f" = __pulp:getScript(\"{self.name}\")"
        
        self.code += f"__pulp:associateScript(\"{self.name}\", \"{scripttypes[self.type]}\", {self.id})"
        
        self.code += "\n"
    
    def addEvent(self, key, blocks, blockidx):
        ctx.blocks = blocks
        self.code += "\n" + transpile_event(self.name, key, ctx, blockidx)

code = startcode()

# images
tile_id = 0

code += "\n__pulp.tiles = {}\n"
for tile in pulp["tiles"]:
    code += f"__pulp.tiles[{tile['id']}] = " + "{\n"
    code += f"    id = {tile['id']},\n"
    code += f"    fps = {tile['fps']},\n"
    code += f"    name = \"{tile['name']}\",\n"
    code += f"    type = {tile['type']},\n"
    code += f"    btype = {tile['btype']},\n"
    code += f"    solid = {tile['solid']},\n".lower()
    code += "    frames = {\n"
    for frame in tile["frames"]:
        code += f"      {tileimages[frame]+1},\n"
    code += "    nil}\n"
    code += "  }\n"

# rooms
code += "\n__pulp.rooms = {}"
for room in pulp["rooms"]:
    code += f"__pulp.rooms[{room['id']}] = " + "{\n"
    code += f"  id = {room['id']},\n"
    code += f"  name = \"{room['name']}\",\n"
    code += f"  song = {room['song']},\n"
    code += "  tiles = {\n"
    for tile in room["tiles"]:
        code += f"    {tile},\n"
    code += "  nil}\n"
    # TODO: exits
    code += "}\n"

for pulpscript in pulp["scripts"]:
    script = Script(pulpscript["id"], pulpscript["type"])
    for key in pulpscript["data"]:
        if not key.startswith("__"):
            assert pulpscript["data"][key][0] == "block"
            blockidx = pulpscript["data"][key][1]
            script.addEvent(key, pulpscript["data"]["__blocks"], blockidx)
    code += script.code
    LuaOut.scripts.append(script)

code += "\n"
vars = list(ctx.vars)
vars.sort()
for var in vars:
    if istoken(var) and "." not in var:
        code += f"{var} = 0\n"
code += "\n"
code += endcode()

for error in list(set(ctx.errors)):
    print("--" + str(error))

# output
if not os.path.isdir(outpath):
    os.mkdir(outpath)
with open(os.path.join(outpath, "main.lua"), "w") as f:
    f.write(code)
shutil.copy("pulp.lua", outpath)
frame_img.save(os.path.join(outpath, "tiles-table-8-8.png"))
print(f"files written to {outpath}")