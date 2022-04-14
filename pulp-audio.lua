-- Modified from pulp stock download pulp-audio.lua

-- shims
local function doValue(value) return value end
local function doAction(action) return action() end
local function pushCall(action) return action() end

-- extracted
local VoiceType = {
	Sine = 0,
	Square = 1,
	Sawtooth = 2,
	Triangle = 3,
	Noise = 4,
}

local snd = playdate.sound
local ms = playdate.getCurrentTimeMilliseconds

local function list(table) return table end

local function isString(value)
	return type(value)=='string'
end

local errorSource = '<runtime>'
local errorLine = -1
local function fatal(msg)
	error('Fatal: '..msg..' ('..errorSource..':'..errorLine..')\n', 0)
end
local function warn(msg)
	print('Warning: '..msg..' ('..errorSource..':'..errorLine..')\n')
end


local audioTime = snd.getCurrentTime
local resetTime = snd.resetTime

local VoiceToWave = {
	[VoiceType.Sine] = snd.kWaveSine,
	[VoiceType.Square] = snd.kWaveSquare,
	[VoiceType.Sawtooth] = snd.kWaveSawtooth,
	[VoiceType.Triangle] = snd.kWaveTriangle,
	[VoiceType.Noise] = snd.kWaveNoise,
}

local function setVolume(voice, v)
	assert(v)
	voice.synths[1]:setVolume(v)
	voice.synths[2]:setVolume(v)
end
local function setEnvelope(voice, idx, a,d,s,r,v)
	voice.envelope.attack = a
	voice.envelope.decay = d
	voice.envelope.sustain = s
	voice.envelope.release = r
	voice.envelope.volume = 1
	
	voice.synths[1]:setADSR(a,d,s,r)
	voice.synths[2]:setADSR(a,d,s,r)
	local scale = SOUNDSCALE[idx]
	assert(v and scale)
	setVolume(voice, v * scale)
end
local function newVoice(type, a,d,s,r,v)
	local waveform = VoiceToWave[type]
	local voice = {
		type = type,
		synths = {
			snd.synth.new(waveform),
			snd.synth.new(waveform),
		},
		alt = false,
		envelope = {},
	}
	
	if type == 1 then
		-- square wave duty cycle
		for _, synth in pairs(voice.synths) do
			synth:setParameter(1, 0.5)
		end
	end
	
	setEnvelope(voice, type, a,d,s,r,v)
	return voice
end
local function playNote(voice, pitch, dur, when)
	voice.alt = not voice.alt
	voice.synths[voice.alt and 2 or 1]:playNote(pitch, voice.envelope.volume, dur, when)
end
local function stopNote(voice)
	voice.synths[1]:stop()
	voice.synths[2]:stop()
end


local voices = list {}
local defaultEnvelope = {
	attack = 0.005,
	decay = 0.1,
	sustain = 0.5,
	release = 0.1,
	volume = 1.0,
}
for i=1,5 do
	voices[i] = newVoice(i-1, defaultEnvelope.attack,defaultEnvelope.decay,defaultEnvelope.sustain,defaultEnvelope.release,defaultEnvelope.volume)
