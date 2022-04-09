assert(___pulp, "___pulp object must be defined before import")

local pulp <const> = ___pulp
pulp.scripts = {}
pulp.tiles = {}
pulp.roomtiles = {}
pulp.rooms = {}
pulp.gameScript = {}
pulp.player = {}
pulp.invert = false
pulp.listen = true
pulp.shake = 0
pulp.hideplayer = false -- (resets to false every frame.)

local ACTOR_TYPE_GLOBAL = 0
local ACTOR_TYPE_ROOM = 1
local ACTOR_TYPE_TILE = 2

local alphabet =
     " !\"#$%&'()*+,-./0123"
    + "456789:;<=>?@ABCDEFG"
    + "HIJKLMNOPQRSTUVWXYZ["
    +"\\]^_`abcdefghijklmno"
    + "pqrstuvwxyz<|>~"

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
playdate.setRefreshRate(20)

local TILESW = 25
local TILESH = 15

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
        orientation = self.orientation,
        __name = name
    }
end

function pulp:newScript(name)
    local script = {}
    pulp.scripts[name] = script
    return script
end

function pulp:associateScript(name, type, id)
    local script = pulp.scripts[name]
    assert(script)
    if type == "tile" then
        assert(pulp.tiles[id])
        pulp.tiles[id].script = script
    elseif type == "room" then
        assert(pulp.rooms[id])
        pulp.rooms[id].script = script
    elseif type == "global" and id == 0 then
        pulp.gameScript = script
    else
        assert(false)
    end
end

function pulp:getScript(id)
    if type(id) == "string" then
        return pulp.scripts[id] or {}
    elseif type(id) == "number" then
        return (pulp.tiles[id] or {}).script or {}
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

function pulp:getTileAt(x, y)
    return (pulp.roomtiles[y] or {})[x]
end

function playdate.cranked(change, acceleratedChange)
    local script = pulp:getPlayerScript()
    event_persist.aa = playdate.getCrankPosition()
    event_persist.da = change
    if script and (script.crank or script.any) then
        local event = event_persist:new("crank");
        (script.crank or script.any)(script, pulp.player, event)
    end
end

function playdate.crankDocked()
    local script = pulp:getPlayerScript()
    if script and (script.dock or script.any) then
        local event = event_persist:new("dock");
        (script.dock or script.any)(script, pulp.player, event)
    end
end

function playdate.crankUndocked()
    local script = pulp:getPlayerScript()
    if script and script.undock then
        local event = event_persist:new("undock");
        (script.undock or script.any)(script, pulp.player, event)
    end
end

local function readAccelerometer()
    event_persist.ax, event_persist.ay, event_persist.az = playdate.readAccelerometer()
    event_persist.ax = event_persist.ax or 0
    event_persist.ay = event_persist.ay or 0
    event_persist.az = event_persist.az or 0
    -- TODO: orientation string
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
    if a_pressed and (playerScript.confirm or playerScript.any) then
        local event = event_persist:new("confirm");
        (playerScript.confirm or playerScript.any)(playerScript, pulp.player, event)
    end
    if b_pressed and (playerScript.cancel or playerScript.any) then
        local event = event_persist:new("cancel");
        (playerScript.cancel or playerScript.any)(playerScript, pulp.player, event)
    end
    if (up_pressed or down_pressed or left_pressed or right_pressed) and (playerScript.confirm or playerScript.any) then
        local event = event_persist:new("update");
        (playerScript.confirm or playerScript.any)(playerScript, pulp.player, event)
    end
    
    prev_a = a
    prev_b = b
    prev_up = up
    prev_down = down
    prev_left = left
    prev_right = right
end

function playdate.update()
    readAccelerometer()
    readInput()
    if pulp.gameScript.loop or pulp.gameScript.any then
        local event = event_persist:new("loop");
        (pulp.gameScript or pulp.gameScript.any)(pulp.gameScript, nil, event)
    end
end

function pulp:load()
    pulp.current_room_idx = nil
    assert(pulp.current_room_idx, "starting room invalid")
    pulp.player.script = pulp:getScript(pulp.playerid)
    pulp.player.tile = pulp.tiles[pulp.playerid]
    for i, room in ipairs(pulp.rooms) do
        room.type = ACTOR_TYPE_ROOM
    end
    local event = event_persist:new("load")
    for _, script in pairs(pulp.scripts) do
        if (script.load or script.any) then
            (script.load or script.any)(script, nil, event)
        end
    end
