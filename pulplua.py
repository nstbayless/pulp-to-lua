from enum import unique
import json
import sys
import os
import shutil
from tkinter import font
from store import LuaOut as LuaOut
from pulpscript import transpile_event, PulpScriptContext, istoken, tile_ids, escape_string
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

scripttypes = ["global", "room", "tile"]
tiletypes = ["world", "player", "sprite", "item", "exit"]

playerid = pulp["player"]["id"]
startroom = pulp["player"]["room"]
halfwidth = pulp["font"]["type"] != 1

ctx = PulpScriptContext()

def startcode():
    code = "___pulp = {\n" \
        + f"  playerid = {playerid},\n" \
        + f"  startroom = {startroom},\n" \
        + f"  startx = {pulp['player']['x']},\n" \
        + f"  starty = {pulp['player']['y']},\n" \
        + f"  gamename = \"{pulp['name']}\",\n" \
        + f"  halfwidth = {str(halfwidth).lower()},\n" \
        + f"  pipe_img = playdate.graphics.imagetable.new(\"pipe\"),\n" \
        + f"  font_img = playdate.graphics.imagetable.new(\"font\"),\n" \
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
    code += "local __tau <const> = math.pi * 2\n"
    code += "local __tostring <const> = tostring\n"
    code += "local __roomtiles <const> = __pulp.roomtiles\n"
    return code
    
def endcode():
    code = "\n__pulp:load()\n"
    code += "__pulp:start()\n"
    return code
    
