local Thread = {}

function Thread.spawn(callback, ...)
	return task.spawn(callback, ...)
end

function Thread.delay(seconds, callback, ...)
	return task.delay(seconds, callback, ...)
end

function Thread.defer(callback, ...)
	return task.defer(callback, ...)
end

function Thread.cancel(thread)
	if thread then
		task.cancel(thread)
	end
end

return Thread
