--- @sync entry
--- type-ahead.yazi: prefix-based file jump
---
--- Press a letter/digit → jump to first file starting with that prefix.
--- Press the same letter again → cycle to the next match for current prefix.
--- Press a different letter → extend the prefix and jump to first match.
--- If extended prefix has no match → fall back to the new letter as a fresh prefix.

local state = { prefix = "", last_char = nil, last_idx = nil }

local function find_match(files, n, prefix, start)
	for offset = 0, n - 1 do
		local idx = (start + offset) % n
		if files[idx + 1].name:lower():sub(1, #prefix) == prefix then
			return idx
		end
	end
	return nil
end

local function entry(self, job)
	local ch = job.args[1]
	if not ch or ch == "" then return end

	local current = cx.active.current
	local files = current.files
	local n = #files
	if n == 0 then return end

	local lower_ch = ch:lower()
	local cursor = current.cursor -- 0-based

	local new_prefix, start

	if state.last_char == lower_ch and state.last_idx then
		-- Same key: cycle to next match keeping current prefix
		new_prefix = state.prefix
		start = state.last_idx + 1
	else
		-- Different key: extend prefix, search from beginning
		new_prefix = state.prefix .. lower_ch
		start = 0
	end

	local found = find_match(files, n, new_prefix, start)

	-- If extended prefix found nothing, fall back to just the new char
	if not found and state.last_char ~= lower_ch then
		new_prefix = lower_ch
		found = find_match(files, n, new_prefix, 0)
	end

	if found then
		state.prefix = new_prefix
		state.last_char = lower_ch
		state.last_idx = found
		local move = found - cursor
		if move ~= 0 then
			ya.emit("arrow", { move })
		end
	end
end

return { entry = entry }
