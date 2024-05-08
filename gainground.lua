local roundAddress = 0xffa2ca
local stageAddress = 0xffa2cb
local globalTimeAddress = 0xffea12
local timerAddress = 0xffa204

local PLAYER_BOX_SIZE = 16
local BASE_FRAME = 41317

local stageInfo =
{
	round = 0,
	stage = 0,
}

local unitGroups =
{
	{
		-- Most units
		firstAddress = 0xFFC3b0,
		unitInfoSize = 0x70,
		numUnits = 30,
		coloration = '#ff0000',
	},
	{
		-- Blue boss in 2-10
		firstAddress = 0xffc890,
		unitInfoSize = 0x80,
		numUnits = 1,
		coloration = '#4f4fff',
	},
	{
		-- 1-10 bosses, hazards
		firstAddress = 0xffc570,
		unitInfoSize = 0x80,
		numUnits = 7,
		coloration = '#ff7f00',
	},
}

local projectileGroups =
{
	{
		-- Enemy unit shots
		firstAddress = 0xffb620,
		projectileInfoSize = 0x70,
		numUnits = 20,
		color = '#ff0000',
	},
	{
		-- Player shots
		firstAddress = 0xFFB000,
		projectileInfoSize = 0x70,
		numUnits = 14,
		color = '#00ff00',
		isPlayerAttack = true,
	},
}

local aiTypeNames =
{
	[0] = "Turt",
	[1] = "Spam",
	[2] = "Sent",
	[3] = "Ambs",
	[4] = "Ptrl",
	[5] = "Aggr",
	[6] = "Repl",
	[7] = "Hypr",
	[16] = "Moat",
	[17] = "Mage",
	[18] = "Slim",
	[19] = "Burw",
	[21] = "Orb",
	[22] = "Spdr",
	[23] = "Gold Orb",
}

local SQRT_0_5 = 0.70710678118654752440084436210485

local directionVectors =
{
	[0] = { 0, -1 },
	[1] = { SQRT_0_5, -SQRT_0_5 },
	[2] = { 1, 0 },
	[3] = { SQRT_0_5, SQRT_0_5 },
	[4] = { 0, 1 },
	[5] = { -SQRT_0_5, SQRT_0_5 },
	[6] = { -1, 0 },
	[7] = { -SQRT_0_5, -SQRT_0_5 },
	[8] = { -1, 0 },
}

local function DrawDirection(cx, cy, dir, weight)
	local dv = directionVectors[dir]

	if dv ~= nil then
		local dx = directionVectors[dir][1] * weight
		local dy = directionVectors[dir][2] * weight

		local cx = math.floor(cx)
		local cy = math.floor(cy)

		local arrowPointX = cx + dx*0.5
		local arrowPointY = cy + dy*0.5

		local perpenX = dy
		local perpenY = -dx

		gui.drawline(arrowPointX, arrowPointY, arrowPointX+dy*0.25-dx*0.25, arrowPointY-dx*0.25-dy*0.25)
		gui.drawline(arrowPointX, arrowPointY, arrowPointX-dy*0.25-dx*0.25, arrowPointY+dx*0.25-dy*0.25)
		gui.drawline(arrowPointX+dx*0.1, arrowPointY+dy*0.1, arrowPointX+dy*0.25-dx*0.25, arrowPointY-dx*0.25-dy*0.25)
		gui.drawline(arrowPointX+dx*0.1, arrowPointY+dy*0.1, arrowPointX-dy*0.25-dx*0.25, arrowPointY+dx*0.25-dy*0.25)
	else
		gui.drawtext(cx, cy-20, dir)
	end
end

local function GuessUnitType(unit)
	if unit.aiType == nil then
		return ""
	end

	local aiType = memory.readbyte(unit.aiType)
	local unitType1 = memory.readbyte(unit.unitType)
	local unitType2 = memory.readbyte(unit.unitType2)

	if aiTypeNames[aiType] then
		aiType = aiTypeNames[aiType]
	end

	if stageInfo.round == 1 and stageInfo.stage == 8 and unitType1 == 20 then
		return "Demn"
	end

	if stageInfo.round == 1 and stageInfo.stage == 10 then
		if unitType1 == 16 then
			return "Demn"
		elseif unitType1 == 196 then
			return "Boss1"
		end
	end

	if stageInfo.round == 2 and stageInfo.stage == 10 and unitType1 == 235 then
		return "Boss2"
	end

	if stageInfo.round == 3 and stageInfo.stage == 10 then
		if unitType1 == 0 then
			return "Boss3Blue"
		elseif unitType1 == 245 then
			return "Boss3Red"
		end
	end

	if stageInfo.round == 4 and stageInfo.stage == 10 and unitType1 == 13 then
		return "Boss4"
	end

	if stageInfo.round == 5 and stageInfo.stage == 2 and unitType1 == 32 then
		return "Tank"
	end

	if stageInfo.round == 5 and stageInfo.stage == 10 and unitType1 == 73 then
		return "Boss5"
	end

	if stageInfo.round == 5 and stageInfo.stage == 8 and unitType2 == 139 then
		return "Laser"
	end

	return aiType
