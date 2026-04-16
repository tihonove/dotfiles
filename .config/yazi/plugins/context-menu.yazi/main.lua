--- Context menu: open-with + copy path actions via ya.which()

local get_hovered = ya.sync(function()
	local h = cx.active.current.hovered
	if h then
		return {
			url = tostring(h.url),
			name = tostring(h.name),
		}
	end
	return nil
end)

local function entry()
	local cand = ya.which {
		cands = {
			{ on = "o", desc = "Open with..." },
			{ on = "p", desc = "Copy path" },
			{ on = "n", desc = "Copy filename" },
			{ on = "d", desc = "Copy directory path" },
			{ on = "f", desc = "Copy files to clipboard" },
		},
	}

	if not cand then
		return
	end

	if cand == 1 then
		ya.emit("open", { interactive = true })
		return
	end

	local h = get_hovered()
	if not h then return end

	if cand == 2 then
		-- Copy full path
		ya.clipboard(h.url)
		Command("sh"):arg({ "-c", "printf '%s' " .. ya.quote(h.url) .. " | xsel -bi" }):status()
		ya.notify { title = "Clipboard", content = "Path: " .. h.url, timeout = 3 }
	elseif cand == 3 then
		-- Copy filename
		local name = h.url:match("[^/]+$") or h.url
		ya.clipboard(name)
		Command("sh"):arg({ "-c", "printf '%s' " .. ya.quote(name) .. " | xsel -bi" }):status()
		ya.notify { title = "Clipboard", content = "Name: " .. name, timeout = 3 }
	elseif cand == 4 then
		-- Copy directory path
		local dir = h.url:match("(.+)/[^/]*$") or h.url
		ya.clipboard(dir)
		Command("sh"):arg({ "-c", "printf '%s' " .. ya.quote(dir) .. " | xsel -bi" }):status()
		ya.notify { title = "Clipboard", content = "Dir: " .. dir, timeout = 3 }
	elseif cand == 5 then
		-- Copy files to system clipboard (delegate to copy-files plugin)
		ya.emit("plugin", { "copy-files" })
	end
end

return { entry = entry }
