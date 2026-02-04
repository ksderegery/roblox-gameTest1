local Promise = {}
Promise.__index = Promise

local STATUS = {
	Pending = "Pending",
	Resolved = "Resolved",
	Rejected = "Rejected",
}

function Promise.new(executor)
	local self = setmetatable({
		_status = STATUS.Pending,
		_value = nil,
		_reason = nil,
		_onResolved = {},
		_onRejected = {},
	}, Promise)

	local function resolve(value)
		if self._status ~= STATUS.Pending then
			return
		end
		self._status = STATUS.Resolved
		self._value = value
		for _, callback in ipairs(self._onResolved) do
			callback(value)
		end
	end

	local function reject(reason)
		if self._status ~= STATUS.Pending then
			return
		end
		self._status = STATUS.Rejected
		self._reason = reason
		for _, callback in ipairs(self._onRejected) do
			callback(reason)
		end
	end

	task.spawn(function()
		local ok, err = pcall(executor, resolve, reject)
		if not ok then
			reject(err)
		end
	end)

	return self
end

function Promise.resolve(value)
	return Promise.new(function(resolve)
		resolve(value)
	end)
end

function Promise.reject(reason)
	return Promise.new(function(_, reject)
		reject(reason)
	end)
end

function Promise.delay(seconds)
	return Promise.new(function(resolve)
		task.delay(seconds, function()
			resolve(true)
		end)
	end)
end

function Promise:andThen(onResolved, onRejected)
	return Promise.new(function(resolve, reject)
		local function handleResolved(value)
			if onResolved then
				local ok, result = pcall(onResolved, value)
				if ok then
					resolve(result)
				else
					reject(result)
				end
			else
				resolve(value)
			end
		end

		local function handleRejected(reason)
			if onRejected then
				local ok, result = pcall(onRejected, reason)
				if ok then
					resolve(result)
				else
					reject(result)
				end
			else
				reject(reason)
			end
		end

		if self._status == STATUS.Resolved then
			handleResolved(self._value)
		elseif self._status == STATUS.Rejected then
			handleRejected(self._reason)
		else
			table.insert(self._onResolved, handleResolved)
			table.insert(self._onRejected, handleRejected)
		end
	end)
end

function Promise:catch(onRejected)
	return self:andThen(nil, onRejected)
end

function Promise:finally(callback)
	return self:andThen(function(value)
		callback()
		return value
	end, function(reason)
		callback()
		return Promise.reject(reason)
	end)
end

function Promise:await()
	if self._status == STATUS.Resolved then
		return true, self._value
	elseif self._status == STATUS.Rejected then
		return false, self._reason
	end

	local thread = coroutine.running()
	self:andThen(function(value)
		coroutine.resume(thread, true, value)
	end, function(reason)
		coroutine.resume(thread, false, reason)
	end)

	return coroutine.yield()
end

return Promise
