import json
import sys
import os
import shutil
from store import LuaOut as LuaOut
from pulpscript import transpile_event, PulpScriptContext, istoken, tile_ids, escape_string

try:
    from PIL import Image
except:
    print("ERROR. Failed to open module PIL. You may need to install PIL or Pillow.")
    print("PIL is a python image manipulation library. It is required to produce the tile images for pulp.")
    print("You can install it via the command line.")
    print("Do this:")
    print()
    print("  python3 -m pip install Pillow")
    exit(1)

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

ROOMW = 25
ROOMH = 15

ctx = PulpScriptContext()

def startcode():
    code = """-- tweak sound engine to sound as it does on firefox.
-- set this to false to make the sound engine sound as it does on pdx export.
local FIREFOX_SOUND_COMPAT = true

-- set random seed
math.randomseed(playdate.getSecondsSinceEpoch())

-- pulp options (must be set before `import "pulp"`)
"""
    code += "___pulp = {\n" \
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
    code += "import \"pulp\"\n"
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
    code += "local __print <const> = print\n"
    code += "local __getTime <const> = playdate.getTime\n"
    code += "local __getSecondsSinceEpoch <const> = playdate.getSecondsSinceEpoch\n"
    code += """local __fillrect <const> = playdate.graphics.fillRect
local __setcolour <const> = playdate.graphics.setColor
local __fillcolours <const> = {
    black = playdate.graphics.kColorBlack,
    white = playdate.graphics.kColorWhite
}
local __pix8scale = __pulp.pix8scale
local __script <const> = {}
"""
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

def getScriptNameBase(type, id):
    if type == 0 and id == 0:
        return "game"
    elif type == 1 and id < len(pulp["rooms"]):
        return pulp["rooms"][id]["name"]
    elif type == 2 and id < len(pulp["tiles"]):
        return pulp["tiles"][id]["name"]
    
    ctx.errors += [f"unknown script, type {type}, id {id}"]
    return f"__UNKNOWN_SCRIPT_{type}_{id}"
    
scriptnames = set()
def getScriptName(type, id):
    s = getScriptNameBase(type, id)
    
    #ensure unique
    while s in scriptnames:
        s = f"_{type}_{id}_{s}"
    scriptnames.add(s)
    return s

evobjid = 1

class Script:
    def __init__(self, id, type) -> None:
        global evobjid
        self.id = id
        self.type = type
        self.code = ""
        self.name = getScriptName(type, id)
        self.evobjid = f"__script[{evobjid}]"
        evobjid += 1
        
        self.code += f"\n----------------- {self.name} ----------------------------\n\n"
        self.code += f"__pulp:newScript(\"{self.name}\")\n"
        self.code += f"{self.evobjid} = __pulp:getScript(\"{self.name}\")\n"
        self.code += f"__pulp:associateScript(\"{self.name}\", \"{scripttypes[self.type]}\", {self.id})"
        
        self.code += "\n"
        
        self.evnames = set()
    
    def addEvent(self, key, blocks, blockidx, commentsblockidx):
        ctx.blocks = blocks
        self.code += "\n" + transpile_event(self.name, key, ctx, blockidx, self.evobjid, commentsblockidx, self.evnames)
    
    def markHasEvent(self, evname):
        self.evnames.add(evname)

code = startcode()

# tiles
tile_id = 0

code += "\n__pulp.tiles = {}\n"
for tile in pulp["tiles"]:
    if tile:
        if type(tile) == bool or tile is None:
            print("WARNING: peculiar entry in tiles table. Expected JSON object.")
            continue
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
        code += "    frames = {"
        for frame in tile["frames"]:
            code += f"{tileimages[frame]+1},"
        code += " }\n"
        code += "  }\n"

def clamp(x, a, b):
    return min(max(x, a), b)

