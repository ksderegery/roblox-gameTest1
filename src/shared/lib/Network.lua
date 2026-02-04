--[[
	

	-- Server API
	
	Network:BindFunctions(functions) 
	Network:BindEvents(events)
	Network:FireClient(client,name,params)
	Network:FireAllClients(name,params)
	Network:FireOtherClients(ignoreclient,name,params)
	Network:FireOtherClientsWithinDistance(ignoreclient,name,distance,params)
	Network:FireAllClientsWithinDistance(name,distance,position,params)
	Network:LogTraffic(duration)
	
	
	
	-- Client API
	
	Network:BindEvents(events) 
	Network:FireServer(name,params)
	Network:InvokeServer(name,params)



--]]



local module = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")


local EventHandlers = {}
local FunctionHandlers = {}

local IsStudio = RunService:IsStudio()
local IsServer = RunService:IsServer()
local LoggingNetwork

local Communication
local EventsFolder
local FunctionsFolder

local SpawnBindable = Instance.new("BindableEvent")
local function Spawn(fn, ...)
	coroutine.wrap(function(...)
		SpawnBindable.Event:Wait()
		fn(...)
	end)(...)

	SpawnBindable:Fire()
end

if IsServer then
	Communication = Instance.new("Folder")
	Communication.Name = "Communication"
	Communication.Parent = ReplicatedStorage

	EventsFolder = Instance.new("Folder")
	EventsFolder.Name="Events"
	EventsFolder.Parent = Communication

	FunctionsFolder = Instance.new("Folder")
	FunctionsFolder.Name="Functions"
	FunctionsFolder.Parent = Communication
else
	Communication = ReplicatedStorage:WaitForChild("Communication")
	EventsFolder = Communication:WaitForChild("Events")
	FunctionsFolder = Communication:WaitForChild("Functions")
end

local function GetEventHandler(name)
	local handler = EventHandlers[name]
	if handler then
		return handler
	end

	local handler = {
		Name = name,
		Folder = EventsFolder
	}

	EventHandlers[name] = handler

	if IsServer then
		local remote = Instance.new("RemoteEvent")
		remote.Name = handler.Name
		remote.Parent = handler.Folder

		handler.Remote = remote
	else
		handler.Remote = handler.Folder:FindFirstChild(name)

		if not handler.Remote then
			handler.Queue = {}

			local addCon
			addCon = handler.Folder.ChildAdded:Connect(function(child)
				if child.Name ~= name then
					return
				end

				addCon:Disconnect()
				handler.Remote = child

				child.Name = ""

				for _,fn in pairs(handler.Queue) do
					fn()
				end 

				handler.Queue = nil
			end)
		else
			handler.Remote.Name = ""
		end
	end

	return handler
end

function GetFunctionHandler(name)
	local handler = FunctionHandlers[name]
	if handler then
		return handler
	end

	local handler = {
		Name = name,
		Folder = FunctionsFolder
	}

	FunctionHandlers[name] = handler

	if IsServer then
		local remote = Instance.new("RemoteEvent")
		remote.Name = handler.Name
		remote.Parent = handler.Folder

		local response = Instance.new("RemoteEvent")
		response.Name = "Response"
		response.Parent = remote

		handler.Remote = remote
		handler.ResponseRemote = response
	else
		Spawn(function()
			handler.Queue = {}

			local remote = handler.Folder:WaitForChild(name)
			local response = remote:WaitForChild("Response")

			handler.Remote = handler.Folder:FindFirstChild(name)
			handler.ResponseRemote = handler.Remote and handler.Remote:FindFirstChild("Response")

			handler.Remote.Name = ""

			for _,fn in pairs(handler.Queue) do
				fn()
			end

			handler.Queue = nil
		end)
	end

	return handler
end