end
local Frequency = list {
	0, -- rest
	16.351598,
	17.323914,
	18.354048,
	19.445436,
	20.601722,
	21.826764,
	23.124651,
	24.499715,
	25.956544,
	27.5,
	29.135235,
	30.867706,
	32.703196,
	34.647829,
	36.708096,
	38.890873,
	41.203445,
	43.653529,
	46.249303,
	48.999429,
	51.913087,
	55,
	58.27047,
	61.735413,
	65.406391,
	69.295658,
	73.416192,
	77.781746,
	82.406889,
	87.307058,
	92.498606,
	97.998859,
	103.826174,
	110,
	116.54094,
	123.470825,
	130.812783,
	138.591315,
	146.832384,
	155.563492,
	164.813778,
	174.614116,
	184.997211,
	195.997718,
	207.652349,
	220,
	233.081881,
	246.941651,
	261.625565,
	277.182631,
	293.664768,
	311.126984,
	329.627557,
	349.228231,
	369.994423,
	391.995436,
	415.304698,
	440,
	466.163762,
	493.883301,
	523.251131,
	554.365262,
	587.329536,
	622.253967,
	659.255114,
	698.456463,
	739.988845,
	783.990872,
	830.609395,
	880,
	932.327523,
	987.766603,
	1046.502261,
	1108.730524,
	1174.659072,
	1244.507935,
	1318.510228,
	1396.912926,
	1479.977691,
	1567.981744,
	1661.21879,
	1760,
	1864.655046,
	1975.533205,
	2093.004522,
	2217.461048,
	2349.318143,
	2489.01587,
	2637.020455,
	2793.825851,
	2959.955382,
	3135.963488,
	3322.437581,
	3520,
	3729.310092,
	3951.06641,
	4186.009045,
	4434.922096,
	4698.636287,
	4978.03174,
	5274.040911,
	5587.651703,
	5919.910763,
	6271.926976,
	6644.875161,
	7040,
	7458.620184,
	7902.13282,
}
local streams = list {}
for i=1,6 do
	streams[i] = {
		id = -1,
		startTime = -1,
		stepTime = 0, -- based on bpm
		bpm = 120,
		tick = 0,
		
		-- song-only
		callback = nil,
		shiftTime = 0, -- affected by bpm changes
		loop = false,
		loopFrom = 0,
	}
end


local data = nil -- {}
local songsByName = nil -- {}
local soundsByName = nil -- {}


local playSound,startSong,stopSong,stopNotes,setBpm


local function getSong(value)
	local songIdent
	

	if isString(value) then
		local songName = value
		local song = songsByName[songName]
		if song then
			return song
		else 
			songIdent = ' named "'..songName..'"'
		end
	else
		local songId = value
		local song = data.songs[songId+1]
		if song then
			return song
		else
			songIdent = ' by id '..songId
		end
	end
	
	--fatal('Unable to get song '..songIdent)
	return nil
end
local function getSound(value)
	local soundIdent
	

	if isString(value) then
		local soundName = value
		local sound = soundsByName[soundName]
		if sound then
			return sound
		else 
			soundIdent = ' named "'..soundName..'"'
		end
	else
		local soundId = value
		local sound = data.sounds[soundId+1]
		if sound then
			return sound
		else
			soundIdent = ' by id '..soundId
		end
	end
	
	fatal('Unable to get sound '..soundIdent)
end


local _env = {}
local function applyEnvelope(voice, type, envelope)
	for key,value in pairs(defaultEnvelope) do
		if envelope and envelope[key] then
			_env[key] = envelope[key]
		else
			_env[key] = value
		end
	end
	setEnvelope(voice, type, _env.attack,_env.decay,_env.sustain,_env.release, _env.volume)
end

function playSound(value)
	local sound = getSound(value)
	local stream = streams[sound.type + 2]
		
	stream.id = sound.id
	stream.startTime = -1
	stream.stepTime = (60 / sound.bpm) * 0.25
	stream.bpm = sound.bpm
	stream.tick = 0
end
function startSong(value, once, callback)
	local song = getSong(value)
	if not song then
		print("WARNING: attempt to play non-existent song '" .. tostring(value) .. "'")
		return
	end
	local stream = streams[1]
	
	if stream.id==song.id then return end
	if stream.id>-1 then stopSong() end
	
	stream.id = song.id

	stream.startTime = -1
	stream.stepTime = (60 / song.bpm) * 0.25
	stream.bpm = song.bpm
	stream.tick = 0
	
	for i=1,#voices do
		applyEnvelope(voices[i], i-1, song.voices and song.voices[i])
	end
	
	stream.shiftTime = 0
	stream.loop = not once
	stream.loopFrom = 0
	if once and callback then
		

		stream.callback = function()
			

			pushCall(callback)
			

		end
	else
		stream.callback = nil
	end