# rooms
code += "\n__pulp.rooms = {}\n"
j = -1
for room in pulp["rooms"]:
    j += 1
    if type(room) == bool or room is None:
        print(f"WARNING: peculiar entry in room table at index {j}. Expected JSON object.")
        continue
    code += f"__pulp.rooms[{room['id']}] = " + "{\n"
    code += f"  id = {room['id']},\n"
    code += f"  name = \"{room['name']}\",\n"
    code += f"  song = {room['song']},\n"
    code += "  tiles = {"
    i = 0
    for tile in room["tiles"]:
        if i % 25 == 0:
            code += "\n    "
        code += f"{tile:4},"
        i += 1
    code += " },\n"
    code += "  exits = {\n"
    for exit in room["exits"]:
        code += "    {\n"
        code += f"      x = {clamp(exit['x'], 0, ROOMW)},\n"
        code += f"      y = {clamp(exit['y'], 0, ROOMH)},\n"
        #code += f"      id = {exit['id']},\n"
        if "tx" in exit:
            code += f"      tx = {exit['tx']},\n"
        if "ty" in exit:
            code += f"      ty = {exit['ty']},\n"
        if "edge" in exit:
            code += f"      edge = {exit['edge']},\n"
        if "fin" in exit:
            code += f"      fin = [[{exit['fin']}]],\n"
        if "room" in exit:
            code += f"      room = {exit['room']},\n"
        code += "    nil},\n"
    code += "  nil},\n"
    code += "}\n"
    
# sounds
j = -1
code += "\n__pulp.sounds = {}\n"
for sound in pulp["sounds"]:
    j += 1
    if type(sound) != dict or sound is None:
        print(f"WARNING: peculiar entry in sounds table at index {j}. Expected JSON object.")
        code += f"__pulp.sounds[{j}] = " + "{}\n"
        continue
    code += f"__pulp.sounds[{sound['id']}] = " + "{\n"
    code += f"  bpm = {sound['bpm']},\n"
    code += f"  name = \"{sound['name']}\",\n"
    code += f"  type = {sound['type']},\n"
    if 'notes' in sound:
        code += "  notes = {"
        for note in sound['notes']:
            code += f"{note}, "
        code += "},\n"
    if 'ticks' in sound:
        code += f"  ticks = {sound['ticks']},\n"
    if 'envelope' in sound:
        if 'decay' in sound['envelope']:
            code += f"  decay = {sound['envelope']['decay']},\n"
        if 'attack' in sound['envelope']:
            code += f"  attack = {sound['envelope']['attack']},\n"
        if 'release' in sound['envelope']:
            code += f"  release = {sound['envelope']['release']},\n"
        if 'volume' in sound['envelope']:
            code += f"  volume = {sound['envelope']['volume']},\n"
        if 'sustain' in sound['envelope']:
            code += f"  sustain = {sound['envelope']['sustain']},\n"
    code += "}\n"

#songs    
code += "\n__pulp.songs = {}\n"
j = -1
for song in pulp["songs"]:
    j += 1
    if type(song) == bool or song is None:
        print(f"WARNING: peculiar entry in songs table at index {j}. Expected JSON object.")
        continue
    code += f"__pulp.songs[#__pulp.songs + 1] = " + "{\n"
    code += f"  bpm = {song['bpm']},\n"
    code += f"  id = {song['id']},\n"
    code += f"  name = \"{song['name']}\",\n"
    code += f"  ticks = {song['ticks']},\n"
    code += "  notes = {\n"
    for track in song["notes"]:
        code += "    {"
        i = 0
        for note in track:
            code += f"{note}, "
            if i % 100 == 99:
                code += "\n"
            i += 1
        code += "},\n"
    code += "  },\n"
    if 'voices' in song:
        code += "  voices = {\n"
        for voice in song['voices']:
            if voice:
                code += "    {\n"
                if 'attack' in voice:
                    code += f"       attack = {voice['attack']},\n"
                if 'decay' in voice:
                    code += f"       decay = {voice['decay']},\n"
                if 'volume' in voice:
                    code += f"       volume = {voice['volume']},\n"
                if 'release' in voice:
                    code += f"       {voice['release']},\n"
                if 'sustain' in voice:
                    code += f"       {voice['sustain']},\n"
                code += "    },\n"
            else:
                code += "    {},\n"
        code += "  },\n"
    if "loopFrom" in song:
        code += f"  loopFrom = {song['loopFrom']}\n,"
    code += "}\n"

#scripts
for pulpscript in pulp["scripts"]:
    if type(pulpscript) == bool:
        print("WARNING: boolean entry in script table. Expected JSON object.")
        continue
    script = Script(pulpscript["id"], pulpscript["type"])
    if "data" in pulpscript:
        for _pass in [0, 1]:
            for key in pulpscript["data"]:
                if not key.startswith("__"):
                    assert pulpscript["data"][key][0] == "block"
                    blockidx = pulpscript["data"][key][1]
                    if _pass == 0:
                        script.markHasEvent(key)
                    elif _pass == 1:
                        script.addEvent(key, pulpscript["data"]["__blocks"], blockidx, pulpscript["data"]["__comments"])
    code += script.code
    LuaOut.scripts.append(script)

