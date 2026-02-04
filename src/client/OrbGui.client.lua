local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local OrbConfig = require(Shared:WaitForChild("OrbConfig"))
local OrbConstants = require(Shared:WaitForChild("OrbConstants"))
local Network = require(Shared:WaitForChild("lib"):WaitForChild("Network"))
local Promise = require(Shared:WaitForChild("lib"):WaitForChild("Promise"))
local Signal = require(Shared:WaitForChild("lib"):WaitForChild("Signal"))
local Rodux = require(Shared:WaitForChild("vendor"):WaitForChild("Rodux"))

local player = Players.LocalPlayer

local snapshotEvent = Network.getRemoteEvent(OrbConstants.RemoteEvents.OrbsSnapshot)
local deltaEvent = Network.getRemoteEvent(OrbConstants.RemoteEvents.OrbDelta)
local requestEvent = Network.getRemoteEvent(OrbConstants.RemoteEvents.RequestPickup)
local rejectEvent = Network.getRemoteEvent(OrbConstants.RemoteEvents.PickupRejected)
local energyEvent = Network.getRemoteEvent(OrbConstants.RemoteEvents.EnergyUpdated)

local Actions = {
	SetSnapshot = "SetSnapshot",
	UpdateOrb = "UpdateOrb",
	SetEnergy = "SetEnergy",
	SetPredicted = "SetPredicted",
}

local initialState = {
	energy = 0,
	orbs = {},
	predicted = {},
}

local reducer = Rodux.createReducer(initialState, {
	[Actions.SetSnapshot] = function(_, action)
		return {
			energy = action.energy,
			orbs = action.orbs,
			predicted = {},
		}
	end,
	[Actions.UpdateOrb] = function(state, action)
		local newOrbs = {}
		for key, value in pairs(state.orbs) do
			newOrbs[key] = value
		end
		newOrbs[action.orbId] = {
			angleOffset = action.angleOffset,
			available = action.available,
		}

		local newPredicted = {}
		for key, value in pairs(state.predicted) do
			newPredicted[key] = value
		end
		if action.available then
			newPredicted[action.orbId] = nil
		end

		return {
			energy = state.energy,
			orbs = newOrbs,
			predicted = newPredicted,
		}
	end,
	[Actions.SetEnergy] = function(state, action)
		return {
			energy = action.energy,
			orbs = state.orbs,
			predicted = state.predicted,
		}
	end,
	[Actions.SetPredicted] = function(state, action)
		local newPredicted = {}
		for key, value in pairs(state.predicted) do
			newPredicted[key] = value
		end

		if action.isPredicted then
			newPredicted[action.orbId] = true
		else
			newPredicted[action.orbId] = nil
		end

		return {
			energy = state.energy,
			orbs = state.orbs,
			predicted = newPredicted,
		}
	end,
})

local store = Rodux.Store.new(reducer)

local visualsFolder = Instance.new("Folder")
visualsFolder.Name = "EnergyOrbVisuals"
visualsFolder.Parent = Workspace

local orbParts = {}
local pendingRequests = {}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EnergyHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Name = "EnergyContainer"
container.Size = UDim2.new(0, 260, 0, 64)
container.Position = UDim2.new(0, 20, 0, 20)
container.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
container.BackgroundTransparency = 0.2
container.BorderSizePixel = 0
container.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = container

local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(0, 170, 255)
stroke.Transparency = 0.3
stroke.Parent = container

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -20, 0, 20)
title.Position = UDim2.new(0, 10, 0, 6)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(221, 245, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Energy Orbit"
title.Parent = container

local valueLabel = Instance.new("TextLabel")
valueLabel.BackgroundTransparency = 1
valueLabel.Size = UDim2.new(1, -20, 0, 24)
valueLabel.Position = UDim2.new(0, 10, 0, 26)
valueLabel.Font = Enum.Font.GothamSemibold
valueLabel.TextSize = 18
valueLabel.TextColor3 = Color3.fromRGB(0, 200, 255)
valueLabel.TextXAlignment = Enum.TextXAlignment.Left
valueLabel.Text = "Energy: 0"
valueLabel.Parent = container

local flash = Instance.new("Frame")
flash.Size = UDim2.new(1, 0, 1, 0)
flash.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
flash.BackgroundTransparency = 1
flash.ZIndex = 2
flash.Parent = container

local function updateHud(newEnergy, delta)
	if delta then
		valueLabel.Text = string.format("Energy: %d (+%d)", newEnergy, delta)
	else
		valueLabel.Text = string.format("Energy: %d", newEnergy)
	end

	flash.BackgroundTransparency = 0.6
	flash.Size = UDim2.new(1, 0, 1, 0)

	local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(flash, tweenInfo, {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 30, 1, 10),
	})

	tween:Play()