end

local function ToHex(num)
	local asHex = ""
	while num > 0 do
		local rem = math.fmod(num, 16)
		asHex = string.sub("0123456789abcdef", rem+1, rem+1)..asHex
		num = (num - rem)/ 16
	end
	if asHex == "" then
		return "0"
	end
	return asHex
end

local function ToScreenCoords(x, y)
	return x-124, y-120
end

local projectileModes =
{
	[4] = "Traj",	-- Travels in a line based on state
	[8] = "Fade",
	[12] = "Bug",
}

local projectileStatOffsets =
{
	xAddr = 0x0,
	yAddr = 0x2,
	projType = 0x4,
	direction = 0x9,
	internalState = 0x17,
	stateTimer = 0x18,

	--speedYdir = 0x1a,	-- 2 = negative, 1 = positive
	speed = 0x1b,

	subPixelX = 0x1f,
	subPixelY = 0x21,

	-- Heading = number of pixels moved since last frame
	xHeading = 0x26,
	yHeading = 0x28,


	lifeDecSpeed = 0x1a,
	projMode = 0x31,
	lifeRemaining = 0x36,

}


local unitStatOffsets =
{
	baseAddress = 0x0,
	xAddr = 0x0,
	yAddr = 0x2,
	overallState = 0x11,
	subState = 0x17,
	direction = 0x9,
	actionTimer = 0x18,
	miscAlive = 0x30,
	aiState1 = 0x31,
	aiTimer = 0x3a,		-- 2 bytes, resets to 0 when hit by a projectile
	aiState2 = 0x3c,
	hp = 0x3d,
	stateCounter = 0x52,

	

	-- 0x51: Possible way to distinguish laser turrets on 5-8, always 139
	aiType = 0x34,
	unitType = 0x39,
	unitType2 = 0x51,
}

local OffsetAddresses = function(addr, addressDict)
	local unit = { }

	for k,v in pairs(addressDict) do
		unit[k] = addr + v
	end

	return unit
end


local player1 = 
{
	xAddr = 0xffa800,
	yAddr = 0xffa802,
	stateCounter = 0xffa83b,
}

local player2 = 
{
	xAddr = 0xffa900,
	yAddr = 0xffa902,
	stateCounter = 0xffa93b,
}

local enemyUnits = { }
local projectiles = { }

