assert(___pulp, "___pulp object must be defined before import")

-- scale audio by this amount
-- (we need to declare this before importing pulp-audio)
SOUNDSCALE = {
    [0] = 0.320, -- sine
    [1] = 0.412, -- square
    [2] = 0.300, -- sawtooth
    [3] = 0.440, -- triangle
    [4] = 0.160  -- noise
}

import "CoreLibs/utilities/sampler"
import "pulp-audio.lua"

local pulp <const> = ___pulp
local floor <const> = math.floor
local ceil <const> = math.ceil
local max <const> = math.max
local min <const> = math.min
local substr <const> = string.sub
local random <const> = math.random
local string_char <const> = string.char
local string_byte <const> = string.byte
local abs <const> = math.abs

local TTYPE_WORLD <const> = 0
local TTYPE_PLAYER <const> = 1
local TTYPE_SPRITE <const> = 2
local TTYPE_ITEM <const> = 3
local ACTOR_TYPE_GLOBAL <const> = 0
local ACTOR_TYPE_ROOM <const> = 1
local ACTOR_TYPE_TILE <const> = 2
local __exits = {}

pulp.scripts = {}
pulp.tiles = pulp.tiles or {}
pulp.sounds = pulp.sounds or {}
pulp.tiles_by_name = {}
pulp.rooms_by_name = {}
pulp.sounds_by_name = {}
pulp.song_names_by_id = {}
pulp.roomtiles = {}
pulp.store = {}
pulp.store_dirty = false
local roomtiles = pulp.roomtiles
pulp.rooms = pulp.rooms or {}
pulp.game = {
    script = EMPTY,
    name = "",
    type = ACTOR_TYPE_GLOBAL,
    __tostring = function(...)
        return pulp.gamename
    end
}
pulp.player = {
    is_player = true,
    frame = 0,
    x = 0,
    y = 0,
    
    -- used if PTLE_SMOOTH_MOVEMENT_SPEED > 0
    smooth_x = 0,
    smooth_y = 0
}
pulp.invert = false
pulp.listen = true
pulp.shake = 0
pulp.hideplayer = false -- (resets to false every frame.)
pulp.roomQueued = nil
pulp.frame = 0
pulp.tilemap = playdate.graphics.tilemap.new()
local tilemap <const> = pulp.tilemap
pulp.game_is_loaded = false
pulp.timers = {}
pulp.shakex = 2
pulp.shakey = 2
pulp.exits = nil
pulp.message = nil
pulp.optattachmessage = nil
local disabled_exit_x = nil
local disabled_exit_y = nil

local pulp_tile_fps_lookup_floor = {}
local pulp_tile_fps_lookup_floor_lookup = {}

-- we scale down the sound to reduce saturation and match playback in Firefox
pulp.soundscale = SOUNDSCALE

local EMPTY <const> = {
    any = function (...) end
}
pulp.EMPTY = {
    any = EMPTY.any
}
pulp.EMPTY.script = pulp.EMPTY
pulp.gameScript = EMPTY

local FPS <const> = 20
local SPF <const> = 1/FPS

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
    inputRepeatBetween=0.2,
    inputRepeatDelay=0.4,
    follow = 0,
    followCenterX=12,
    followCenterY=7,
    followOverflowTile = 1,
    allowDismissRootMenu = 0,
    sayAdvanceDelay = 0.2,
    textSpeed = 20,
    _pulp_to_lua = pulp.tiles[1],
}

-- TODO: only start if accelerometer is used in this game.
playdate.startAccelerometer()
playdate.display.setRefreshRate(FPS)

local tile_img = pulp.tile_img
local font_img = pulp.font_img
local GRIDX <const>, GRIDY <const> = pulp.tile_img[1]:getSize()
if GRIDX == 8 then
    playdate.display.setScale(2)
end
if GRIDX == 4 then
    playdate.display.setScale(4)
end
if GRIDX == 2 then
    playdate.display.setScale(8)
end
if GRIDX == 1 then
    playdate.display.setScale(16)
end

local PIX8SCALE <const> = GRIDX / 8
pulp.gridx = GRIDX
pulp.gridy = GRIDY
pulp.pix8scale = PIX8SCALE

local HALFWIDTH_SRCRECT = nil
if pulp.halfwidth then
    HALFWIDTH_SRCRECT = playdate.geometry.rect.new(0, 0, GRIDX/2, GRIDY)
end

playdate.graphics.setBackgroundColor(playdate.graphics.kColorBlack)

local TILESW <const> = 25
local TILESH <const> = 15
local cropl = 0
local cropr = TILESW-1
local cropu = 0
local cropd = TILESH-1
local iscropped = false

tilemap:setImageTable(tile_img)
tilemap:setSize(TILESW, TILESH)
for y = 0,TILESH-1 do
    pulp.roomtiles[y] = {}
end

-- sounds
local SOUND_CHANNELS <const> = 5

local wavetypes <const> = {
    [0] = playdate.sound.kWaveSine,
    [1] = playdate.sound.kWaveSquare,
    [2] = playdate.sound.kWaveSawtooth,
    [3] = playdate.sound.kWaveTriangle,
    [4] = playdate.sound.kWaveNoise,
}

-- tweens x toward y by adding/subtracting at most c
local function tween(x, y, c)
    if abs(x - y) <= c then
        return y
    elseif x < y then
        return x + c
    else
        return x - c
    end
end

------------------------------------------------ API ---------------------------------------------------------

local function copytable(t)
    local t2 = {}
    for k,v in pairs(t) do
       t2[k] = v
    end
    return t2
end

local function trimLineEnd(s)
    return string.gsub(s, "%s*$", "")
end

-- input: a string, height and width
-- output: a list of strings, one for each 'page', each of which is word-wrapped to fit in  w-by-h rectangle (as rendered with pulp.__fn_label)

