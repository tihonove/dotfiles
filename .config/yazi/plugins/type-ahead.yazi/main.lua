--- @sync entry
--- type-ahead.yazi: Windows Explorer-style single-key jump
---
--- Press a letter/digit → jump to first file starting with it.
--- Press the same letter again → cycle to the next match.
--- Press a different letter → jump to the first match for the new letter.

local state = { last_char = nil, last_idx = nil }

local function entry(self, job)
	local ch = job.args[1]
	if not ch or ch == "" then return end

	local current = cx.active.current
	local files = current.files
	local n = #files
	if n == 0 then return end

	local lower_ch = ch:lower()
	local cursor = current.cursor -- 0-based

	-- Determine start position for search
	local start
	if state.last_char == lower_ch and state.last_idx then
		-- Same char pressed again: start searching from NEXT file after last match
		start = state.last_idx + 1
	else
		-- New char: start from the beginning
		start = 0
	end

	-- Search from start to end, then wrap around from 0
	local found = nil
	for offset = 0, n - 1 do
		local idx = (start + offset) % n
		local name = files[idx + 1].name -- files is 1-indexed
		if name:sub(1, 1):lower() == lower_ch then
			found = idx
			break
		end
	end

	if found then
		state.last_char = lower_ch
		state.last_idx = found
		local move = found - cursor
		if move ~= 0 then
			ya.emit("arrow", { move })
		end
	end
end

return { entry = entry }