-- Create enemy units
for _,ug in ipairs(unitGroups) do
	for i=1,ug.numUnits do
		local unit = OffsetAddresses((i-1)*ug.unitInfoSize + ug.firstAddress, unitStatOffsets)
		unit.coloration = ug.coloration
		enemyUnits[#enemyUnits+1] = unit
	end
end

-- Create projectiles
for _,pg in ipairs(projectileGroups) do
	for i=1,pg.numUnits do
		local p = OffsetAddresses((i-1)*pg.projectileInfoSize + pg.firstAddress, projectileStatOffsets)
		p.color = pg.color
		p.isPlayerAttack = pg.isPlayerAttack
		projectiles[#projectiles+1] = p
	end
end

local function drawProjectileBox(proj, layer)
	local x = proj.drawX
	local y = proj.drawY

	if x == nil then
		return
	end

	if layer == 1 then
		gui.drawbox(x-3, y-3, x+3, y+3, '#000000', '#000000')
	end

	if layer == 2 then
		DrawDirection(x, y, proj.drawDir, 5)
	end

	if layer == 3 then
		gui.setpixel(x, y, proj.color)
		gui.drawline(x-3, y, x-4, y, proj.color)
		gui.drawline(x+3, y, x+4, y, proj.color)
		gui.drawline(x, y-3, x, y-4, proj.color)
		gui.drawline(x, y+3, x, y+4, proj.color)
	end
end

local PROJECTILE_OFFSETS =
{
	-- Round 3 is hard-coded global
	[633] =		{{ 5,	9,	-4 }},	-- 5-9 orb bullet
	[686] =	{
			{ 2,	9,	-4 },	-- 2-9 mage fireball
			{ 5,	3,	-4 },	-- 5-3 orb bullet
		},
	[691] =		{{ 2,	8,	-4 }},	-- 2-8 mage fireball
	[692] =		{{ 2,	10,	-4 }},	-- 2-10 mage fireball
	[714] =		{{ 5,	2,	-4 }},	-- 5-2 tank bullet
	[765] =		{{ 5,	4,	-4 }},	-- 5-4 spider bullet
	[796] =		{{ 5,	10,	-4 }},	-- 5-10 boss bullet
	[832] =		{{ 2,	3,	 4 }},	-- 2-3 rod
	[836] =		{{ 5,	5,	-4 }},	-- 5-5 orb bullet
	[861] =		{{ 2,	5,	-4 }},	-- 2-5 moat monster attack
	[864] =		{{ 2,	7,	-4 }},	-- 2-7 mage fireball
	[916] =		{{ 4,	4,	 4 }},	-- 4-4 nunchuck
	[967] =		{{ 4,	3,	 4 }},	-- 4-3 nunchuck
	[972] =		{{ 1,	6,	 4 }},	-- 1-6 rod
	[1019] =	{{ 1,	10,	-4 }},	-- 1-10 Demon turret fireball
	[1040] =	{{ 4,	5,	 4 }},	-- 4-5 nunchuck
	[1051] =	{{ 4,	8,	 4 }},	-- 4-8 nunchuck
}

local function drawProjectile(proj)
	local realX = memory.readbyte(proj.xAddr) * 256 + memory.readbyte(proj.xAddr+1)
	local realY = memory.readbyte(proj.yAddr) * 256 + memory.readbyte(proj.yAddr+1)
	local x,y = ToScreenCoords(realX, realY)

	local projOffset = 0

	local projType = memory.readbyte(proj.projType)*256 + memory.readbyte(proj.projType+1)

	local dir = memory.readbyte(proj.direction)

	if PROJECTILE_OFFSETS[projType] then
		for _,poi in ipairs(PROJECTILE_OFFSETS[projType]) do
			if stageInfo.round == poi[1] and stageInfo.stage == poi[2] then
				projOffset = poi[3]
			end
		end
	elseif (stageInfo.round == 4 or stageInfo.round == 3) and not proj.isPlayerAttack then
		projOffset = -4	-- Everything in round 3 and 4 is -4
	end

	local projMode = memory.readbyte(proj.projMode)

	if projMode == 0 then
		proj.drawX = nil
		proj.drawY = nil
		return	-- Inactive
	end

	local ttl = memory.readbyte(proj.lifeRemaining)*256 + memory.readbyte(proj.lifeRemaining+1)
	local ttlDec = memory.readbyte(proj.lifeDecSpeed)*256 + memory.readbyte(proj.lifeDecSpeed+1)

	if ttlDec ~= 0 then
		local timeLeft = math.floor(ttl/ttlDec)
		--gui.drawtext(x, y-15, "TTL:"..timeLeft.." T:"..projType)
	end



	x = x + projOffset
	y = y + projOffset

	proj.drawX = x
	proj.drawY = y
	proj.drawDir = dir
end

local function drawPlayer(player)
	local x = memory.readbyte(player.xAddr) * 256 + memory.readbyte(player.xAddr+1)
	local y = memory.readbyte(player.yAddr) * 256 + memory.readbyte(player.yAddr+1)

	local x = memory.readbyte(player.xAddr) * 256 + memory.readbyte(player.xAddr+1)
	local y = memory.readbyte(player.yAddr) * 256 + memory.readbyte(player.yAddr+1)
	x,y = ToScreenCoords(x,y)

	gui.drawbox(x, y, x+16, y+16, '#00000000', '#00ff007f')
end

local function drawSprite(unit)
	local x = memory.readbyte(unit.xAddr) * 256 + memory.readbyte(unit.xAddr+1)
	local y = memory.readbyte(unit.yAddr) * 256 + memory.readbyte(unit.yAddr+1)
	x,y = ToScreenCoords(x,y)
	--gui.drawbox(x, y, x+15, x+15, nil, '#00ff00')

	local spriteWidth = PLAYER_BOX_SIZE
	local spriteHeight = PLAYER_BOX_SIZE

	local borderColor = '#ff00007f'

	if unit.pxWidth then
		spriteWidth = memory.readbyte(unit.pxWidth)
	end
	if unit.pxHeight then
		spriteHeight = memory.readbyte(unit.pxHeight)
	end

	if unit.hp then
		local hp = memory.readbytesigned(unit.hp)
		if hp <= 0 then
			return	-- Don't draw dead sprites
		end

		gui.drawtext(x+spriteWidth+2, y, "HP:"..hp)
		--gui.drawtext(x, y-9, string.sub(ToHex(unit.baseAddress), 4, 6))
	end

	if unit.stateCounter then
		local sc = memory.readbyte(unit.stateCounter)
		if sc ~= 0 and sc ~= unit.lastSC then
			gui.drawtext(x+spriteWidth+2, y+6, 'TNA:'..sc)
			unit.lastSC = sc
		end
	end

	if unit.direction then
		local dir = memory.readbyte(unit.direction)

		local dv = directionVectors[dir]

		DrawDirection(x+spriteWidth/2, y+spriteWidth/2, dir, spriteWidth)
	end

	local aiState1 = 0
	local aiState2 = 0
	local aiTimer = 0
	local actionTimer = 0
	local overallState = 0
	local subState = 0
	local unitType = 0
	local typeGuess = 0
	local aiType = nil

	if unit.aiState1 then
		aiState1 = memory.readbyte(unit.aiState1)
	end
	if unit.aiState2 then
		aiState2 = memory.readbyte(unit.aiState2)
	end
	if unit.aiTimer then
		aiTimer = memory.readbyte(unit.aiTimer) * 256 + memory.readbyte(unit.aiTimer+1)
	end
	if unit.typeGuess then
		typeGuess = memory.readbyte(unit.typeGuess)
	end
	if unit.unitType then
		unitType = memory.readbyte(unit.unitType)
	end

	if unit.aiType then
		aiType = GuessUnitType(unit)
	end
	--gui.drawtext(x, y+spriteHeight+2, 'AI1:'..aiState1, nil, borderColor)
	--gui.drawtext(x, y+spriteHeight+8, 'AI2:'..aiState2, nil, borderColor)
	--gui.drawtext(x, y+spriteHeight+8, unitType.."-"..aiType, '#ffff00')
	if aiType then
		gui.drawtext(x, y+spriteHeight+2, aiType, unit.coloration)
	end

	-- Display timers
	--gui.drawtext(x, y+spriteHeight+14, 'AI:'..aiState1.."-"..aiState2, '#4f4fff', '#000000')
	if aiState1 == 8 then
		-- Enemy is in a phased state.  This only increments when the level's tick counter is even and ends at 12, so estimate the phase frames remaining
		gui.drawtext(x, y+spriteHeight+8, 'Phase:'..(12-aiTimer), '#7f7f7f', '#000000')
	elseif aiState2 == 2 then
		gui.drawtext(x, y+spriteHeight+8, 'Stun:'..aiTimer, '#4f4fff', '#000000')
	elseif (aiType == "Mage" or aiType == "Burw") and aiTimer ~= 0 and aiState2 == 4 then
		gui.drawtext(x, y+spriteHeight+8, 'Hide:'..aiTimer, nil, '#ff00004f')
	end

	if unit.actionTimer then
		actionTimer = memory.readbytesigned(unit.actionTimer) * 256 + memory.readbyte(unit.actionTimer+1)
		if actionTimer ~= unit.lastActionTimer then
			gui.drawtext(x+spriteWidth+2, y+12, 'Act:'..actionTimer, nil, '#ff00004f')
			unit.lastActionTimer = actionTimer
		end
	end
	if unit.overallState then
		overallState = memory.readbyte(unit.overallState)
	end
	if unit.subState then
		subState = memory.readbyte(unit.subState)
	end
	--gui.drawtext(x, y+spriteHeight+26, 'OS:'..overallState.."-"..subState, nil, borderColor)

	gui.drawbox(x, y, x+spriteWidth, y+spriteHeight, '#00000000', borderColor)
end

gens.registerafter(function()
	stageInfo.round = memory.readbyte(roundAddress)
	stageInfo.stage = memory.readbyte(stageAddress)

	if stageInfo.round == 0 then
		stageInfo.round = 1	-- Weird
	end

	stageInfo.globalTime = memory.readbyte(globalTimeAddress)*16777216 + memory.readbyte(globalTimeAddress+1)*65536 + memory.readbyte(globalTimeAddress+2)*256 + memory.readbyte(globalTimeAddress+3)
	stageInfo.secondsLeft = memory.readbyte(timerAddress)
	stageInfo.secondTicksLeft = memory.readbyte(timerAddress+1)



	for _,proj in ipairs(projectiles) do
		drawProjectile(proj)
	end

	for _,unit in ipairs(enemyUnits) do
		drawSprite(unit)
	end

	-- Draw important hitboxes last
	for layer=1,3 do
		for _,proj in ipairs(projectiles) do
			drawProjectileBox(proj, layer)
		end
	end

	drawPlayer(player1)
	drawPlayer(player2)

	gui.drawbox(0, 0, 35, 7, '#000000ff', '#000000ff')
	gui.drawtext(0, 0, 'VF:'..gens.framecount() - BASE_FRAME)
end)
