assert(___pulp, "___pulp object must be defined before import")

import "CoreLibs/utilities/sampler"

local pulp <const> = ___pulp
local floor <const> = math.floor
local max <const> = math.max
pulp.scripts = {}
pulp.tiles = pulp.tiles or {}
pulp.tiles_by_name = {}
pulp.rooms_by_name = {}
pulp.roomtiles = {}
pulp.rooms = pulp.rooms or {}
pulp.gameScript = {}
pulp.game = {
    script = nil,
    name = nil,
    __tostring = function(...)
        return pulp.gamename
    end
}
pulp.player = {
    frame = 0,
    x = 0,
    y = 0,
}
pulp.invert = false
pulp.listen = true
pulp.shake = 0
pulp.hideplayer = false -- (resets to false every frame.)
pulp.roomQueued = nil
pulp.frame = 0
pulp.tilemap = playdate.graphics.tilemap.new()
pulp.game_is_loaded = false

local EMPTY <const> = {
    any = function (...) end
}

local ACTOR_TYPE_GLOBAL = 0
local ACTOR_TYPE_ROOM = 1
local ACTOR_TYPE_TILE = 2
local FPS = 40

local alphabet =
      " !\"#$%&'()*+,-./0123"
    .. "456789:;<=>?@ABCDEFG"
    .. "HIJKLMNOPQRSTUVWXYZ["
    .."\\]^_`abcdefghijklmno"
    .. "pqrstuvwxyz<|>~"

-- NOT local -- shared with pulpscript!
config = {
    autoAct = 1,
    inputRepeat=1,
    inputRepeatBetween=0.4,
    inputRepeatDelay=0.2,
    follow = 0,
    followCenterX=12,
    followCenterY=7,
    followOverflowTile = "black",
    allowDismissRootMenu = 0,
    sayAdvanceDelay = 0,
}

-- TODO: datetime

-- TODO: only start if accelerometer is used in this game.
playdate.startAccelerometer()
playdate.display.setRefreshRate(FPS)

local GRIDX, GRIDY = pulp.tile_img[1]:getSize()
if GRIDX == 8 then
    playdate.display.setScale(2)
end
if GRIDX == 4 then
    playdate.display.setScale(4)
end

local TILESW = 25
local TILESH = 15

pulp.tilemap:setImageTable(pulp.tile_img)
pulp.tilemap:setSize(TILESW, TILESH)
pulp.roomtiles = {}
for y = 0,TILESH-1 do
    pulp.roomtiles[y] = {}
end

local function copytable(t)
    local t2 = {}
    for k,v in pairs(t) do
       t2[k] = v
    end
    return t2
 end

local event_persist = {
    aa = 0,
    ra = playdate.getCrankPosition(),
    ax = 0,
    ay = 1,
    az = 0,
    dx = 0,
    dy = 0,
    orientation = "standing up"
}

function event_persist:new(name)
    return {
        aa = self.aa,
        ra = self.ra,
        ax = self.ax,
        ay = self.ay,
        az = self.az,
        room = self.room,
        orientation = self.orientation,
        __name = name
    }
end

function pulp:newScript(name)
    local script = {}
    pulp.scripts[name] = script
    return script
end

function pulp:associateScript(name, t, id)
    local script = type(name) == "string" and pulp.scripts[name] or name
    assert(script, "no script found with name '" .. tostring(name) .. "'")
    if t == "tile" then
        assert(pulp.tiles[id])
        pulp.tiles[id].script = script
    elseif t == "room" then
        assert(pulp.rooms[id], "unknown room id " .. tostring(id))
        pulp.rooms[id].script = script
    elseif t == "global" and id == 0 then
        pulp.gameScript = script
        pulp.game.script = script
    else
        assert(false)
    end
end

function pulp:getScriptEventByName(id, evname)
    local script = pulp:getScript(id) or EMPTY
    return script[evname] or script.any or function(...) end
end

