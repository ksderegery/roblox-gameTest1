local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Network = {}

local REMOTES_FOLDER_NAME = "Remotes"

local function getRemotesFolder()
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not folder then
		if RunService:IsServer() then
			folder = Instance.new("Folder")
			folder.Name = REMOTES_FOLDER_NAME
			folder.Parent = ReplicatedStorage
		else
			folder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
		end
	end
	return folder
end

function Network.getRemoteEvent(name)
	local folder = getRemotesFolder()
	local remote = folder:FindFirstChild(name)
	if not remote then
		if RunService:IsServer() then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		else
			remote = folder:WaitForChild(name)
		end
	end
	return remote
end

return Network
