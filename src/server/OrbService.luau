local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local OrbConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OrbConfig"))

local OrbService = {}

local ORB_FOLDER_NAME = "EnergyOrbs"
local REMOTE_NAME = "OrbCollected"

local orbFolder
local orbCollectedEvent
local orbStates = {}
local heartbeatConnection

local function getPlayerFromHit(hit)
	if not hit or not hit.Parent then
		return nil
	end

	local character = hit:FindFirstAncestorOfClass("Model")	
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function setOrbActive(orb, isActive)
	orb:SetAttribute("Active", isActive)
	orb.Transparency = isActive and 0 or 1
	orb.CanCollide = false
end

local function updateEnergy(player, amount)
	local current = player:GetAttribute("Energy") or 0
	local newValue = current + amount
	player:SetAttribute("Energy", newValue)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local energyStat = leaderstats:FindFirstChild("Energy")
		if energyStat then
			energyStat.Value = newValue
		end
	end

	return newValue
end

local function updateOrbPositions()
	local now = time()
	for _, orbState in ipairs(orbStates) do
		local orb = orbState.orb
		if orb.Parent then
			local angle = orbState.angleOffset + (now * OrbConfig.RotationSpeed)
			local bob = math.sin((now * OrbConfig.BobSpeed) + orbState.angleOffset) * OrbConfig.BobAmplitude
			local offset = Vector3.new(
				math.cos(angle) * OrbConfig.OrbRadius,
				OrbConfig.OrbHeight + bob,
				math.sin(angle) * OrbConfig.OrbRadius
			)
			orb.Position = OrbConfig.CenterOffset + offset
		end
	end
end

local function spawnOrb(index)
	local orb = Instance.new("Part")
	orb.Name = string.format("EnergyOrb_%02d", index)
	orb.Shape = Enum.PartType.Ball
	orb.Anchored = true
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(0, 170, 255)
	orb.Size = OrbConfig.OrbSize
	orb.CanCollide = false

	local angle = (index / OrbConfig.OrbCount) * math.pi * 2
	orb.Position = OrbConfig.CenterOffset + Vector3.new(
		math.cos(angle) * OrbConfig.OrbRadius,
		OrbConfig.OrbHeight,
		math.sin(angle) * OrbConfig.OrbRadius
	)
	table.insert(orbStates, {
		orb = orb,
		angleOffset = angle,
	})

	setOrbActive(orb, true)
	orb.Parent = orbFolder

	orb.Touched:Connect(function(hit)
		if not orb:GetAttribute("Active") then
			return
		end

		local player = getPlayerFromHit(hit)
		if not player then
			return
		end

		setOrbActive(orb, false)
		local newEnergy = updateEnergy(player, OrbConfig.EnergyPerOrb)
		if orbCollectedEvent then
			orbCollectedEvent:FireClient(player, newEnergy, OrbConfig.EnergyPerOrb)
		end

		task.delay(OrbConfig.RespawnSeconds, function()
			if orb.Parent then
				setOrbActive(orb, true)
			end
		end)
	end)
end

local function setupLeaderstats(player)
	player:SetAttribute("Energy", 0)

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local energyStat = Instance.new("IntValue")
	energyStat.Name = "Energy"
	energyStat.Value = 0
	energyStat.Parent = leaderstats
end

function OrbService.start()
	orbFolder = Workspace:FindFirstChild(ORB_FOLDER_NAME)
	if not orbFolder then
		orbFolder = Instance.new("Folder")
		orbFolder.Name = ORB_FOLDER_NAME
		orbFolder.Parent = Workspace
	end

	orbCollectedEvent = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if not orbCollectedEvent then
		orbCollectedEvent = Instance.new("RemoteEvent")
		orbCollectedEvent.Name = REMOTE_NAME
		orbCollectedEvent.Parent = ReplicatedStorage
	end

	Players.PlayerAdded:Connect(setupLeaderstats)
	for _, player in Players:GetPlayers() do
		setupLeaderstats(player)
	end

	for index = 1, OrbConfig.OrbCount do
		spawnOrb(index)
	end

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
	end
	heartbeatConnection = RunService.Heartbeat:Connect(updateOrbPositions)
end

return OrbService