function AddToQueue(handler, fn, doWarn)
	if handler.Remote then
		return fn()
	end

	handler.Queue[#handler.Queue + 1] = fn

	if doWarn then
		delay(5, function()
			if not handler.Remote then
				warn(debug.traceback(("Infinite yield possible on '%s:WaitForChild(\"%s\")'"):format(handler.Folder:GetFullName(), handler.Name)))
			end
		end)
	end
end


local function checkParams(name, paramTypes)
	paramTypes = { unpack(paramTypes) }
	local paramStart = 1

	for i,v in pairs(paramTypes) do
		local dict = {}

		local list = type(v) == "string" and {v} or v
		dict._string = table.concat(list, " or ")

		for i,v in pairs(list) do
			dict[v] = true
		end

		paramTypes[i] = dict
	end

	if IsServer then
		paramStart = 2
		table.insert(paramTypes, 1, false)
	end

	return function(fn, ...)
		local args = { n = select("#", ...), ... }

		if args.n > #paramTypes then
			if IsStudio then
				warn(("[Network] Invalid number of parameters to %s (%d expected, got %d)"):format(name, #paramTypes, args.n))
			end
			return
		end

		for i = paramStart, #paramTypes do
			local argType = typeof(args[i])
			local argExpected = paramTypes[i]

			if not argExpected[argType] and not argExpected.any then
				if IsStudio then
					warn(("[Network] Invalid parameter %d to %s (%s expected, got %s)"):format(i, name, argExpected._string, argType))
				end
				return
			end
		end

		return fn(...)
	end
end

local function combineFn(handler, fn, pre)
	local fnList = { pre }

	if typeof(fn) == "table" then
		local info = fn
		fn = fn[1]

		if info.MatchParams then
			table.insert(fnList, checkParams(handler.Name, info.MatchParams))
		end
	end

	table.insert(fnList, fn)

	local function NetworkHandler(...)
		if LoggingNetwork then
			LoggingNetwork[#LoggingNetwork + 1] = { true, handler.Remote, ... }
		end

		local index = 0

		local function runMiddleware(...)
			index = index + 1

			if index < #fnList then
				return fnList[index](runMiddleware, ...)
			end

			return fnList[index](...)
		end

		return runMiddleware(...)
	end

	return NetworkHandler
end

function BindEvent(name, fn, pre)
	local handler = GetEventHandler(name)
	if not handler then
		error(("Tried to bind callback to non-existing RemoteEvent %q"):format(name))
	end

	fn = combineFn(handler, fn, pre)

	if RunService:IsServer() then
		handler.Remote.OnServerEvent:Connect(fn)		
	else
		if handler.Remote then
			handler.Remote.OnClientEvent:Connect(fn)
		else
			AddToQueue(handler, function()
				handler.Remote.OnClientEvent:Connect(fn)
			end)
		end
	end
end

function BindFunction(name, fn, pre)
	assert(IsServer)

	local handler = GetFunctionHandler(name)
	if not handler then
		error(("Tried to bind callback to non-existing RemoteFunction %q"):format(name))
	end

	if handler.IsSet then
		error(("Tried to bind multiple callbacks to the same RemoteFunction (%s)"):format(handler.Remote:GetFullName()))
	end

	handler.IsSet = true
	fn = combineFn(handler, fn, pre)

	handler.Remote.OnServerEvent:Connect(function(client, respId, ...)
		local done = false
		local thread

		Spawn(function(...)
			thread = coroutine.running()
			pcall(function(...) handler.ResponseRemote:FireClient(client, respId, true, ...) end, fn(client, ...))
			done = true
		end, ...)

		while not done and client:IsDescendantOf(game) do
			wait(0.5)
		end

		if done or not client:IsDescendantOf(game) then
			return
		end

		handler.ResponseRemote:FireClient(client, respId, false)
	end)
end



function module:BindEvents(pre, callbacks)
	if typeof(pre) == "table" then
		pre, callbacks = nil, pre
	end

	for i,v in pairs(callbacks) do
		BindEvent(i, v, pre)
	end
end



local ReferenceTypes = {
	Character = {},
	CharacterPart = {}
}

local References = {} 
local Objects = {}

for i,v in pairs(ReferenceTypes) do
	References[i] = {}
	Objects[i] = {}
end

function module:AddReference(key, refType, ...)
	local refInfo = ReferenceTypes[refType]
	assert(refInfo, "Invalid Reference Type")

	local refData = {
		Type = refType,
		Reference = key,
		Objects = {...},
		Aliases = {}
	}

	References[refType][refData.Reference] = refData

	local last = Objects[refType]
	for _,obj in ipairs(refData.Objects) do
		local list = last[obj] or {}
		last[obj] = list
		last = list
	end

	last.__Data = refData
end

function module:AddReferenceAlias(key, refType, ...)
	local refInfo = ReferenceTypes[refType]
	assert(refInfo, "Invalid Reference Type")

	local refData = References[refType][key]
	if not refData then
		warn("Tried to add an alias to a non-existing reference")
		return
	end

	local objects = {...}
	refData.Aliases[#refData.Aliases + 1] = objects

	local last = Objects[refType]
	for _,obj in ipairs(objects) do
		local list = last[obj] or {}
		last[obj] = list
		last = list
	end

	last.__Data = refData
end

function module:RemoveReference(key, refType)
	local refInfo = ReferenceTypes[refType]
	assert(refInfo, "Invalid Reference Type")

	local refData = References[refType][key]
	if not refData then
		warn("Tried to remove a non-existing reference")
		return
	end

	References[refType][refData.Reference] = nil

	local function rem(parent, objects, index)
		if index <= #objects then
			local key = objects[index]
			local child = parent[key]

			rem(child, objects, index + 1)

			if next(child) == nil then
				parent[key] = nil
			end
		elseif parent.__Data == refData then
			parent.__Data = nil
		end
	end

	local objects = Objects[refData.Type]
	rem(objects, refData.Objects, 1)

	for i,alias in ipairs(refData.Aliases) do
		rem(objects, alias, 1)
	end
end

function module:GetObject(ref, refType)
	assert(ReferenceTypes[refType], "Invalid Reference Type")

	local refData = References[refType][ref]
	if not refData then
		return nil
	end

	return unpack(refData.Objects)
end

function module:GetReference(...)
	local objects = {...}

	local refType = table.remove(objects)
	assert(ReferenceTypes[refType], "Invalid Reference Type")

	local last = Objects[refType]
	for i,v in ipairs(objects) do
		last = last[v]

		if not last then
			break
		end
	end

	local refData = last and last.__Data
	return refData and refData.Reference or nil
end

--

if RunService:IsServer() then
	function module:BindFunctions(pre, callbacks)
		if typeof(pre) == "table" then
			pre, callbacks = nil, pre
		end

		for i,v in pairs(callbacks) do
			BindFunction(i, v, pre)
		end
	end

	function module:GetPlayers()
		return Players:GetPlayers()
	end

	function module:FireClient(client, name, ...)
		local handler = GetEventHandler(name)
		if not handler then
			error(("'%s' is not a valid RemoteEvent"):format(name))
		end

		if LoggingNetwork then
			LoggingNetwork[#LoggingNetwork + 1] = { false, handler.Remote, client, ... }
		end
		return handler.Remote:FireClient(client, ...)
	end

	function module:FireAllClients(name, ...)
		local handler = GetEventHandler(name)
		if not handler then
			error(("'%s' is not a valid RemoteEvent"):format(name))
		end

		for i,v in pairs(self:GetPlayers()) do
			if LoggingNetwork then
				LoggingNetwork[#LoggingNetwork + 1] = { false, handler.Remote, v, ... }
			end
			handler.Remote:FireClient(v, ...)
		end
	end

	function module:FireOtherClients(client, name, ...)
		local handler = GetEventHandler(name)
		if not handler then
			error(("'%s' is not a valid RemoteEvent"):format(name))
		end

		for i,v in pairs(self:GetPlayers()) do
			if v ~= client then
				if LoggingNetwork then
					LoggingNetwork[#LoggingNetwork + 1] = { false, handler.Remote, v, ... }
				end

				handler.Remote:FireClient(v, ...)
			end
		end
	end


	function module:FireOtherClientsWithinDistance(client, name, dist, ...)

		local char = client.Character

		if not char then
			return
		end

		local myroot = char.PrimaryPart
		if not myroot then
			return
		end


		local pos = myroot.Position

		for _,player in pairs(self:GetPlayers()) do
			if player ~= client then
				local playerchar = player.Character
				if playerchar and playerchar.PrimaryPart then
					if (playerchar.PrimaryPart.Position - pos).Magnitude <= dist then
						self:FireClient(player, name, ...)
					end
				end
			end
		end
	end

	function module:FireAllClientsWithinDistance(name,dist,pos,...)

		for _,player in pairs(self:GetPlayers()) do
			local playerchar = player.Character
			if playerchar and playerchar.PrimaryPart then
				if (playerchar.PrimaryPart.Position - pos).Magnitude <= dist then
					self:FireClient(player, name, ...)
				end
			end
		end
	end


else
	local ResponseCounter = 0

	function ToByteArgs(n)
		if n > 255 then
			return math.floor(n / 256), n % 256
		end

		return n
	end

	function ToByteString(n)
		return string.char(ToByteArgs(n))
	end

	function GetResponse(id, event, respId, success, ...)
		if respId ~= id then
			return GetResponse(id, event, event:Wait())
		end

		return ...
	end

	for _,remote in pairs(EventsFolder:GetChildren()) do
		GetEventHandler(remote.Name)
	end

	for _,remote in pairs(FunctionsFolder:GetChildren()) do
		GetFunctionHandler(remote.Name)
	end

	function module:FireServer(name, ...)
		local handler = GetEventHandler(name)
		if not handler then
			error(("'%s' is not a valid RemoteEvent"):format(name))
		end

		if handler.Remote then
			handler.Remote:FireServer(...)
		else
			local args = { n = select("#", ...), ... } 

			AddToQueue(handler, function()
				handler.Remote:FireServer(unpack(args, 1, args.n))
			end, true)
		end
	end

	function module:InvokeServer(name, ...)
		local handler = GetFunctionHandler(name)
		if not handler then
			error(("'%s' is not a valid RemoteFunction"):format(name))
		end

		if not handler.Remote then
			local bindable = Instance.new("BindableEvent")

			AddToQueue(handler, function()
				bindable:Fire()
			end, true)

			bindable.Event:Wait()
		end

		local responseId = ToByteString(ResponseCounter)
		ResponseCounter = (ResponseCounter + 1) % (2 ^ 32)

		handler.Remote:FireServer(responseId, ...)
		return GetResponse(responseId, handler.ResponseRemote.OnClientEvent)
	end
end


function module:LogTraffic(duration)
	if not RunService:IsServer() then
		warn("LogTraffic is server only")
		return
	end

	if LoggingNetwork then return end
	warn("Logging Network Traffic...")

	LoggingNetwork = {}
	local start = tick()

	delay(duration, function()
		local effDur = tick() - start

		local log = LoggingNetwork
		LoggingNetwork = nil

		local clientTraffic = {}

		for i,v in pairs(log) do
			local remote = v[2]
			local player = v[3]

			local playerTraffic = clientTraffic[player]
			if not playerTraffic then
				playerTraffic = { total = 0 }
				clientTraffic[player] = playerTraffic
			end

			local remoteTraffic = playerTraffic[remote]
			if not remoteTraffic then
				remoteTraffic = { dataIn = {}, dataOut = {} }
				playerTraffic[remote] = remoteTraffic
			end

			local target = v[1] and remoteTraffic.dataIn or remoteTraffic.dataOut

			target[#target + 1] = v
			playerTraffic.total = playerTraffic.total + 1
		end

		for player,remotes in pairs(clientTraffic) do
			warn(("Player '%s', total received: %d"):format(player.Name, remotes.total))
			remotes.total = nil

			for remote,data in pairs(remotes) do
				do
					local list = data.dataIn
					if #list > 0 then
						warn(("   %s %s: %d (%.2f/s)"):format("Incoming", remote.Name, #list, #list / effDur))

						for i = 1,math.min(#list, 3) do
							local reqI = math.random(1, #list)
							local params = { unpack(list[reqI], 4, 7) }

							for i = 1, #params do
								params[i] = tostring(params[i])
							end

							warn(("      %d: %s"):format(reqI, table.concat(params, ", ")))
						end
					end
				end
				do
					local list = data.dataOut
					if #list > 0 then
						warn(("   %s %s: %d (%.2f/s)"):format("Outgoing", remote.Name, #list, #list / effDur))

						for i = 1,math.min(#list, 3) do
							local reqI = math.random(1, #list)
							local params = { unpack(list[reqI], 3, 5) }

							for i = 1, #params do
								params[i] = tostring(params[i])
							end

							warn(("      %d: %s"):format(reqI, table.concat(params, ", ")))
						end
					end
				end
			end
		end
	end)
end



return module