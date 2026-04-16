--- Copy selected (or hovered) file path(s) to system clipboard.
--- Uses ya.clipboard() (sends OSC 52) and also pipes to xsel as fallback.

local selected = ya.sync(function()
	local sel = cx.active.selected
	local paths = {}

	if #sel > 0 then
		for _, url in pairs(sel) do
			paths[#paths + 1] = tostring(url)
		end
	else
		local h = cx.active.current.hovered
		if h then
			paths[1] = tostring(h.url)
		end
	end

	return paths
end)

local function entry()
	local paths = selected()
	if #paths == 0 then
		return
	end

	local text = table.concat(paths, "\n")

	-- OSC 52 (works in kitty, WezTerm, Alacritty, etc.)
	ya.clipboard(text)

	-- xsel fallback (works locally in GNOME Terminal / X11)
	local status = Command("sh")
		:arg({ "-c", "printf '%s' " .. ya.quote(text) .. " | xsel -bi" })
		:status()

	ya.notify {
		title = "Clipboard",
		content = #paths == 1
			and "Copied: " .. paths[1]:match("[^/]+$")
			or #paths .. " paths copied",
		timeout = 3,
	}
end

return { entry = entry }