# breaks mimics actually...
if False and len(ctx.full_mimics) > 0:
    code += "\n-- full mimics\n"
    code += "\n-- this loop is optional, but it can improve performance by cutting corners on mimic calls\n"
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
for name, fn in pairs(__pulp:getScript(\"{evtarg}\")) do -- (for 'any')
    if not __pulp:getScript(\"{evobj}\")[name] and type(fn) == "function" then
        __pulp:getScript(\"{evobj}\")[name] = fn
    end
end
"""
    code += "end\n"

code += "\n"
vars = sorted(list(ctx.vars))
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
code += "function __pulp.resetvars()\n"
for var in vars:
    code += f"  {var} = 0\n"
code += "end\n"

code += endcode()

for error in list(set(ctx.errors)):
    print("--" + str(error))

# output
if not os.path.isdir(outpath):
    os.mkdir(outpath)
with open(os.path.join(outpath, "main.lua"), "w") as f:
    f.write(code)
shutil.copy("pulp.lua", outpath)
shutil.copy("pulp-audio.lua", outpath)
frame_img.save(os.path.join(outpath, "tiles-table-8-8.png"))
borderimage.save(os.path.join(outpath, "pipe-table-8-8.png"))
fontimage.save(os.path.join(outpath, "font-table-8-8.png"))
print(f"files written to {outpath}")

# create path for launcher assets
launcher_path = "launcher/"
if not os.path.isdir(os.path.join(outpath,launcher_path)):
    os.mkdir(os.path.join(outpath, launcher_path))

# create pdxinfo file
with open(os.path.join(outpath, "pdxinfo"), "w") as f:
    f.write("name=" + pulp["name"] + str('\n'))
    f.write("author=" + pulp["author"] + str('\n'))
    f.write("description=" + pulp["intro"] + str('\n'))
    f.write("bundleID=" + "game.pulp." + \
        pulp["author"].replace(" ","").replace(".", "") + "." + \
        pulp["name"].replace(" ","").replace(".", "") + \
        str('\n'))
    f.write("version=" + str(pulp["version"]) + str('\n'))
    f.write("buildNumber=123\n")
    f.write("imagePath=" + launcher_path + "\n")
    f.write("launchSoundPath=" + launcher_path + "\n")
print(f"pdxinfo saved to {outpath}")

# generates launcher card from Pulpscript JSON and tilesheet
def generate_launcher_card(pulp_json, tilesheet):
    print("Generating launcher card...")
    
    # initialize launcher image
    launcher_image = Image.new("1", (200, 120)) # create image sized to pulp resolution
    
    # locate launcher card info in pulp json can be found in the n-th element of the "rooms" array, where n is the value specified in the "card" key	 
    print(f"launcher card room name: {pulp_json['rooms'][pulp_json['card']]['name']}")
    launcher_card_tiles = pulp_json["rooms"][pulp_json["card"]]["tiles"]
    
    # populate launcher card image with tiles
    tile_counter = 0
    for y in range(15):
        for x in range(25):
            # get tile # from launcher_card_json
            tile_num = launcher_card_tiles[tile_counter]
          
            # get first frame of specified tile
            frame_number = pulp_json["tiles"][tile_num]["frames"][0]
            
            # get the number of the unique image list (necessary since the code is removing duplicate tiles from the tiles list)
            h = hash(tuple( pulp_json["frames"][frame_number]["data"] ))
            image_map_number = uniqueimagehashmap[h]      
            
            # get tile from tilesheet
            tile = tilesheet.crop((0, image_map_number * 8, 8, image_map_number * 8 + 8)) # (left, upper, right, lower)
            
            # add tile to launcher card image at (x,y)
            launcher_image.paste(im=tile, box=(x*8, y*8))
            
            tile_counter+=1
    
    
    # NOTE: The card image at this point is 200 X 120 which is Pulp's full-screen resolution
    
    # resize image from Pulp's resolution (200 x 120) to standard Playdate resolution then crop to 350 x 155
    resized_card = launcher_image.resize((400, 240))    
    cropped_card = resized_card.crop((25, 42, 375, 197))

    # save launcher image to  file
    launcher_card_path = os.path.join(outpath, launcher_path, "card.png")    
    cropped_card.save( launcher_card_path, "PNG" )
    print(f"launcher card saved to {launcher_card_path}")
    

# generate launcher card
generate_launcher_card(pulp, frame_img)

print("build complete")