end
function setBpm(bpm)
	if bpm>240 then
		warn('Invalid bpm ('..bpm..') must be less than or equal to 240')
		bpm = 240
	elseif bpm<1 then
		warn('Invalid bpm ('..bpm..') must be greater than or equal to 1')
		bpm = 1
	end
	
	local stream = streams[1]
	local stepTime = stream.stepTime
	stream.stepTime = (60 / bpm) * 0.25
	stream.shiftTime += (stepTime - stream.stepTime) * stream.tick
	stream.bpm = bpm
end
function stopNotes()
	for i=1,#voices do
		stopNote(voices[i])
	end
end
function stopSong()
	local stream = streams[1]
	if stream.id>-1 then
		stream.id = -1
		stopNotes()
	end
end

local function scheduleNote(voice, notes, i, stepTime, when)
	local note = notes[i + 1]
	if note and note>0 then
		note -= 1
		local octave = notes[i + 2]
		local hold = notes[i + 3]
		
		local freqIdx = 1 + (octave * 12) + note + 1
		local pitch = Frequency[freqIdx]
		local dur = hold * stepTime

		playNote(voice, pitch, dur, when)
	end
end

local function killCallbacks()
	for i=1,6 do
		streams[i].callback = nil
	end
end

local function updateAudio()
	local now = audioTime()
	for i=1,6 do
		local isSong = i==1
		local stream = streams[i]
		if stream.id==-1 then goto continue end
		
		local source = isSong and data.songs[stream.id + 1] or data.sounds[stream.id + 1]
		
		if stream.startTime==-1 then
			stream.startTime = audioTime()
		end
		
		local offsetTime = stream.startTime + stream.shiftTime
		local now = audioTime() - offsetTime
		local last = (stream.tick-1) * stream.stepTime
		
		if now<last then goto continue end
		
		local start = 0
		if isSong then
			local loopTicks = source.ticks - source.loopFrom
			local rep = 0
			if stream.tick>=source.ticks then
				rep += math.floor((stream.tick - stream.loopFrom) / loopTicks)
			end
			start = rep * loopTicks
		end
		local tock = stream.tick - start
		local when = stream.tick * stream.stepTime
		
		when += offsetTime
		
		local j = tock * 3
		if isSong then
			for k=1,#voices do
				scheduleNote(voices[k], source.notes[k], j, stream.stepTime, when)
			end
		else
			scheduleNote(source.voice, source.notes, j, stream.stepTime, when)
		end
		
		stream.tick += 1
		tock += 1
		if tock>=source.ticks then
			if isSong then
				if stream.loop then
					stream.loopFrom = source.loopFrom
				else
					stream.id = -1
					if stream.callback then
						stream.callback()
					end
				end
			else
				stream.id = -1
			end
		end
		
		::continue::
	end
end


local function loadAudio()
	-- sounds
	soundsByName = {}
	if not data.sounds then data.sounds = {} end
	for i, sound in pairs(data.sounds) do
		sound.voice = newVoice(sound.type, defaultEnvelope.attack,defaultEnvelope.decay,defaultEnvelope.sustain,defaultEnvelope.release,defaultEnvelope.volume)
		applyEnvelope(sound.voice, sound.envelope)
		soundsByName[sound.name] = sound
	end

	-- songs
	songsByName = {}
	if not data.songs then data.songs = {} end
	for i, song in pairs(data.songs) do
		if song.name == nil then
			print("error: song #" .. tostring(i) .. " has nil name field")
		else
			songsByName[song.name] = song
			song.splits = nil -- unneeded
		end
	end
end


local function initAudio()
	for i=1,#streams do
		streams[i].id = -1
	end
	for i=1,#voices do
		assert(SOUNDSCALE[i-1])
		setVolume(voices[i], SOUNDSCALE[i-1])
	end
end

-- API
__pulp_audio = {
	kPlayLoop = false,
	kPlayOnce = true,
	init = function(songs)
		initAudio()
		data = {
			songs = songs
		}
		loadAudio()
	end,
	update = updateAudio,
	playSound = playSound,
	playSong = startSong,
	stopSong = stopSong,
	setBpm = setBpm,
	killCallbacks = killCallbacks,
}