local function paginate(text, w, h)
    -- virtal cursor position
    local x = 0
    local y = 0
    
    -- return value
    local pages = {""}
    
    -- the index of the first character to include in this line.
    local startidx = 1
    
    -- the index of the first character in the currently-processing word (or startidx if larger)
    local wordidx = 1
    local wordx = 0
    
    -- skip this many characters
    local multichar = 0
    
    -- waiting to find start of word.
    local hook_word = true
    
    -- waiting to find start of line.
    local hook_line = true
    
    for i = 1,#text+1 do
        if i == #text+1 then
            -- finish with text[startidx:]
            pages[#pages] = pages[#pages] .. trimLineEnd(substr(text, startidx, #text))
        else
            if multichar > 0 then
                multichar -= 1
                goto continue
            end
            
            local char = substr(text, i, i)
            
            if char == '\f' then
                pages[#pages] = pages[#pages] .. trimLineEnd(substr(text, startidx, i - 1))
                pages[#pages+1] = ""
                x = 0
                y = 0
                startidx = i
                wordidx = i
                wordx = 0
                hook_line = true
                hook_word = true
            elseif char == '\n' then
                pages[#pages] = pages[#pages] .. trimLineEnd(substr(text, startidx, i - 1)) .. "\n"
                x = 0
                y += 1
                startidx = i
                wordidx = i
                wordx = 0
                hook_line = true
                hook_word = true
            else
                local chbyte = string_byte(text, i, i)
                local isspace = (char == ' ' or char == '\t')
                
                --[[print(
                    tostring(x) .. "/" .. tostring(w),
                    tostring(y) .. "/" .. tostring(h), char
                )]]
                
                if x >= w then
                    local cut_point = i
                    if wordidx > startidx then
                        cut_point = wordidx
                        x -= wordx - 1
                    else
                        x = 0
                    end
                    
                    local cutline = trimLineEnd(substr(text, startidx, cut_point - 1))
                    pages[#pages] = pages[#pages] .. cutline .. "\n"
                    startidx = cut_point
                    wordidx = cut_point
                    wordx = 0
                    y += 1
                    if y >= h then
                        y = 0
                        pages[#pages+1] = ""
                    end
                else
                    x += 1
                end
                
                if hook_line then
                    startidx = i
                end
                
                if hook_word then
                    wordidx = i
                    wordx = x
                end
                
                if not isspace then
                    hook_line = false
                    hook_word = false
                else
                    hook_word = true
                end
                
                -- read embeds
                if chbyte >= 0x80 then
                    multichar = chbyte - 0x80
                end
            end
            
            ::continue::
        end
    end
    
    -- remove empty final page
    if pages[#pages] == "" then
        pages[#pages] = nil
    end
    
    if #pages == 0 then
        pages[1] = ""
    end
    
    return pages
end

-- https://stackoverflow.com/q/49979017
local function getStackDepth()
    local depth = 0
    while true do
        if not debug.getinfo(3 + depth) then
            break
        end
        depth = depth + 1
    end
    return depth
end

-- slow, so don't call it except sometimes
local stackdepth = 0
local function preventStackOverflow()
    if stackdepth > 300 then
        print("WARNING: stack overflow detected.")
        return true
    end
    return false
end


local event_persist = {
    aa = playdate.getCrankPosition() or 0,
    ra = 0,
    ax = 0,
    ay = 1,
    az = 0,
    dx = 0,
    dy = 0,
    orientation = "standing up"
}

function event_persist:new()
    return {
        aa = self.aa,
        ra = self.ra,
        ax = self.ax,
        ay = self.ay,
        az = self.az,
        dx = self.dx,
        dy = self.dy,
        tx = self.tx,
        ty = self.ty,
        px = pulp.player.x,
        py = pulp.player.y,
        game = pulp.game,
        room = self.room,
        orientation = self.orientation,
        frame = pulp.frame
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
        assert(pulp.tiles[id], "script \"" .. name .. "\" for tile " .. tostring(id) .. ", but tile does not exist")
        pulp.tiles[id].script = script
    elseif t == "room" then
        assert(pulp.rooms[id], "associate room script with unknown room id " .. tostring(id))
        pulp.rooms[id].script = script
    elseif t == "global" and id == 0 then
        pulp.gameScript = script
        pulp.game.script = script
    else
        assert(false, "unrecognized script type " .. tostring(t))
    end
end

function pulp:getScriptEventByName(id, evname)
    local script = pulp:getScript(id) or EMPTY
    return script[evname] or script.any or EMPTY.any
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
    return pulp.player.script or EMPTY
end

function pulp:getTile(tid)
    if type(tid) == "number" then
        return pulp.tiles[tid]
    else
        return pulp.tiles_by_name[tid]
    end
end

function pulp:getSongName(sid)
    if type(sid) == "number" then
        return pulp.song_names_by_id[sid]
    else
        return sid
    end
end

function pulp:getSound(sid)
    if type(sid) == "number" then
        return pulp.sounds[sid]
    else
        return pulp.sounds_by_name[sid]
    end
end

function pulp:getTileAt(x, y)
    return (roomtiles[y] or EMPTY)[x]
end

local function default_event_interact(tilei, event, evname)
    if tilei.tile.says and #tilei.tile.says > 0 then
        pulp.__fn_say(nil, nil, nil, nil, tilei, event, evname, nil, tilei.tile.says)
    end
end

local function default_event_collect(tilei, event, evname)
    local says = tilei.tile.says
    pulp.setvariable(tilei.name .. "s", (pulp.getvariable(tilei.name .. "s") or 0) + 1)
    pulp.__fn_swap(tilei, 0)
    if says and #says > 0 then
        pulp.__fn_say(nil, nil, nil, nil, tilei, event, evname, nil, says)
    end
end

function playdate.cranked(change, acceleratedChange)
    local script = pulp:getPlayerScript()
    event_persist.aa = playdate.getCrankPosition()
    event_persist.ra = change
    if script then
        (script.crank or script.any)(pulp.player, event_persist:new(), "crank")
    end
end

function playdate.crankDocked()
    local script = pulp:getPlayerScript()
    if script then
        (script.dock or script.any)(pulp.player, event_persist:new(), "dock")
    end
end

function playdate.crankUndocked()
    local script = pulp:getPlayerScript()
    if script then
        (script.undock or script.any)(pulp.player, event_persist:new(), "undock")
    end
end

local function readAccelerometer()
    local ax, ay, az = playdate.readAccelerometer()
    if ax and ay and ay then
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

local function updateMessage(up, down, left, right, confirm, cancel)
    -- FIXME: yes, this is pretty messy.
    
    local message = pulp.message
    local text = (message.text or EMPTY)[message.page]
    -- TODO: crank can also dismiss 
    local skiptext = up or down or confirm or cancel or left or right
    
    if message.dismiss then
        pulp.message = pulp.message.previous
        return
    end
    
    if message.sayAdvanceDelay > 0 then
        message.sayAdvanceDelay -= SPF
    end
    
    if not message.showoptions and not message.text then
        if message.block then
            pulp.optattachmessage = message
            message.block(message.actor, message.event, message.evname)
            pulp.optattachmessage = nil
            message.showoptions = true
            message.optselect = 1
            if message.options and #message.options > 0 then
                pulp:emit("change", event_persist:new())
            end
        end
        if #message.options == 0 then
            -- dismiss menu
            print("warning: opened a menu with 0 valid options")
            pulp.message = pulp.message.previous
            return
        end
    end
    
    if message.showoptions then
        if message.sayAdvanceDelay > 0 then return end
        local prevoptsel = message.optselect
        if up then
            message.optselect -= 1
        elseif down then
            message.optselect += 1
        end
        if message.opth then
            if left and message.firstopt ~= 1 then
                message.firstopt -= message.opth
                message.optselect -= message.opth
            end
            if right and message.firstopt + message.opth <= #message.options then
                message.firstopt += message.opth
                message.optselect += message.opth
            end
            
            if message.firstopt <= 1 then
                message.firstopt = 1
            elseif message.firstopt > #message.options then
                message.firstopt -= message.opth
            end
        end
        
        if up or down then
            if message.opth then
                if message.optselect < message.firstopt then
                    message.optselect = message.firstopt + message.opth
                elseif message.optselect > message.firstopt + message.opth - 1 or message.optselect > #message.options then
                    message.optselect = message.firstopt
                end
            else
                if message.optselect < 1 then
                    message.optselect = #message.options
                elseif message.optselect > #message.options then
                    message.optselect = 1
                end
            end
        end
        
        if message.opth then
            message.optselect = max(min(message.optselect, message.firstopt + message.opth - 1), message.firstopt)
        end
        
        message.optselect = max(min(message.optselect, #message.options), 1) -- paranoia
        
        if prevoptsel ~= message.optselect then
            pulp:emit("change", event_persist:new())
        end
        
        if confirm then
            local option = message.options[message.optselect]
            
            -- dismiss message
            if option and option.block then
                assert(option.event)
                option.block(option.actor, option.event, option.evname, option)
                
                -- dismiss ALL menus if no submenu opened in option block
                if pulp.message == message then
                    pulp.message = nil
                elseif pulp.message.text then
                    message.dismiss = true
                end
                
                (pulp.gameScript.select or pulp.gameScript.any)(pulp.game, event_persist:new(), "select")
            end
        elseif cancel then
            if pulp.message.previous or config.allowDismissRootMenu ~= 0 then
                pulp.message = pulp.message.previous
                ;(pulp.gameScript.select or pulp.gameScript.any)(pulp.game, event_persist:new(), "dismiss")
            else
                (pulp.gameScript.select or pulp.gameScript.any)(pulp.game, event_persist:new(), "invalid")
            end
        end
    elseif message.textidx < #text and skiptext and message.sayAdvanceDelay <= 0 then
        message.textidx = #text
    elseif message.textidx < #text then
        message.textidx += (message.textSpeed or FPS) / FPS
        if message.textidx >= #text then
            message.textids = #text
        end
    elseif skiptext and message.sayAdvanceDelay <= 0 then
        -- proceed to next page or close if last page.
        
        if message.page == #message.text then
            -- close the final page.
            if message.block then
                pulp.optattachmessage = message
                message.block(message.actor, message.event, message.evname)
                pulp.optattachmessage = nil
                message.block = nil
            end
            
            if message.options and #message.options then
                message.showoptions = true
                message.optselect = 1
                if message.options and #message.options > 0 then
                    pulp:emit("change", event_persist:new())
                end
            else
                -- dismiss message if no menus opened up
                message.dismiss = true
                if message == pulp.message then
                    pulp.message = nil
                end
            end
        else
            -- go to next page
            message.page += 1
            message.prompt_timer = -1
            message.textidx = 0
        end
    else
        -- wait to proceed
        message.prompt_timer += 1
    end
end

local function drawMessage(message, submenu)
    if not message or message.dismiss then
        return
    end
    if not submenu then
        if message.clear then
            playdate.graphics.clear(playdate.graphics.kColorBlack)
        end
        
        if message.text and message.page and message.text[message.page] then
            pulp.__fn_window(message.x-1, message.y-1, message.w+2, message.h+2)
            local text = substr(message.text[message.page], 1, floor(message.textidx))
            pulp.__fn_label(message.x, message.y, nil, nil, text)
            
            -- prompt to advance
            if message.prompt_timer >= 0 and not message.showoptions then
                local prompt_idx = 10 + floor((message.prompt_timer % FPS) * SPF * 2)
                pulp.pipe_img[prompt_idx]:draw(GRIDX * (message.x + message.w - 1), GRIDY * (message.y + message.h))
            end
        end
    end
    
    -- recursively draw options for previous menu
    drawMessage(message.previous, true)
    
    -- options
    if message.options and message.showoptions then
        local optw = message.optw or min(message.options_width, 8)
        local opth = message.opth or #message.options
        local optx = message.optx or message.x + message.w - 1 - optw
        local opty = message.opty or message.y + message.h
        
        pulp.__fn_window(optx - 2, opty - 1, optw + 3, opth + 2)
        
        local y = 0
        for i = message.firstopt,#message.options do
            if y >= opth then
                break
            end
            local option = message.options[i]
            local text = option.text
            if not pulp.halfwidth and #text > optw then
                text = substr(text, 1, optw)
            elseif pulp.halfwidth and #text > optw * 2 then
                text = substr(text, 1, optw * 2)
            end
            pulp.__fn_label(optx, opty + y, nil, nil, text)
            y += 1
        end
        
        -- cursor
        pulp.pipe_img[submenu and 13 or 12]:draw((optx - 1) * GRIDX, (opty + message.optselect - message.firstopt) * GRIDY)
        
        if #message.options > opth then
            -- page icon
            pulp.pipe_img[14]:draw(GRIDX * (optx + optw - 1), GRIDY * (opty + opth))
        end
    end
end

local function readInput()
    local a = playdate.buttonIsPressed( playdate.kButtonA )
    local b = playdate.buttonIsPressed( playdate.kButtonB )
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
    
    pulp.PTLE_CONFIRM_DAS = -1
    pulp.PTLE_CANCEL_DAS = -1
    pulp.PTLE_V_DAS = -1
    pulp.PTLE_H_DAS = -1
    local a_pressed = a and not prev_a
    local b_pressed = b and not prev_b
    local up_pressed = up and not prev_up
    local down_pressed = down and not prev_down
    local left_pressed = left and not prev_left
    local right_pressed = right and not prev_right
    
    if config.inputRepeat == 1 then
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
            pulp.PTLE_CONFIRM_DAS = 1
        end
        if b and b_press_time and now >= b_press_time  then
            b_press_time = next_repeat
            b_pressed = true
            pulp.PTLE_CANCEL_DAS = 1
        end
        if up and up_press_time and now >= up_press_time  then
            up_press_time = next_repeat
            up_pressed = true
            pulp.PTLE_V_DAS = 1
        end
        if down and down_press_time and now >= down_press_time  then
            down_press_time = next_repeat
            down_pressed = true
            pulp.PTLE_V_DAS = 1
        end
        if left and left_press_time and now >= left_press_time  then
            left_press_time = next_repeat
            left_pressed = true
            pulp.PTLE_H_DAS = 1
        end
        if right and right_press_time and now >= right_press_time  then
            right_press_time = next_repeat
            right_pressed = true
            pulp.PTLE_H_DAS = 1
        end
    else
        a_press_time = false
        b_press_time = false
        up_press_time = false
        down_press_time = false
        left_press_time = false
        right_press_time = false
    end
    
    if pulp.message then
        updateMessage(up_pressed, down_pressed, left_pressed, right_pressed, a_pressed, b_pressed)
    else
        local player = pulp.player
        
        if up_pressed or down_pressed or left_pressed or right_pressed then
            event_persist.dx = 0
            event_persist.dy = 0
            if up_pressed then
                event_persist.dy = -1
            elseif down_pressed then
                event_persist.dy = 1
            elseif left_pressed then
                event_persist.dx = -1
            elseif right_pressed then
                event_persist.dx = 1
            end
        end
        
        local tx = max(0, min(player.x + event_persist.dx, TILESW-1))
        local ty = max(0, min(player.y + event_persist.dy, TILESH-1))
        event_persist.tx = tx
        event_persist.ty = ty
    
        local playerScript = pulp:getPlayerScript()
        if pulp.listen and (pulp.PTLE_SMOOTH_MOVEMENT_SPEED <= 0 or (pulp.player.smooth_x == pulp.player.x and pulp.player.smooth_y == pulp.player.y)) then
            if a_pressed and playerScript then
                (playerScript.confirm or playerScript.any)(pulp.player, event_persist:new(), "confirm")
            end
            if b_pressed and playerScript then
                (playerScript.cancel or playerScript.any)(pulp.player, event_persist:new(), "cancel")
            end
                
            local do_exit = false
            if pulp.listen then
                -- check for exits
                -- TODO: only do this if player has moved since previous frame
                local x = player.x
                local y = player.y
                if x ~= disabled_exit_x or y ~= disabled_exit_y then
                    disabled_exit_x = nil
                    disabled_exit_y = nil
                end
                for i = 1,#__exits do
                    local exit = __exits[i]
                    if exit.edge == nil and (x ~= disabled_exit_x or y ~= disabled_exit_y) then
                        do_exit = x == exit.x and y == exit.y
                    elseif exit.edge == 1 then
                        do_exit = x == exit.x and event_persist.dx > 0
                    elseif exit.edge == 2 then
                        do_exit = y == exit.y and event_persist.dy > 0
                    elseif exit.edge == 3 then
                        do_exit = x == exit.x and event_persist.dx < 0
                    elseif exit.edge == 0 or exit.edge == 4 then
                        do_exit = y == exit.y and event_persist.dy < 0
                    end
                    if do_exit then
                        if exit.fin then
                            pulp.__fn_fin(exit.fin)
                        else
                            if exit.edge == nil then
                                pulp.__fn_goto(exit.tx, exit.ty, exit.room)
                            elseif exit.edge == 1 or exit.edge == 3 then
                                pulp.__fn_goto(exit.tx, y, exit.room)
                            elseif exit.edge == 2 or exit.edge == 4 or exit.edge == 0 then
                                pulp.__fn_goto(x, exit.ty, exit.room)
                            end
                        end
                        break
                    end
                end
                    
                -- move, and check for interactions and collections
                if (up_pressed or down_pressed or left_pressed or right_pressed) then
                    if not do_exit then
                            local ttile = roomtiles[ty][tx]
                            if ttile then -- paranoia
                            
                            if not ttile.solid then
                                player.x = tx
                                player.y = ty
                                if pulp.PTLE_SMOOTH_MOVEMENT_SPEED <= 0 then
                                    player.smooth_x = player.x
                                    player.smooth_y = player.y
                                end
                            else
                                if playerScript then
                                    (playerScript.bump or playerScript.any)(player, event_persist:new(), "bump")
                                end
                            end
                            
                            local _type = ttile.ttype
                            local _script = ttile.script or EMPTY
                            
                            -- _script_any <- script.any, or if that's NOT SET BY USER (i.e. is EMPTY) then nil.
                            -- bad code. :|
                            local _script_any = _script.any
                            if _script_any == EMPTY.any then
                                _script_any = nil
                            end
                            
                            if _type == TTYPE_SPRITE and config.autoAct then
                                (_script.interact or _script_any or default_event_interact)(ttile, event_persist:new(), "interact")
                            elseif _type == TTYPE_ITEM then
                                (_script.collect or _script_any or default_event_collect)(ttile, event_persist:new(), "collect")
                            end
                        end
                    end
                    if playerScript then
                        (playerScript.update or playerScript.any)(player, event_persist:new(), "update")
                    end
                end
            end
        end
    end
    
    prev_a = a
    prev_b = b
    prev_up = up
    prev_down = down
    prev_left = left
    prev_right = right
end


local function smoothMovementBegin()
    local player = pulp.player
    pulp.smooth_true_x = player.x
    pulp.smooth_true_y = player.y
    if pulp.PTLE_SMOOTH_MOVEMENT_SPEED > 0 then
        player.smooth_x = tween(player.smooth_x, player.x, pulp.PTLE_SMOOTH_MOVEMENT_SPEED)
        player.smooth_y = tween(player.smooth_y, player.y, pulp.PTLE_SMOOTH_MOVEMENT_SPEED)
        pulp.PTLE_SMOOTH_OFFSET_X = player.smooth_x - player.x
        pulp.PTLE_SMOOTH_OFFSET_Y = player.smooth_y - player.y
    else
        player.smooth_x = player.x
        player.smooth_y = player.y
        pulp.PTLE_SMOOTH_OFFSET_X = 0
        pulp.PTLE_SMOOTH_OFFSET_Y = 0
    end
end

local function smoothMovementEnd()
    local player = pulp.player
    player.x = pulp.smooth_true_x
    player.y = pulp.smooth_true_y
    pulp.PTLE_SMOOTH_OFFSET_X = 0
    pulp.PTLE_SMOOTH_OFFSET_Y = 0
end

function playdate.update()
    if not pulp.game_is_loaded then
        return
    end
    
    if pulp.restart then
        pulp:emit("finish", event_persist:new())
        __pulp_audio.killCallbacks()
        pulp:savestore()
        pulp.resetvars()
        
        pulp:start()
        return
    end
    
    __pulp_audio.update()
    
    if pulp.roomQueued then
        pulp:exitRoom()
        
        if pulp.roomQueuedX and pulp.roomQueuedY then
            pulp.player.x = pulp.roomQueuedX
            pulp.player.y = pulp.roomQueuedY
            pulp.player.smooth_x = pulp.player.x
            pulp.player.smooth_y = pulp.player.y
        end
        
        pulp:enterRoom(pulp.roomQueued)
    end
    
    readAccelerometer()
    readInput() -- (and do player physics)
        
    local timers_activate = {}
    if not pulp.message then
        for i, timer in pairs(pulp.timers) do
            timer.duration -= SPF
            if timer.duration <= 0 then
                pulp.timers[i] = nil
                timers_activate[#timers_activate+1] = timer
            end
        end
        
        (pulp.gameScript.loop or pulp.gameScript.any)(pulp.game, event_persist:new(), "loop")
    end
        
    playdate.display.setInverted(pulp.invert)
    
    -- precompute tile indices by (frame rate, frame count)
    for fps, framecs in pairs(pulp.tile_fps_lookup) do
        local s = SPF
        for i, framec in pairs(framecs) do
            framecs[i] = framec + fps * SPF
            if framecs[i] >= i then
                framecs[i] = framecs[i] - i
            end
            pulp_tile_fps_lookup_floor[pulp_tile_fps_lookup_floor_lookup[fps][i]] = floor(framecs[i])
        end
    end
    
    smoothMovementBegin()
    
    local scrolly = 0
    local scrollx = 0
    -- smooth_scroll* and scroll* differ only when smooth movement is enabled
    local smooth_scrollx = 0
    local smooth_scrolly = 0
    local scroll = false
    
    if config.follow ~= 0 then
        scrollx = config.followCenterX - pulp.player.x - math.floor(pulp.PTLE_SMOOTH_OFFSET_X)
        scrolly = config.followCenterY - pulp.player.y - math.floor(pulp.PTLE_SMOOTH_OFFSET_Y)
        smooth_scrollx = config.followCenterX - pulp.player.x - pulp.PTLE_SMOOTH_OFFSET_X
        smooth_scrolly = config.followCenterY - pulp.player.y - pulp.PTLE_SMOOTH_OFFSET_Y
        pulp.PTLE_SMOOTH_OFFSET_FRACX = pulp.PTLE_SMOOTH_OFFSET_X - math.floor(pulp.PTLE_SMOOTH_OFFSET_X)
        pulp.PTLE_SMOOTH_OFFSET_FRACY = pulp.PTLE_SMOOTH_OFFSET_Y - math.floor(pulp.PTLE_SMOOTH_OFFSET_Y)
        if scrolly == 0 and scrollx == 0 then
            scroll = false
        else
            scroll = true
        end
    else
        pulp.PTLE_SMOOTH_OFFSET_FRACX = 0
        pulp.PTLE_SMOOTH_OFFSET_FRACY = 0
    end
    
    local framei = nil
    
    -- update tile frames and draw tiles
    -- WARNING: DUPLICATE CODE! Yes, yes, but it's efficient, and this loop is hot, oh boy.
    if scroll then
        for x = cropl,cropr do
            for y = cropu,cropd do
                if y - scrolly >= TILESH or y - scrolly < 0 or x - scrollx >= TILESW or x - scrollx < 0 then
                    -- skip this one
                else
                    local tilei = roomtiles[y - scrolly][x - scrollx]
                    local dsttilei = roomtiles[y][x]
                    local frames = tilei.frames
                    
                    if tilei.play then -- [[CAN STATICALLY OPTIMIZE OUT]]
                        framei = floor(tilei.frame)
                        if framei < #frames then
                            tilei.frame += SPF * tilei.fps
                        elseif tilei.play_block then
                            timers_activate[#timers_activate+1] = {
                                block = tilei.play_block,
                                self = tilei.play_self,
                                event = tilei.play_event,
                                evname = tilei.play_evname,
                                actor = tilei.play_actor,
                            }
                            tilei.play_block = nil
                            framei = #frames - 1
                        end
                    elseif tilei.fps > 0 then -- [[CAN STATICALLY OPTIMIZE OUT]]
                        framei = pulp_tile_fps_lookup_floor[tilei.fps_lookup_idx]
                        tilei.frame = framei
                    else
                        framei = tilei.frame
                    end
                        
                    
                    -- checks if changed
                    local frame = frames[framei + 1] or frames[1] or 1
                    if dsttilei.prev_frame ~= frame then
                        dsttilei.prev_frame = frame
                        tilemap:setTileAtPosition(x+1, y+1, frame)
                    end
                end
            end
        end
    else
        -- no scrolling
        for x = cropl,cropr do
            for y = cropu,cropd do
                local tilei = roomtiles[y][x]
                local frames = tilei.tile.frames
                
                if tilei.play then -- [[CAN STATICALLY OPTIMIZE OUT]]
                    framei = floor(tilei.frame)
                    if framei < #frames then
                        tilei.frame += SPF * tilei.fps
                    elseif tilei.play_block then
                        timers_activate[#timers_activate+1] = {
                            block = tilei.play_block,
                            self = tilei.play_self,
                            event = tilei.play_event,
                            evname = tilei.play_evname,
                            actor = tilei.play_actor,
                        }
                        tilei.play_block = nil
                        framei = #frames - 1
                    end
                elseif tilei.fps > 0 then
                    framei = pulp_tile_fps_lookup_floor[tilei.fps_lookup_idx]
                    tilei.frame = framei
                else
                    framei = tilei.frame
                end
                
                -- checks if changed
                local frame = frames[framei + 1] or frames[1] or 1
                if tilei.prev_frame ~= frame then
                    tilei.prev_frame = frame
                    tilemap:setTileAtPosition(x+1, y+1, frame)
                end
            end
        end
    end
        
    if iscropped or scroll then
        -- draw cropping borders
        -- FIXME: more efficient implementation of this.
        local overflowtile = pulp:getTile(config.followOverflowTile) or {frames={1}}
        local frame = overflowtile.frames[1] or 1
        for x=0,TILESW-1 do
            for y=0,TILESH-1 do
                if x < cropl or x > cropr or y < cropu or y > cropd then
                    tilemap:setTileAtPosition(x+1,y+1, frame)
                    roomtiles[y][x].prev_frame = frame
                elseif scroll and (x - scrollx < 0 or x - scrollx >= TILESW or y - scrolly < 0 or y - scrolly >= TILESH) then
                    tilemap:setTileAtPosition(x+1,y+1, frame)
                    roomtiles[y][x].prev_frame = frame
                end
            end
        end
    end
    
    -- execute elapsed timer events
    for i=1,#timers_activate do
        local timer = timers_activate[i]
        assert(timer.actor)
        assert(timer.actor.script)
        timer.block(timer.actor, timer.event, timer.evname)
    end
    
    -- draw all non-player tiles
    tilemap:draw(-pulp.PTLE_SMOOTH_OFFSET_FRACX * GRIDX, -pulp.PTLE_SMOOTH_OFFSET_FRACY * GRIDY)
    
    -- update player frame
    local player = pulp.player
    
    if player.fps > 0 then
        player.frame = pulp_tile_fps_lookup_floor[player.fps_lookup_idx]
    else
        player.frame = floor(player.frame)
    end
    
    local playerScript = pulp:getPlayerScript()
    if playerScript then
        (playerScript.draw or playerScript.any)(player, event_persist:new(), "draw")
    end
    
    if not pulp.hideplayer and player.tile then
        local frame = player.tile.frames[1 + (floor(player.frame) % max(1, #player.tile.frames))]
        tile_img[frame]:draw(GRIDX * (player.x + smooth_scrollx + pulp.PTLE_SMOOTH_OFFSET_X), GRIDY * (player.y + smooth_scrolly + pulp.PTLE_SMOOTH_OFFSET_Y))
    end
    pulp.hideplayer = false
    
    smoothMovementEnd()
    
    drawMessage(pulp.message)
    
    -- shake timer
    if pulp.shake > 0 then
        pulp.shake -= SPF
        if pulp.shake <= 0 then
            playdate.display.setOffset(0, 0)
        else
            playdate.display.setOffset(random(-pulp.shakex, pulp.shakey), random(-pulp.shakex, pulp.shakey))
        end
    end
    
    -- clear blank frames
    if pulp.restart then
        playdate.graphics.clear( playdate.graphics.kColorBlack )
    end
    
    if pulp.PTLE_SHOW_FPS then
        playdate.drawFPS()
    end
    
    pulp.frame += 1
end

function pulp:loadSounds()
    -- we outsource music to pulp-audio
    __pulp_audio.init(pulp.songs)
    for _, song in pairs(pulp.songs) do
        pulp.song_names_by_id[song.id] = song.name
    end
    
    -- we handle sounds ourself
    for i, sound in pairs(pulp.sounds) do
        if sound.name == nil then
            print("WARNING: sound #" .. tostring(i) .. " has nil name")
        else
            pulp.sounds_by_name[sound.name] = sound
            sound.attack = sound.attack or 0.005
            sound.decay = sound.decay or 0.1
            sound.sustain = sound.sustain or 0.5
            sound.release = sound.release or 0.1
            sound.volume = sound.volume or 1
            local sequence = playdate.sound.sequence.new() 
            
            local steps_per_second = 4 * sound.bpm / 60
            local final = __FIREFOX_SOUND_COMPAT and (1 + ceil((sound.attack + sound.decay) * steps_per_second)) or 1 
            local max_polyphony = 3
            for j=1,final do 
                local any_notes = false
                local track = playdate.sound.track.new()
                
                local scale_factor = 1
                if __FIREFOX_SOUND_COMPAT and j < final then
                    local max_time = j / steps_per_second
                    local destime = (sound.attack + sound.decay)
                    scale_factor = min(max_time/destime, 1)
                end
                
                local inst = playdate.sound.instrument.new()
                for i = 1,max_polyphony do
                    local synth = playdate.sound.synth.new(wavetypes[sound.type])
                    synth:setAttack(sound.attack * scale_factor)
                    synth:setDecay(sound.decay * scale_factor)
                    -- it doesn't really make sense that sustain is scaled by scale_factor, but firefox does this.
                    synth:setSustain(sound.sustain * scale_factor)
                    synth:setRelease(sound.release)
                    
                    synth:setVolume(sound.volume * SOUNDSCALE[sound.type])
                    
                    inst:addVoice(synth)
                end
                track:setInstrument(inst)
                local max_polyphony = min(3, 1 + ceil(sound.bpm * SPF * (sound.decay or 0.1)))
                for i=1,#sound.notes,3 do
                    local octave = sound.notes[i+1] + 1
                    local pitch = sound.notes[i] + 12 * octave - 1
                    local length = sound.notes[i + 2]
                    local step = floor((i+2)/3)
                    if length ~= 0 then
                        if length == j or (length >= j and j == final) then
                            track:addNote(step, pitch, length)
                            any_notes = true
                        end
                    end
                end
            
                if any_notes then
                    sequence:addTrack(track)
                end
            end

            sequence:setTempo(steps_per_second)
            sound.sequence = sequence
        end
    end
end

function pulp:load()
    pulp.resetvars()
    pulp.loadstore()
    event_persist.game = pulp.game
    pulp.game.name = pulp.gamename
    pulp.player.script = pulp:getScript(pulp.playerid) or EMPTY
    assert(pulp.player.script)
    pulp.tile_fps_lookup = {}
    pulp:loadSounds()
    for _, tile in pairs(pulp.tiles) do
        pulp.tiles_by_name[tile.name] = tile
        if tile.fps > 0 then
            pulp_tile_fps_lookup_floor_lookup[tile.fps] = pulp_tile_fps_lookup_floor_lookup[tile.fps] or {}
            if not pulp_tile_fps_lookup_floor_lookup[tile.fps][#tile.frames] then
                local idx = #pulp_tile_fps_lookup_floor + 1
                pulp_tile_fps_lookup_floor[idx] = 0
                pulp_tile_fps_lookup_floor_lookup[tile.fps][#tile.frames] = idx
            end
            tile.fps_lookup_idx = pulp_tile_fps_lookup_floor_lookup[tile.fps][#tile.frames]
            pulp.tile_fps_lookup[tile.fps] = pulp.tile_fps_lookup[tile.fps] or {}
            pulp.tile_fps_lookup[tile.fps][#tile.frames] = 0
        end
    end
    for i, room in pairs(pulp.rooms) do
        room.type = ACTOR_TYPE_ROOM
        room.tiles_init = copytable(room.tiles)
        pulp.rooms_by_name[room.name] = room
        room.__tostring = function(...)
            return "0"
        end
    end
    for _, script in pairs(pulp.scripts) do
        -- ensure 'any' exists
        script.any = script.any or EMPTY.any
    end
end

function pulp:exitRoom()
    local event = event_persist:new()
    pulp:emit("exit", event)
    pulp:savestore()
    
    -- save tiles
    -- TODO: dirty cache?
    local i = 0
    local room = pulp:getCurrentRoom()
    for y=0,TILESH-1 do
        for x=0,TILESW-1 do
            i += 1
            room.tiles[i] = pulp.roomtiles[y][x].id or 0
        end
    end
end

function pulp:enterRoom(rid)
    disabled_exit_x = pulp.player.x
    disabled_exit_y = pulp.player.y
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
    __exits = room.exits
    
    -- set tiles
    for y = 0,TILESH-1 do
        for x = 0,TILESW-1 do
            local tid = room.tiles[y * TILESW + x + 1]
            assert(tid, "entering room prototype has missing tile entry")
            local tile = pulp.tiles[tid]
            assert(tile, "tile not found: " .. tostring(tid) .. " in entering room at location " .. tostring(x) .. "," .. tostring(y))
            
            local tilei = {
                id = tid,
                name = tile.name,
                type = ACTOR_TYPE_TILE,
                ttype = tile.type,
                tile = tile,
                fps = tile.fps,
                fps_lookup_idx = tile.fps_lookup_idx,
                frames = tile.frames,
                play = false,
                solid = tile.solid,
                script = tile.script or EMPTY,
                x = x,
                y = y,
                frame = 0
            }
            assert(tilei.script and tilei.script.any, "tile " .. tostring(tile.name) .. " malformed sript")
            roomtiles[y][x] = tilei
        end
    end
    
    if room.song == -2 then
        pulp.__fn_stop()
    elseif room.song >= 0 then
        pulp.__fn_loop(room.song)
    end
    
    if pulp.roomStart then
        -- 'load' and 'start' events every time restart
        local event = event_persist:new()
        for _, script in pairs(pulp.scripts) do
            ;(script.load or script.any)(pulp:getScriptPrototype(script), event, "load")
        end
        pulp.game_is_loaded = true
    
        -- 'start' event
        pulp.roomStart = false
        -- FIXME: instead of 'nil', pass 'game'?
        ;(pulp.game.script.start or pulp.game.script.any)(nil, event_persist:new(), "start")
    end
    
    -- 'enter' event
    pulp:emit("enter", event_persist:new())
end

-- returns a dummy actor with this given script
-- used for when we would otherwise pass 'nil' as the actor field for an event handler.
function pulp:getScriptPrototype(script)
    assert(script)
    return {
        script = script,
        any = EMPTY.any
    }
end

function pulp:start()
    -- FIXME: just call pulp.__fn_swap() instead.
    pulp.player.x = pulp.startx
    pulp.player.y = pulp.starty
    pulp.player.smooth_x = pulp.startx
    pulp.player.smooth_y = pulp.starty
    pulp.player.tile = pulp.tiles[pulp.playerid]
    pulp.player.id = pulp.playerid
    pulp.player.frames = pulp.player.tile.frames
    pulp.player.solid = false
    pulp.player.name = pulp.player.tile.name
    pulp.player.ttype = TTYPE_PLAYER
    pulp.player.fps = pulp.player.tile.fps
    pulp.player.fps_lookup_idx = pulp.player.tile.fps_lookup_idx
    pulp.player.play = false
    
    pulp.roomStart = true
    pulp.roomQueued = nil
    pulp.roomQueuedX = nil
    pulp.roomQueuedY = nil
    pulp.restart = false
    pulp.listen = true
    
    -- reset rooms to have their starting tiles
    for _, room in pairs(pulp.rooms) do
        room.tiles = copytable(room.tiles_init)
    end
    
    if pulp.roomQueuedX and pulp.roomQueuedY then
        pulp.player.x = pulp.roomQueuedX
        pulp.player.y = pulp.roomQueuedY
    end
    pulp:enterRoom(pulp.roomQueued or pulp.startroom)
    
    pulp.frame = 0
end

function pulp:emit(evname, event)
    
    local tasks = {}
    
    assert(event ~= pulp.player)
    
    tasks[#tasks+1] = function()
        ;(pulp.gameScript[evname] or pulp.gameScript.any)(pulp.game, event, evname)
    end
    
    local roomScript = pulp:getCurrentRoom().script
    if roomScript then
        assert(roomScript.any);
        tasks[#tasks+1] = function()
            assert(roomScript.any);
            (roomScript[evname] or roomScript.any)(pulp:getCurrentRoom(), event, evname)
        end
    end
    
    -- tiles
    for y = 0,TILESH-1 do
        for x = 0,TILESW-1 do
            local tileInstance = pulp:getTileAt(x, y)
            local script = tileInstance.script
            if script then
                assert(script.any)
                tasks[#tasks+1] = function()
                    ;(script[evname] or script.any)(tileInstance, event, evname)
                end
            end
        end
    end
    
    -- player
    local playerScript = pulp:getPlayerScript()
    local player = pulp.player
    if playerScript then
        tasks[#tasks+1] = function()
            ;(playerScript[evname] or playerScript.any)(player, event, evname)
        end
    end
    
    for i = 1,#tasks do
        tasks[i]()
    end
end

function pulp:forTiles(tid, cb)
    for x = 0,TILESW-1 do
        for y = 0,TILESH-1 do
            local tilei = roomtiles[y][x]
            if tilei.id == tid or tid == nil or tilei.tile.name == tid then
                cb(x, y, tilei)
            end
        end
    end
end

function pulp:loadstore()
    local p, store = pcall(playdate.datastore.read)
    if p and store then
        pulp.store = store
        pulp.store_dirty = false
    else
        print("Error loading store:")
        print(store)
    end
end

function pulp:savestore()
    if pulp.store_dirty then
        local p, err = pcall(
            playdate.datastore.write,
            pulp.store
        )
        if not p then
            print("Error saving store:")
            print(err)
        end
    end
    pulp.store_dirty = false
end

------- IMPERATIVE FUNCTIONS --------------------------------------------------

function pulp.__fn_stop()
    __pulp_audio.stopSong()
end

function pulp.__fn_once(actor, event, evname, block, song)
    __pulp_audio.playSong(
        pulp:getSongName(song),
        true,
        block and function()
            block(actor, event, evname)
        end
    )
end

function pulp.__fn_loop(song)
    __pulp_audio.playSong(
        pulp:getSongName(song),
        false
    )
end

function pulp.__fn_bpm(bpm)
    __pulp_audio.setBpm(bpm)
end

function pulp.__fn_sound(sid)
    local sound = pulp:getSound(sid)
    if sound and sound.sequence then
        sound.sequence:stop()
        sound.sequence:goToStep(1, true)
    end
end

function pulp.__fn_play(actor, event, evname, block, id)
    pulp.__fn_swap(actor, id)
    actor.play = true
    actor.frame = 0
    actor.play_event = event
    actor.play_evname = evname
    actor.play_block = block
    -- this is probably redundant but paranoia ok
    actor.play_actor = actor
end

local font_lookup_character <const> = {}
for i=1,#alphabet do
    font_lookup_character[string_byte(substr(alphabet, i, i))] = i
end

function pulp.__fn_label(x, y, len, lines, text)
    assert(type(text) == "string")
    local startx = x
    local endy = nil
    local xinc = pulp.halfwidth and (1 / 2) or 1
    local srcrect = HALFWIDTH_SRCRECT
    if lines then
        endy = y + lines
    end
    if len then
        len = min(len, #text)
    else
        len = #text
    end
    local i = 1
    while i <= len do
        local chr = string_byte(substr(text, i, i))
        assert(chr)
        if chr == string_byte("\n") then
            x = startx
            y += 1
            if endy and y > endy then
                return
            end
        elseif chr < 0x80 then
            local chridx = font_lookup_character[chr] or 1
            font_img[chridx]:draw(x * GRIDX, y * GRIDY, nil, HALFWIDTH_SRCRECT)
            x += xinc
        else
            -- embed
            -- decode tile
            local numbytes = chr % 0x80
            local frame = 0
            local j = i
            for k=numbytes,1,-1 do
                i += 1
                frame *= 0x80
                local _chr = string_byte(substr(text, j+k, j+k))
                local b = 0
                if _chr then
                    b = _chr % 0x80
                else
                    print("WARNING: error decoding embedded tile")
                end
                frame += b
            end
            if pulp.tile_img[frame] then
                pulp.tile_img[frame]:draw(x * GRIDX, y * GRIDY, nil, HALFWIDTH_SRCRECT)
            end
            x += xinc
        end
        i += 1
    end
end

function pulp.__fn_draw(x, y, tid)
    local tile = pulp:getTile(tid)
    if tile and tile.frames then
        local frame = tile.frames[1]
        pulp.tile_img[frame]:draw(x * GRIDX, y * GRIDY)
    end
end

function pulp.__fn_restore(name)
    if name == nil then
        for _name in pairs(pulp.store) do
            local v = pulp.store[_name]
            if type(v) ~= "table" then
                pulp.setvariable(_name, v)
            end
        end
    else
        assert(type(name) == "string")
        local v = pulp.store[name]
        if v and type(v) ~= "table" then
            pulp.setvariable(name, v)
        end
    end
end

function pulp.__fn_store(name)
    assert(type(name) == "string")
    local value = pulp.getvariable(name)
    if type(value) ~= "table" then
        pulp.store[name] = value
    end
    pulp.store_dirty = true
end

function pulp.__fn_toss(name)
    if name == nil then
        pulp.store = {}
        pulp.store_dirty = true
    else
        assert(type(name) == "string")
        pulp.store[name] = nil
        pulp.store_dirty = true
    end
end

function pulp.__fn_wait(actor, event, evname, block, duration)
    pulp.timers[#pulp.timers+1] = {
        duration = duration,
        block = block,
        event = event,
        evname = evname,
        actor = actor,
    }
end

function pulp.__fn_say(x,y,w,h, actor, event, evname, block,text)
    assert(not block or type(block) == "function", "say 'then' block is not a function")
    assert(type(text) == "string", "say text must be a string")
    x = min(x or 3, TILESW - 1) + 1
    y = min(y or 3, TILESH - 1) + 1
    if w == 0 then w = nil end
    if h == 0 then h = nil end
    if w and pulp.halfwidth then
        w = ceil(w/2)
    end
    w = w or (TILESW - 8)
    h = h or 4
    
    w = max(w, 1)
    h = max(h, 1)
        
    pulp.message = {
        x = x,
        y = y,
        w = w,
        h = h,
        page = 1,
        prompt_timer = -1,
        sayAdvanceDelay = config.sayAdvanceDelay,
        textSpeed = config.textSpeed,
        textidx = 0,
        clear = pulp.frame == 0,
        text = paginate(text or "", w * (pulp.halfwidth and 2 or 1), h),
        options_width = 0, -- text width of largest option
        optselect = 1,
        firstopt = 1,
        actor = actor,
        event = event,
        evname = evname,
        block = block
    }
    
    assert(pulp.message.text)
    assert(pulp.message.text[1])
    
    if block then
        assert(event, "ask block not given an event")
    end
end

function pulp.__fn_menu(x,y,w,h, actor, event, evname, block)
    x = x or 2
    y = y or 3
    assert(type(block) == "function")
        
    print("menu")
    
    pulp.message = {
        optx = x + 2,
        opty = y + 1,
        options_width = 0, -- text width of largest option
        optw = w,
        opth = h,
        clear = pulp.frame == 0,
        previous = pulp.message,
        showoptions = false,
        firstopt = 1,
        optselect = 1,
        sayAdvanceDelay = config.sayAdvanceDelay,
        textSpeed = config.textSpeed,
        actor = actor,
        event = event,
        evname = evname,
        block = block
    }
    
    if pulp.message.previous then
        pulp.message.clear = pulp.message.previous.clear
    end
end

function pulp.__fn_option(actor, event, evname, block, text)
    local message = pulp.optattachmessage
    if not message then return end
    if message.dismiss or message.showoptions then return end
    assert(type(text) == "string")
    message.options = message.options or {}
    local optwidth = #text
    if pulp.halfwidth then
        optwidth = ceil(optwidth / 2)
    end
    message.options_width = max(message.options_width, optwidth)
    message.options[#message.options + 1] = {
        text = text,
        block = block,
        actor = actor,
        event = event,
        evname = evname,
    }
    if block then
        assert(event, "option event is nil")
    end
end

pulp.__fn_ask = pulp.__fn_say

function pulp.__fn_fin(text)
    pulp.__fn_say(nil, nil, nil, nil, {}, {}, "", function()
        pulp.restart = true
    end, text)
    
    pulp.message.clear = true
    pulp.message.is_finish = true
end

function pulp.__fn_window(x, y, w, h)
    x = x or 3
    y = y or 3
    w = w or TILESW - 4
    h = h or 6
    local x2 = x + w - 1
    local y2 = y + h - 1
    
    if x2 <= x or y2 <= y then return end
    
    local ui = pulp.pipe_img
    
    -- corners
    ui[1]:draw(x * GRIDX, y * GRIDY)
    ui[3]:draw(x2 * GRIDX, y * GRIDY)
    ui[7]:draw(x * GRIDX, y2 * GRIDY)
    ui[9]:draw(x2 * GRIDX, y2 * GRIDY)
    
    -- edges
    local u = ui[2]
    local l = ui[4]
    local mid = ui[5]
    local r = ui[6]
    local d = ui[8]
    for j = y+1,y2-1 do
        l:draw(x * GRIDX, j * GRIDY)
        r:draw(x2 * GRIDX, j * GRIDY)
    end
    for i = x+1,x2-1 do
        u:draw(i * GRIDX, y * GRIDY)
        d:draw(i * GRIDX, y2 * GRIDY)
        for j = y+1,y2-1 do
            mid:draw(i * GRIDX, j * GRIDY)
        end
    end 
end

function pulp.__fn_act()
    local player = pulp.player
    local x = player.x
    local y = player.y
    local dx = event_persist.dx
    local dy = event_persist.dy
    if x >= 0 and y >= 0 and x < TILESW and y < TILESH then
        local itemtile = roomtiles[y][x]
        if itemtile.ttype == TTYPE_ITEM then
            local _script = itemtile.script or {};
            (_script.collect or _script.any or default_event_collect)(itemtile, event_persist:new(), "collect")
        end
    end
    x += dx
    y += dy
    if x >= 0 and y >= 0 and x < TILESW and y < TILESH then
        local itemtile = roomtiles[y][x]
        if itemtile.ttype == TTYPE_SPRITE then
            local _script = itemtile.script or {};
            (_script.interact or _script.any or default_event_interact)(itemtile, event_persist:new(), "interact")
        end
    end
end

function pulp.__fn_dump()
    print("dump command not yet implemented in pulp-to-lua.")
end

function pulp.__fn_crop(x, y, w, h)
    local prevw = cropr - cropl + 1
    local prevh = cropu - cropd + 1
    cropl = max(0, x or cropl)
    cropr = min(TILESW, cropl + (w or prevw)) - 1
    cropu = max(0, y or cropu)
    cropd = min(TILESH, cropu + (h or prevh)) - 1
    
    iscropped = false
    if cropl ~= 0 or cropr ~= TILESW - 1 or cropu ~= 0 or cropd ~= TILESH - 1 then
        iscropped = true
    end
end

function pulp.__fn_goto(x, y, room)
    if room then
        pulp.roomQueuedX = x
        pulp.roomQueuedY = y
        pulp.roomQueued = room
    else
        local player = pulp.player
        event_persist.dx = (x or player.x) - player.x
        event_persist.dy = (y or player.y) - player.y
        player.x = x or player.x
        player.y = y or player.y
        if pulp.PTLE_SMOOTH_MOVEMENT_SPEED <= 0 then
            player.smooth_x = player.x
            player.smooth_y = player.y
        end
        
        -- oddly, the reference implementation seems to do this:
        local playerScript = pulp:getPlayerScript()
        stackdepth += 1
        if playerScript and not preventStackOverflow() then
            (playerScript.update or playerScript.any)(player, event_persist:new(), "update")
        end
        stackdepth -= 1
    end
end

function pulp.__fn_invert()
    pulp.invert = not pulp.invert
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

function pulp.__fn_tell(event, evname, block, actor)
    if type(actor) == "string" or type(actor) == "number" then
        local tile = pulp:getTile(actor)
        if tile then
            block(pulp:getScriptPrototype(tile.script), event, evname)
        else
            print("WARNING: `tell` command on invalid tile '" .. tostring(actor) .. '"')
        end
    elseif type(actor) == "table" then
        block(__NIL or EMPTY, actor, event, evname)
    else
        assert(false, "invalid tell target: " .. tostring(actor))
    end
end

function pulp.__fn_swap(actor, newid)
    assert(newid)
    if actor and actor.tile then
        local newtile = pulp:getTile(newid)
        if newtile then
            actor.tile = newtile
            actor.id = actor.tile.id
            if not actor.is_player then
                actor.script = actor.tile.script or EMPTY
            end
            actor.play = false
            actor.frames = newtile.frames
            actor.solid = actor.tile.solid
            actor.name = actor.tile.name
            actor.ttype = actor.tile.type
            actor.fps = actor.tile.fps
            actor.fps_lookup_idx = actor.tile.fps_lookup_idx
            actor.frame = 0
        else
            print("cannot swap to tile " .. newid)
            assert(false)
        end
    end
end

------- EXPRESSION FUNCTIONS --------------------------------------------------

-- tile embeds are encoded in 0x80+ bytes
-- first byte indicates number of bytes in encoding
-- subsequent bytes are 0x80 plus 7 bits of frame index, big-endian over bytes.
-- this might be different from pulp original.
function pulp.__ex_embed(tid)
    local frame = pulp:getTile(tid).frames[1] or 1
    
    local frame_bh = frame
    local bytes = { 0x80 }
    while frame_bh > 0 do
        bytes[1] = bytes[1] + 1
        bytes[#bytes+1] = 0x80 + (frame_bh % 128)
        frame_bh = floor(frame_bh / 128)
    end

    local s = ""
    for _, byte in ipairs(bytes) do
        s = s .. string_char(byte)
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

function pulp.__ex_name(id)
    if type(id) == "table" then
        return id.name
    else
        local tile = pulp.tiles[id]
        if tile then
            return tile.name
        else
            return ""
        end
    end
end

function pulp.__ex_type(x, y, id)
    if x or y then
        if x >= 0 and x < TILESW and y >= 0 and y < TILESH then
            return roomtiles[y][x].tile.type
        end
    else
        local tile = pulp:getTile(id)
        if tile then
            return tile.type
        end
    end
    
    return 0
end

-- TODO: inline this
function pulp.__ex_solid(x, y, id)
    if x and y then
        if x < 0 or x >= TILESW or y < 0 or y >= TILESH then
            -- edge case
            return 1
        end
        local tilei = pulp.roomtiles[y][x]
        return (tilei and tilei.solid) and 1 or 0
    else
        local tile = pulp:getTile(id)
        return (tile and tile.solid) and 1 or 0
    end
end
