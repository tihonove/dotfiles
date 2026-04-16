--- Copy selected (or hovered) files to system clipboard as file URIs.
--- On Linux uses clip-files helper (multi-MIME: gnome-copied-files + uri-list + text).
--- On macOS uses osascript/NSPasteboard.

local get_paths = ya.sync(function()
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
	local paths = get_paths()
	if #paths == 0 then
		return
	end

	local os = ya.target_os()

	if os == "macos" then
		local quoted = {}
		for i, p in ipairs(paths) do
			quoted[i] = '"' .. p:gsub('"', '\\"') .. '" as POSIX file'
		end
		local script = 'set the clipboard to {' .. table.concat(quoted, ', ') .. '}'
		Command("osascript"):arg({ "-e", script }):status()
	else
		-- Linux: clip-files sets gnome-copied-files + text/uri-list + UTF8_STRING
		local cmd = Command("clip-files")
		for _, p in ipairs(paths) do
			cmd = cmd:arg(p)
		end
		cmd:status()
	end

	ya.notify {
		title = "Clipboard",
		content = #paths == 1
			and "Copied file: " .. paths[1]:match("[^/]+$")
			or #paths .. " files copied",
		timeout = 3,
	}
end

return { entry = entry }