end

local function ensureOrbPart(orbId)
	if orbParts[orbId] then
		return orbParts[orbId]
	end

	local orb = Instance.new("Part")
	orb.Name = string.format("EnergyOrb_%02d", orbId)
	orb.Shape = Enum.PartType.Ball
	orb.Anchored = true
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(0, 170, 255)
	orb.Size = OrbConfig.OrbSize
	orb.CanCollide = false
	orb.Parent = visualsFolder

	orbParts[orbId] = orb
	return orb
end

local function computeOrbPosition(angleOffset, now)
	local angle = angleOffset + (now * OrbConfig.RotationSpeed)
	local bob = math.sin((now * OrbConfig.BobSpeed) + angleOffset) * OrbConfig.BobAmplitude
	return OrbConfig.CenterOffset + Vector3.new(
		math.cos(angle) * OrbConfig.OrbRadius,
		OrbConfig.OrbHeight + bob,
		math.sin(angle) * OrbConfig.OrbRadius
	)
end

local function updateVisuals(now)
	local state = store:getState()
	for orbId, orbState in pairs(state.orbs) do
		local orb = ensureOrbPart(orbId)
		local isPredicted = state.predicted[orbId]
		orb.Transparency = (orbState.available and not isPredicted) and 0 or 1
		orb.Position = computeOrbPosition(orbState.angleOffset, now)
	end
end

local function handleProximity(now)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local state = store:getState()
	for orbId, orbState in pairs(state.orbs) do
		if orbState.available and not pendingRequests[orbId] then
			local position = computeOrbPosition(orbState.angleOffset, now)
			if (root.Position - position).Magnitude <= OrbConfig.PickupRadius then
				pendingRequests[orbId] = true
				store:dispatch({
					type = Actions.SetPredicted,
					orbId = orbId,
					isPredicted = true,
				})
				requestEvent:FireServer(orbId)
			end
		end
	end
end

local snapshotSignal = Signal.new()

snapshotEvent.OnClientEvent:Connect(function(payload)
	snapshotSignal:Fire(payload)
end)

deltaEvent.OnClientEvent:Connect(function(orbId, available)
	local current = store:getState().orbs[orbId]
	store:dispatch({
		type = Actions.UpdateOrb,
		orbId = orbId,
		angleOffset = current and current.angleOffset or 0,
		available = available,
	})
	if available then
		pendingRequests[orbId] = nil
	end
end)

rejectEvent.OnClientEvent:Connect(function(orbId)
	pendingRequests[orbId] = nil
	local current = store:getState().orbs[orbId]
	if current then
		store:dispatch({
			type = Actions.UpdateOrb,
			orbId = orbId,
			angleOffset = current.angleOffset,
			available = true,
		})
	end
end)

energyEvent.OnClientEvent:Connect(function(newEnergy, delta)
	store:dispatch({
		type = Actions.SetEnergy,
		energy = newEnergy,
	})
	updateHud(newEnergy, delta)
end)

Promise.new(function(resolve)
	snapshotSignal:Once(resolve)
end):andThen(function(payload)
	store:dispatch({
		type = Actions.SetSnapshot,
		energy = payload.energy or (player:GetAttribute("Energy") or 0),
		orbs = payload.orbs,
	})
	updateHud(store:getState().energy)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		updateVisuals(now)
		handleProximity(now)
	end)
end)
