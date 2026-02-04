local Rodux = {}

local function copyTable(input)
	local result = {}
	for key, value in pairs(input) do
		result[key] = value
	end
	return result
end

function Rodux.combineReducers(reducers)
	return function(state, action)
		state = state or {}
		local newState = {}
		for key, reducer in pairs(reducers) do
			newState[key] = reducer(state[key], action)
		end
		return newState
	end
end

function Rodux.createReducer(initialState, handlers)
	return function(state, action)
		state = state or initialState
		local handler = handlers[action.type]
		if handler then
			return handler(state, action)
		end
		return state
	end
end

local Store = {}
Store.__index = Store

function Store.new(reducer, initialState)
	local self = setmetatable({
		_reducer = reducer,
		_state = initialState or reducer(nil, { type = "@@INIT" }),
		_listeners = {},
	}, Store)
	return self
end

function Store:getState()
	return self._state
end

function Store:dispatch(action)
	self._state = self._reducer(self._state, action)
	for _, listener in ipairs(self._listeners) do
		listener(self._state, action)
	end
	return action
end

function Store:subscribe(listener)
	table.insert(self._listeners, listener)
	local index = #self._listeners
	return function()
		table.remove(self._listeners, index)
	end
end

Rodux.Store = Store

return Rodux
