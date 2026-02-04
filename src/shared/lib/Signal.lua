local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_connections = {},
	}, Signal)
end

function Signal:Connect(callback)
	local connection = {
		Connected = true,
		_disconnect = function() end,
	}

	local function disconnect()
		if not connection.Connected then
			return
		end
		connection.Connected = false
		self._connections[connection] = nil
	end

	connection._disconnect = disconnect
	self._connections[connection] = callback

	return {
		Disconnect = disconnect,
	}
end

function Signal:Once(callback)
	local connection
	connection = self:Connect(function(...)
		if connection then
			connection:Disconnect()
		end
		callback(...)
	end)
	return connection
end

function Signal:Fire(...)
	for connection, callback in pairs(self._connections) do
		if connection.Connected then
			callback(...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		coroutine.resume(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Destroy()
	for connection in pairs(self._connections) do
		connection.Connected = false
	end
	self._connections = {}
end

return Signal
