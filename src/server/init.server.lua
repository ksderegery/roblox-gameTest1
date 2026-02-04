local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local OrbConfig = require(Shared:WaitForChild("OrbConfig"))
local OrbConstants = require(Shared:WaitForChild("OrbConstants"))
local Network = require(Shared:WaitForChild("lib"):WaitForChild("Network"))
local Promise = require(Shared:WaitForChild("lib"):WaitForChild("Promise"))
local Signal = require(Shared:WaitForChild("lib"):WaitForChild("Signal"))
local Thread = require(Shared:WaitForChild("lib"):WaitForChild("Thread"))

local snapshotEvent = Network.getRemoteEvent(OrbConstants.RemoteEvents.OrbsSnapshot)
local deltaEvent = Network.getRemoteEvent(OrbConstants.RemoteEvents.OrbDelta)
local requestEvent = Network.getRemoteEvent(OrbConstants.RemoteEvents.RequestPickup)
local rejectEvent = Network.getRemoteEvent(OrbConstants.RemoteEvents.PickupRejected)
local energyEvent = Network.getRemoteEvent(OrbConstants.RemoteEvents.EnergyUpdated)

local orbStates = {}
local playerCooldowns = {}
local orbUpdated = Signal.new()

local function getOrbPosition(angleOffset, now)
	local angle = angleOffset + (now * OrbConfig.RotationSpeed)
	local bob = math.sin((now * OrbConfig.BobSpeed) + angleOffset) * OrbConfig.BobAmplitude
	return OrbConfig.CenterOffset + Vector3.new(
		math.cos(angle) * OrbConfig.OrbRadius,
		OrbConfig.OrbHeight + bob,
		math.sin(angle) * OrbConfig.OrbRadius
	)
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

	energyEvent:FireClient(player, newValue, amount)
end

local function sendSnapshot(player)
	local orbsPayload = {}
	for orbId, orbState in pairs(orbStates) do
		orbsPayload[orbId] = {
			angleOffset = orbState.angleOffset,
			available = orbState.available,
		}
	end

	snapshotEvent:FireClient(player, {
		serverTime = os.clock(),
		energy = player:GetAttribute("Energy") or 0,
		orbs = orbsPayload,
		config = {
			OrbCount = OrbConfig.OrbCount,
			OrbRadius = OrbConfig.OrbRadius,
			OrbHeight = OrbConfig.OrbHeight,
			OrbSize = OrbConfig.OrbSize,
			CenterOffset = OrbConfig.CenterOffset,
			RotationSpeed = OrbConfig.RotationSpeed,
			BobAmplitude = OrbConfig.BobAmplitude,
			BobSpeed = OrbConfig.BobSpeed,
			PickupRadius = OrbConfig.PickupRadius,
		},
	})
end

local function buildOrbs()
	orbStates = {}
	for index = 1, OrbConfig.OrbCount do
		local angle = (index / OrbConfig.OrbCount) * math.pi * 2
		orbStates[index] = {
			id = index,
			angleOffset = angle,
			available = true,
		}
	end
end

local function validatePickup(player, orbId)
	local orbState = orbStates[orbId]
	if not orbState then
		return false, "missing"
	end

	if not orbState.available then
		return false, "unavailable"
	end

	local now = os.clock()
	local cooldownAt = playerCooldowns[player]
	if cooldownAt and now - cooldownAt < OrbConfig.PickupCooldown then
		return false, "cooldown"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "no_root"
	end

	local position = getOrbPosition(orbState.angleOffset, now)
	if (root.Position - position).Magnitude > OrbConfig.PickupRadius then
		return false, "distance"
	end

	return true
end

local function onOrbCollected(player, orbId)
	local orbState = orbStates[orbId]
	if not orbState then
		return
	end

	orbState.available = false
	orbUpdated:Fire(orbId, false)
	updateEnergy(player, OrbConfig.EnergyPerOrb)

	Promise.delay(OrbConfig.RespawnSeconds):andThen(function()
		if orbState then
			orbState.available = true
			orbUpdated:Fire(orbId, true)
		end
	end)
end

local function onPickupRequested(player, orbId)
	local ok, reason = validatePickup(player, orbId)
	if not ok then
		rejectEvent:FireClient(player, orbId, reason)
		return
	end

	playerCooldowns[player] = os.clock()
	onOrbCollected(player, orbId)
end

orbUpdated:Connect(function(orbId, available)
	deltaEvent:FireAllClients(orbId, available)
end)

requestEvent.OnServerEvent:Connect(onPickupRequested)

Players.PlayerAdded:Connect(function(player)
	setupLeaderstats(player)
	sendSnapshot(player)
end)

Players.PlayerRemoving:Connect(function(player)
	playerCooldowns[player] = nil
end)

Thread.spawn(function()
	buildOrbs()
	for _, player in ipairs(Players:GetPlayers()) do
		sendSnapshot(player)
	end
end)

print("Energy orb system ready")