end

function pulp:exitRoom()
    local event = event_persist:new("exit")
    pulp:emit("exit", event)
end

function pulp:enterRoom(room_idx)
    pulp.current_room_idx = room_idx
    local room = pulp.rooms[room_idx]
    assert(room, f"no room for index '{room_idx}'")
    
    -- set tiles
    for i, tid in ipairs(room.tiles) do
        local y = math.floor(i / TILESW)
        local x = i % TILESW
        pulp.roomtiles[y][x] = {
            id = tid,
            type = ACTOR_TYPE_TILE,
            tile = pulp.tiles[tid],
            x = x,
            y = y,
            frame = 0
        }
    end
    
    if room.song == -2 then
        pulp:__fn_stop()
    elseif room.song >= 0 then
        pulp:__fn_loop(room.song)
    end
    
    if pulp.roomStart then
        -- 'start' event
        pulp.roomStart = false
        local event = event_persist:new("start")
        if pulp.gameScript.start or pulp.gameScript.any then
            (game.start or game.any)(nil, event)
        end
    end
    
    -- 'enter' event
    local event = event_persist:new("enter")
    pulp:emit("enter", event)
    
    pulp.roomQueued = nil
end

function pulp:start()
    pulp.player = {
        x = pulp.startx,
        y = pulp.starty,
        tile = pulp.tiles[pulp.playerid]
    }
    pulp.roomStart = true
    pulp.enterRoom(pulp.startroom)
end

function pulp:emit(evname, event)
    -- FIXME: what if evname starts with "__"?
    
    if pulp.gameScript[evname] or pulp.gameScript.any then
        (pulp.gameScript[evname] or pulp.gameScript.any)(pulp.gameScript, nil, event)
    end
    
    local roomScript = pulp:getCurrentRoom().script
    if roomScript and (roomScript[evname] or roomScript.any) then
        (roomScript[evname] or roomScript.any)(roomScript, pulp:getCurrentRoom(), event)
    end
    
    -- player
    local playerScript = pulp:getPlayerScript()
    if playerScript and (playerScript[evname] or playerScript.any) then
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
-- FUNCTIONS TODO

-- draw
-- label
-- fill

-- restore
-- store
-- toss

-- goto

-- wait
-- say
-- ask
-- fin

-- loop
-- once
-- stop
-- bpm
-- sound

-- swap
-- tell
-- act

-- dump

function pulp:__fn_invert(kwargs)
    pulp.invert = not pulp.invert
end

function pulp:__fn_frame(kwargs, x)
    if kwargs.actor and kwargs.actor.type == ACTOR_TYPE_TILE then
        -- UB!
        -- this isn't really the correct behaviour but w/e
        kwargs.actor.frame = math.floor(x)
    end
end

function pulp:__fn_log(kwargs, x)
    print(x)
end

function pulp:__fn_ignore(kwargs)
    pulp.listen = false
end

function pulp:__fn_listen(kwargs)
    pulp.listen = true
end

function pulp:__fn_shake(kwargs, x)
    pulp.shake = x
end

function pulp:__fn_hide(kwargs, x)
    pulp.hideplayer = true
end

------- EXPRESSION FUNCTIONS --------------------------------------------------
-- EXPRESSION FUNCTIONS TODO
-- lpad
-- rpad

function pulp:__ex_name(kwargs)
    if kwargs.actor then
        if kwargs.actor.type == ACTOR_TYPE_TILE then
            return kwargs.actor.tile.name or ""
        else
            -- UB!
            return kwargs.actor.name or ""
        end
    else
        -- UB!
        return ""
    end
end

function pulp:__ex_frame(kwargs)
    if kwargs.actor and kwargs.actor.type == ACTOR_TYPE_ROOM then
        return kwargs.actor.frame
    else
        return 0
    end
end

function pulp:__ex_invert(kwargs)
    return pulp.invert
end

function pulp:__ex_degrees(kwargs, x)
    return x * 180 / math.pi
end

function pulp:__ex_radians(kwargs, x)
    return x * math.pi / 180
end