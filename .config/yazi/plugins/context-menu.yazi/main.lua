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

local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

-- Submenu: open a terminal in the current directory.
-- tmux entries only when running inside tmux; kitty tab is always available.
local function open_terminal()
	local cwd = get_cwd()
	if not cwd then return end

	local in_tmux = os.getenv("TMUX") ~= nil

	local cands = {}
	local actions = {}
	if in_tmux then
		cands[#cands + 1] = { on = "p", desc = "Floating popup (tmux)" }
		actions[#actions + 1] = {
			cmd = "tmux display-popup -d " .. ya.quote(cwd) .. ' -E "$SHELL"',
			block = true,
		}
		cands[#cands + 1] = { on = "s", desc = "Split pane (tmux)" }
		actions[#actions + 1] = {
			cmd = "tmux split-window -h -c " .. ya.quote(cwd),
			orphan = true,
		}
	end
	cands[#cands + 1] = { on = "k", desc = "New tab (kitty)" }
	actions[#actions + 1] = {
		cmd = "kitty @ --to unix:/tmp/kitty launch --type=tab --cwd=" .. ya.quote(cwd),
		orphan = true,
	}

	local pick = ya.which { cands = cands }
	if not pick then return end

	local a = actions[pick]
	if a.block then
		ya.emit("shell", { a.cmd, block = true })
	else
		ya.emit("shell", { a.cmd, orphan = true })
	end
end

local function entry()
	local cand = ya.which {
		cands = {
			{ on = "o", desc = "Open with..." },
			{ on = "t", desc = "Open terminal here ▸" },
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
	elseif cand == 2 then
		open_terminal()
		return
	end

	local h = get_hovered()
	if not h then return end

	if cand == 3 then
		-- Copy full path
		ya.clipboard(h.url)
		Command("sh"):arg({ "-c", "printf '%s' " .. ya.quote(h.url) .. " | xsel -bi" }):status()
		ya.notify { title = "Clipboard", content = "Path: " .. h.url, timeout = 3 }
	elseif cand == 4 then
		-- Copy filename
		local name = h.url:match("[^/]+$") or h.url
		ya.clipboard(name)
		Command("sh"):arg({ "-c", "printf '%s' " .. ya.quote(name) .. " | xsel -bi" }):status()
		ya.notify { title = "Clipboard", content = "Name: " .. name, timeout = 3 }
	elseif cand == 5 then
		-- Copy directory path
		local dir = h.url:match("(.+)/[^/]*$") or h.url
		ya.clipboard(dir)
		Command("sh"):arg({ "-c", "printf '%s' " .. ya.quote(dir) .. " | xsel -bi" }):status()
		ya.notify { title = "Clipboard", content = "Dir: " .. dir, timeout = 3 }
	elseif cand == 6 then
		-- Copy files to system clipboard (delegate to copy-files plugin)
		ya.emit("plugin", { "copy-files" })
	end
end

return { entry = entry }