def write_data_to_image(img, y, data, hasalpha=False):
    i = 0
    for p in data:
        assert p == 0 or p == 1 or (hasalpha and (p == 2 or p == 3)), f"pixel is {p}"
        if i % 8 < img.width:
            img.putpixel(
                (i % 8, y + i // 8),
                (0xff * (1 - p%2), 0 if p >= 2 else 0xff) if hasalpha else (1 - (p%2))
            )
        i += 1
    
# images (font, borders)
borderimage = Image.new("1", (8, 8 * len(pulp["font"]["pipe"])))
fontimage = Image.new("1", (8, 8 * len(pulp["font"]["chars"])))

y = 0
for data in pulp["font"]["pipe"]:
    write_data_to_image(borderimage, y, data)
    y += 8

y = 0
for data in pulp["font"]["chars"]:
    write_data_to_image(fontimage, y, data)
    y += 8
    
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

hasalpha = False
for data in uniqueimagelist:
    if 2 in data or 3 in data:
        hasalpha = True
        break
frame_img = Image.new("LA" if hasalpha else "1", (8, 8 * len(uniqueimagelist)))
y = 0
print("writing image data...")
for data in uniqueimagelist:
    write_data_to_image(frame_img, y, data, hasalpha)
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

# tiles
tile_id = 0

code += "\n__pulp.tiles = {}\n"
for tile in pulp["tiles"]:
    if tile:
        tile_ids[tile['name']] = tile['id']
        code += f"__pulp.tiles[{tile['id']}] = " + "{\n"
        code += f"    id = {tile['id']},\n"
        code += f"    fps = {tile['fps']},\n"
        code += f"    name = \"{tile['name']}\",\n"
        code += f"    type = {tile['type']},\n"
        code += f"    btype = {tile['btype']},\n" # behaviour type?
        code += f"    solid = {tile['solid']},\n".lower()
        if "says" in tile:
            code += f"    says = \"{escape_string(tile['says'])}\","
        code += "    frames = {\n"
        for frame in tile["frames"]:
            code += f"      {tileimages[frame]+1},\n"
        code += "    nil}\n"
        code += "  }\n"

def clamp(x, a, b):
    return min(max(x, a), b)

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
    code += "  nil},\n"
    code += "  exits = {\n"
    for exit in room["exits"]:
        code += "    {\n"
        code += f"      x = {exit['x']},\n"
        code += f"      y = {exit['y']},\n"
        #code += f"      id = {exit['id']},\n"
        if "tx" in exit:
            code += f"      tx = {clamp(exit['tx'], 0,24)},\n"
        if "ty" in exit:
            code += f"      ty = {clamp(exit['ty'], 0, 14)},\n"
        if "edge" in exit:
            code += f"      edge = {exit['edge']},\n"
        if "fin" in exit:
            code += f"      fin = {exit['fin']},\n"
        code += f"      room = {exit['room']}\n"
        code += "    },\n"
    code += "  nil},\n"
    code += "}\n"

for pulpscript in pulp["scripts"]:
    script = Script(pulpscript["id"], pulpscript["type"])
    if "data" in pulpscript:
        for key in pulpscript["data"]:
            if not key.startswith("__"):
                assert pulpscript["data"][key][0] == "block"
                blockidx = pulpscript["data"][key][1]
                script.addEvent(key, pulpscript["data"]["__blocks"], blockidx)
    code += script.code
    LuaOut.scripts.append(script)

if len(ctx.full_mimics) > 0:
    code += "\n-- full mimics\n"
    code += "for _=1,5 do\n"
    for full_mimic in ctx.full_mimics:
        evobj = full_mimic[0]
        evname = full_mimic[1]
        evtarg = full_mimic[2]
        if evname != "any":
            code += f"__pulp:getScript(\"{evobj}\")[\"{evname}\"]" \
                + f" = __pulp:getScript(\"{evtarg}\")[\"{evname}\"] or " \
                + f"__pulp:getScript(\"{evtarg}\").any\n"
        else:
            code += f"""
for name, fn in pairs(__pulp:getScript(\"{evtarg}\")) do
    if not __pulp:getScript(\"{evobj}\")[name] and type(fn) == "function" then
        __pulp:getScript(\"{evobj}\")[name] = fn
    end
end
"""
    code += "end\n"

code += "\n"
vars = list(ctx.vars)
vars.sort(key=lambda var: -ctx.var_usage[var])
varcode = ""
LOCVARMAX = 160 # chosen rather arbitrarily. 200 is too high though; it won't compile.
locvars = []
i = 0
for var in vars:
    assert not var.startswith("__"), "variables cannot start with __."
    if istoken(var) and "." not in var:
        if i < LOCVARMAX:
            # TODO: optimize local variables by usage
            varcode += "local "
            i += 1
            locvars.append(var)
        varcode += f"{var} = 0\n"
code = varcode + "\n" + code
code += endcode()

code += "local __LOCVARSET = {\n"
for var in locvars:
    code += f"  [\"{var}\"] = function(__{var}) {var} = __{var} end,\n"
code += "nil}\n"
code += "local __LOCVARGET = {\n"
for var in locvars:
    code += f"  [\"{var}\"] = function() return {var} end,\n"
code += "nil}\n"
code += "function __pulp.setvariable(varname, value)\n"
code += "  if varname:find(\"__\") then varname = \"__\" .. varname end -- prevent namespace conflicts with builtins\n"
code += "  local __varsetter = __LOCVARSET[varname]\n"
code += "  if __varsetter then __varsetter(value) else _G[varname] = value end\n"
code += "end\n"
code += "function __pulp.getvariable(varname)\n"
code += "  if varname:find(\"__\") then varname = \"__\" .. varname end -- prevent namespace conflicts with builtins\n"
code += "  local __vargetter = __LOCVARGET[varname]\n"
code += "  if __vargetter then return __vargetter() else return _G[varname] end\n"
code += "end\n"

for error in list(set(ctx.errors)):
    print("--" + str(error))

# output
if not os.path.isdir(outpath):
    os.mkdir(outpath)
with open(os.path.join(outpath, "main.lua"), "w") as f:
    f.write(code)
shutil.copy("pulp.lua", outpath)
frame_img.save(os.path.join(outpath, "tiles-table-8-8.png"))
borderimage.save(os.path.join(outpath, "pipe-table-8-8.png"))
fontimage.save(os.path.join(outpath, "font-table-8-8.png"))
print(f"files written to {outpath}")