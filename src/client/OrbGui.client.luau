local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("OrbCollected")

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

local function updateValue(newEnergy, delta)
	valueLabel.Text = string.format("Energy: %d (+%d)", newEnergy, delta)
	flash.BackgroundTransparency = 0.6
	flash.Size = UDim2.new(1, 0, 1, 0)

	local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(flash, tweenInfo, {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 30, 1, 10),
	})
	
	tween:Play()
end

remote.OnClientEvent:Connect(updateValue)