function pulp:getScript(id)
    if type(id) == "string" then
        return pulp.scripts[id] or EMPTY
    elseif type(id) == "number" then
        return (pulp.tiles[id] or EMPTY).script or EMPTY
    elseif type(id) == "table" then
        return id
    else
        -- oops. :(
        assert(false)
        return {}
    end
end

function pulp:getCurrentRoom()
    return pulp.rooms[pulp.current_room_idx]
end

function pulp:getPlayerScript()
    return pulp.player.script
end

function pulp:getTile(tid)
    if type(tid) == "number" then
        return pulp.tiles[tid]
    else
        return pulp.tiles_by_name[tid]
    end
end

function pulp:getTileAt(x, y)
    return (pulp.roomtiles[y] or EMPTY)[x]
end

function playdate.cranked(change, acceleratedChange)
    local script = pulp:getPlayerScript()
    event_persist.aa = playdate.getCrankPosition()
    event_persist.da = change
    if script then
        local event = event_persist:new("crank");
        (script.crank or script.any)(script, pulp.player, event)
    end
end

function playdate.crankDocked()
    local script = pulp:getPlayerScript()
    if script then
        local event = event_persist:new("dock");
        (script.dock or script.any)(script, pulp.player, event)
    end
end

function playdate.crankUndocked()
    local script = pulp:getPlayerScript()
    if script then
        local event = event_persist:new("undock");
        (script.undock or script.any)(script, pulp.player, event)
    end
end

local function readAccelerometer()
    local ax, ay, az = playdate.readAccelerometer()
    event_persist.ax = ax
    event_persist.ay = ay
    event_persist.az = az
    event_persist.ax = event_persist.ax or 0
    event_persist.ay = event_persist.ay or 0
    event_persist.az = event_persist.az or 0
    if ay >= 0.70 then
        event_persist.orientation = "standing up"
    elseif ay <= -0.70 then
        event_persist.orientation = "upside down"
    elseif az >= 0.70 then
        event_persist.orientation = "on back"
    elseif az <= -0.70 then
        event_persist.orientation = "on front"
    elseif ax >= 0.70 then
        event_persist.orientation = "on right"
    elseif ax <= -0.70 then
        event_persist.orientation = "on left"
    else
        -- (hysteresis)
    end
end

local prev_a = false
local prev_b = false
local prev_up = false
local prev_down = false
local prev_left = false
local prev_right = false

local a_press_time = false
local b_press_time = false
local up_press_time = false
local down_press_time = false
local left_press_time = false
local right_press_time = false

local function readInput()
    local a = playdate.buttonIsPressed( playdate.kButtonA )
    local b = playdate.buttonIsPressed( playdate.kButtonA )
    local up = playdate.buttonIsPressed( playdate.kButtonUp )
    local down = playdate.buttonIsPressed( playdate.kButtonDown )
    local left = playdate.buttonIsPressed( playdate.kButtonLeft )
    local right = playdate.buttonIsPressed( playdate.kButtonRight )
    
    -- FIXME: ensure this is correct
    if up and down then
        up = false
        down = false
    end
    if left and right then
        left = false
        right = false
    end
    
    local a_pressed = a and not prev_a
    local b_pressed = b and not prev_b
    local up_pressed = up and not prev_up
    local down_pressed = down and not prev_down
    local left_pressed = left and not prev_left
    local right_pressed = right and not prev_right
    
    if config.inputRepeat then
        local now = playdate.getCurrentTimeMilliseconds()
        
        local next_first = now + config.inputRepeatDelay * 1000
        local next_repeat = now + config.inputRepeatBetween * 1000
        
        if a_pressed then
            a_press_time = next_first
        end
        if b_pressed then
            b_press_time = next_first
        end
        if up_pressed then
            up_press_time = next_first
        end
        if down_pressed then
            down_press_time = next_first
        end
        if left_pressed then
            left_press_time = next_first
        end
        if right_pressed then
            right_press_time = next_first
        end
        
        if a and a_press_time and now >= a_press_time  then
            a_press_time = next_repeat
            a_pressed = true
        end
        if b and b_press_time and now >= b_press_time  then
            b_press_time = next_repeat
            b_pressed = true
        end
        if up and up_press_time and now >= up_press_time  then
            up_press_time = next_repeat
            up_pressed = true
        end
        if down and down_press_time and now >= down_press_time  then
            down_press_time = next_repeat
            down_pressed = true
        end
        if left and left_press_time and now >= left_press_time  then
            left_press_time = next_repeat
            left_pressed = true
        end
        if right and right_press_time and now >= right_press_time  then
            right_press_time = next_repeat
            right_pressed = true
        end
    else
        a_press_time = false
        b_press_time = false
        up_press_time = false
        down_press_time = false
        left_press_time = false
        right_press_time = false
    end
    
    if up_pressed or down_pressed or left_pressed or right_pressed then
        event_persist.dx = 0
        event_persist.dy = 0
        if up_pressed then
            event_persist.dy = 1
        elseif down_pressed then
            event_persist.dy = -1
        elseif left_pressed then
            event_persist.dx = -1
        elseif right_pressed then
            event_persist.dx = 1
        end
    end
    
    -- TODO: perform actions with these inputs (e.g. move the player.)
    
    local playerScript = pulp:getPlayerScript()
    if playerScript then
        if a_pressed then
            local event = event_persist:new("confirm");
            (playerScript.confirm or playerScript.any)(playerScript, pulp.player, event)
        end
        if b_pressed then
            local event = event_persist:new("cancel");
            (playerScript.cancel or playerScript.any)(playerScript, pulp.player, event)
        end
        if (up_pressed or down_pressed or left_pressed or right_pressed) then
            local event = event_persist:new("update");
            (playerScript.confirm or playerScript.any)(playerScript, pulp.player, event)
        end
    end
    
    prev_a = a
    prev_b = b
    prev_up = up
    prev_down = down
    prev_left = left
    prev_right = right
end

local tileUpdateFrame <const> = function(tilei)
    if tilei.fps > 0 then
        tilei.frame = pulp.tile_fps_lookup_floor[tilei.fps_lookup_idx]
    else
        tilei.frame = floor(tilei.frame)
    end
end

function playdate.update()
    if not pulp.game_is_loaded then
        return
    end
    readAccelerometer()
    readInput()
    
    if pulp.roomQueued then
        pulp:exitRoom()
        
        pulp:enterRoom(pulp.roomQueued)
    end
    
    local event = event_persist:new("loop");
    (pulp.gameScript.loop or pulp.gameScript.any)(pulp.gameScript, nil, event)
    
    playdate.display.setInverted(pulp.invert)
    
    -- precompute tile indices by (frame rate, frame count)
    for fps, framecs in pairs(pulp.tile_fps_lookup) do
        local s = 1/fps
        for i, framec in pairs(framecs) do
            framecs[i] = framec + 1/fps
            if framecs[i] >= i then
                framecs[i] -= i
            end
            pulp.tile_fps_lookup_floor[pulp.tile_fps_lookup_floor_lookup[fps][i]] = floor(framecs[i])
        end
    end
    
    -- update tile frames and draw tiles
    for x = 0,TILESW-1 do
        for y = 0,TILESH-1 do
            local tilei = pulp.roomtiles[y][x]
            tileUpdateFrame(tilei)
            
            -- checks if changed
            local frame = tilei.tile.frames[tilei.frame + 1]
            if tilei.prev_frame ~= frame then
                tilei.prev_frame = frame
                pulp.tilemap:setTileAtPosition(x+1, y+1, frame)
            end
        end
    end
    
    -- draw all non-player tiles
    pulp.tilemap:draw(0, 0)
    
    -- update player frame
    local player = pulp.player
    tileUpdateFrame(player)
    
    local playerScript = pulp:getPlayerScript()
    
    if playerScript then
        local event = event_persist:new("draw");
        (playerScript.draw or playerScript.any)(playerScript, player, event)
    end
    
    if not pulp.hideplayer then
        local frame = player.tile.frames[floor(player.frame) % max(1, #player.tile.frames)]
        pulp.tile_img[frame]:draw(GRIDX * player.x, GRIDY * player.y)
    end
    pulp.hideplayer = false
    
    playdate.drawFPS()
    
    pulp.frame += 1
end

function pulp:load()
    event_persist.game = pulp.game
    pulp.game.name = pulp.gamename
    pulp.player.script = pulp:getScript(pulp.playerid) or {}
    assert(pulp.player.script)
    pulp.tile_fps_lookup = {}
    pulp.tile_fps_lookup_floor = {}
    pulp.tile_fps_lookup_floor_lookup = {}
    for i, tile in pairs(pulp.tiles) do
        pulp.tiles_by_name[tile.name] = tile
        if tile.fps > 0 then
            pulp.tile_fps_lookup_floor_lookup[tile.fps] = pulp.tile_fps_lookup_floor_lookup[tile.fps] or {}
            if not pulp.tile_fps_lookup_floor_lookup[tile.fps][#tile.frames] then
                local idx = #pulp.tile_fps_lookup_floor + 1
                pulp.tile_fps_lookup_floor[idx] = 0
                pulp.tile_fps_lookup_floor_lookup[tile.fps][#tile.frames] = idx
            end
            tile.fps_lookup_idx = pulp.tile_fps_lookup_floor_lookup[tile.fps][#tile.frames]
            pulp.tile_fps_lookup[tile.fps] = pulp.tile_fps_lookup[tile.fps] or {}
            pulp.tile_fps_lookup[tile.fps][#tile.frames] = 0
        end
    end
    for i, room in pairs(pulp.rooms) do
        room.type = ACTOR_TYPE_ROOM
        pulp.rooms_by_name[room.name] = room
        room.__tostring = function(...)
            return "0"
        end
    end
    local event = event_persist:new("load")
    for _, script in pairs(pulp.scripts) do
        script.any = script.any or function(...) end
        ;(script.load or script.any)(script, nil, event)
    end
    pulp.game_is_loaded = true
end

function pulp:exitRoom()
    local event = event_persist:new("exit")
    pulp:emit("exit", event)
end

function pulp:enterRoom(rid)
    local room_idx
    if type(rid) == "number" then
        room_idx = rid
    elseif type(rid) == "string" then
        room_idx = pulp.rooms_by_name[rid].id
    elseif type(rid) == "table" then
        room_idx = rid.id
    else
        assert(false, "unrecognized room " .. tostring(rid))
    end
    pulp.current_room_idx = room_idx
    pulp.roomQueued = nil
    local room = pulp.rooms[room_idx]
    assert(room, "no room for index " .. tostring(room_idx))
    event_persist.room = room
    
    -- set tiles
    for i, tid in ipairs(room.tiles) do
        local y = floor((i-1) / TILESW)
        local x = (i-1) % TILESW
        pulp.roomtiles[y][x] = {
            id = tid,
            type = ACTOR_TYPE_TILE,
            tile = pulp.tiles[tid],
            fps = pulp.tiles[tid].fps,
            fps_lookup_idx = pulp.tiles[tid].fps_lookup_idx,
            x = x,
            y = y,
            frame = 0
        }
    end
    
    if room.song == -2 then
        pulp.__fn_stop()
    elseif room.song >= 0 then
        pulp.__fn_loop(room.song)
    end
    
    if pulp.roomStart then
        -- 'start' event
        pulp.roomStart = false
        local event = event_persist:new("start")
        ;(game.start or game.any)(nil, event)
    end
    
    -- 'enter' event
    local event = event_persist:new("enter")
    pulp:emit("enter", event)
end

function pulp:start()
    pulp.player.x = pulp.startx
    pulp.player.y = pulp.starty
    pulp.player.tile = pulp.tiles[pulp.playerid]
    pulp.player.fps = pulp.player.tile.fps
    pulp.player.fps_lookup_idx = pulp.player.tile.fps_lookup_idx
    pulp.roomStart = true
    pulp:enterRoom(pulp.startroom)
end

function pulp:emit(evname, event)
    -- FIXME: what if evname starts with "__"?
    
    ;(pulp.gameScript[evname] or pulp.gameScript.any)(pulp.gameScript, nil, event)
    
    local roomScript = pulp:getCurrentRoom().script
    if roomScript then
        (roomScript[evname] or roomScript.any)(roomScript, pulp:getCurrentRoom(), event)
    end
    
    -- player
    local playerScript = pulp:getPlayerScript()
    if playerScript then
        (playerScript[evname] or playerScript.any)(playerScript, pulp.player, event)
    end
    
    -- tiles
    for x = 0,TILESW-1 do
        for y = 0,TILESH-1 do
            local tileInstance = pulp:getTileAt(x, y)
            if tileInstance.tile.script and tileInstance.tile.script[evname] then
                (tileInstance.tile.script[evname] or tileInstance.tile.script.any)(tileInstance.tile.script, tileInstance, event)
            end
        end
    end
end

function pulp:forTiles(tid, cb)
    for x = 0,TILESW-1 do
        for y = 0,TILESH-1 do
            local tilei = pulp.roomtiles[y][x]
            if tilei.id == tid or tid == nil or tilei.tile.name == tid then
                cb(x, y, tilei)
            end
        end
    end
end


-- EVENTS TODO:
-- update [player]
-- bump [player]
-- finish [game]
-- interact [sprite tile]
-- collect [item tile]
-- change [game]
-- select [game]
-- dismiss [game
-- invalid [game]

------- IMPERATIVE FUNCTIONS --------------------------------------------------

function pulp.__fn_stop(...)
    -- todo
end

function pulp.__fn_once(...)
    -- todo
end

function pulp.__fn_loop(...)
    -- todo
end

function pulp.__fn_bpm(...)
    -- todo
end

function pulp.__fn_sound(...)
    -- todo
end

function pulp.__fn_play(...)
    -- todo
end

function pulp.__fn_draw(...)
    -- todo
end

function pulp.__fn_label(...)
    -- todo
end

function pulp.__fn_fill(...)
    -- todo
end

function pulp.__fn_restore(...)
    -- todo
end

function pulp.__fn_store(...)
    -- todo
end

function pulp.__fn_toss(...)
    -- todo
end

function pulp.__fn_wait(...)
    -- todo
end

function pulp.__fn_say(...)
    -- todo
end

function pulp.__fn_ask(...)
    -- todo
end

function pulp.__fn_fin(...)
    -- todo
end

function pulp.__fn_act(...)
    -- todo
end

function pulp.__fn_dump(...)
    -- todo
end

function pulp.__fn_goto(actor, x, y, room)
    if x then
        player.x = x
    end
    if y then
        player.y = y
    end
    if room then
        pulp.roomQueued = actor
    end
end

function pulp.__fn_invert()
    pulp.invert = not pulp.invert
end

function pulp.__fn_log(x)
    print(x)
end

function pulp.__fn_ignore()
    pulp.listen = false
end

function pulp.__fn_listen()
    pulp.listen = true
end

function pulp.__fn_shake(x)
    pulp.shake = x
end

function pulp.__fn_hide(x)
    pulp.hideplayer = true
end

function pulp.__fn_tell(x, y, event, block, actor)
    if x and y then
        local tilei = (pulp.roomtiles[y] or EMPTY)[x]
        if tilei then
            block(tilei.script or EMPTY, tilei, event)
        end
    else
        if type(actor) == "string" or type(actor) == "number" then
            pulp:forTiles(actor, function(x, y, tilei)
                block(tilei.script or EMPTY, tilei, event)
            end)
        elseif type(actor) == "table" then
            block(actor.script or EMPTY, actor, event)
        else
            assert(false, "invalid tell target")
        end
    end
end

function pulp.__fn_swap(actor, newid)
    assert(newid)
    if actor and actor.tile then
        local newtile = pulp:getTile(newid)
        if newtile then
            actor.tile = newtile
            actor.id = actor.tile.id
            actor.fps = actor.tile.fps
            actor.fps_lookup_idx = actor.tile.fps_lookup_idx
        else
            print("cannot swap to tile " .. newid)
        end
    end
end

------- EXPRESSION FUNCTIONS --------------------------------------------------

-- tile embeds are encoded in 0x80+ bytes
-- first byte indicates number of bytes in encoding
-- subsequent bytes are 0x80 plus 7 bits of frame index, big-endian over bytes.
-- this might be different from pulp original.
function pulp.__ex_embed(tid)
    local frame = pulp:getTile(tid).frames[1] or 0
    
    local frame_bh = frame
    local bytes = { 0x80 }
    while frame_bh > 0 do
        bytes[1] += 1
        bytes[#bytes+1] = 0x80 + (frame_bh % 128)
        frame_bh = floor(frame_bh / 128)
    end

    local s = ""
    for _, byte in ipairs(bytes) do
        s = s .. string.char(byte)
    end
    return s
end

function pulp.__ex_lpad(value, width, symbol)
    symbol = symbol or " "
    value = tostring(value)
    while #value < width do
        value = symbol .. value
    end
    return value
end

function pulp.__ex_rpad(value, width, symbol)
    symbol = symbol or " "
    value = tostring(value)
    while #value < width do
        value = value .. symbol
    end
    return value
end

function pulp.__ex_name(actor)
    if actor then
        if actor.type == ACTOR_TYPE_TILE then
            return actor.tile.name or ""
        else
            -- UB!
            return actor.name or ""
        end
    else
        -- UB!
        return ""
    end
end

function pulp.__ex_invert()
    return pulp.invert and 1 or 0
end

function pulp.__ex_degrees(x)
    return x * 180 / math.pi
end

function pulp.__ex_radians(x)
    return x * math.pi / 180
end