local M = { _id = "command-palette" }

local function fail(s, ...) 
  ya.notify { title = "Command Palette", content = string.format(s, ...), timeout = 5, level = "error" } 
end

local function info(s, ...) 
  ya.notify { title = "Command Palette", content = string.format(s, ...), timeout = 3, level = "info" } 
end

local function debug(s, ...)
  ya.notify { title = "Command Palette DEBUG", content = string.format(s, ...), timeout = 5, level = "warn" }
end

-- Load tinytoml TOML parser (https://github.com/FourierTransformer/tinytoml)
local tinytoml
do
  local plugin_dir = os.getenv("HOME") .. "/.config/yazi/plugins/command-palette.yazi/"
  local loader, err = loadfile(plugin_dir .. "tinytoml.lua")
  if loader then
    tinytoml = loader()
  else
    fail("Failed to load tinytoml: %s", tostring(err))
  end
end

-- Get all TOML files from plugins directory
local function get_plugin_tomls()
  local tomls = {}
  local plugins_dir = os.getenv("HOME") .. "/.config/yazi/plugins"
  
  -- Try to list directory contents
  local handle = io.popen("find '" .. plugins_dir .. "' -name '*.toml' 2>/dev/null")
  if handle then
    for line in handle:lines() do
      table.insert(tomls, line)
    end
    handle:close()
  end
  
  return tomls
end

-- Normalize a single keymap entry from parsed TOML into {key, desc, run}
local function normalize_keymap_entry(entry)
  if type(entry) ~= "table" then return nil end
  
  -- Normalize "on" field → key
  local key
  if type(entry.on) == "string" then
    key = entry.on
  elseif type(entry.on) == "table" then
    local parts = {}
    for _, k in ipairs(entry.on) do
      parts[#parts + 1] = tostring(k)
    end
    key = table.concat(parts, " + ")
  end
  
  -- Normalize "run" field
  local run
  if type(entry.run) == "string" then
    run = entry.run
  elseif type(entry.run) == "table" then
    -- Take the first command from the array
    run = entry.run[1] and tostring(entry.run[1]) or nil
  end
  
  local desc = type(entry.desc) == "string" and entry.desc or nil
  
  if key and run then
    return { key = key, desc = desc, run = run }
  end
  return nil
end

-- Recursively walk a parsed TOML table to find all keymap arrays
local function collect_keymap_entries(tbl, commands)
  if type(tbl) ~= "table" then return end
  
  -- Check if tbl is an array of keymap entries (first element has "on" or "run")
  if #tbl > 0 and type(tbl[1]) == "table" and (tbl[1].on ~= nil or tbl[1].run ~= nil) then
    for _, entry in ipairs(tbl) do
      local cmd = normalize_keymap_entry(entry)
      if cmd then
        commands[#commands + 1] = cmd
      end
    end
    return
  end
  
  -- Otherwise recurse into sub-tables (dict-like)
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      collect_keymap_entries(v, commands)
    end
  end
end

-- Parse TOML keymap file to extract keybindings (uses tinytoml)
local function parse_keymap_file(file_path)
  if not tinytoml then return {} end
  
  local ok, data = pcall(tinytoml.parse, file_path)
  if not ok then
    -- Try loading as string in case file path has issues
    local file = io.open(file_path, "r")
    if not file then return {} end
    local content = file:read("*all")
    file:close()
    ok, data = pcall(tinytoml.parse, content, { load_from_string = true })
    if not ok then
      return {}
    end
  end
  
  local commands = {}
  collect_keymap_entries(data, commands)
  return commands
end

-- Get all available commands from keymap files
local function get_all_commands()
  local commands = {}
  
  -- Try to read from config keymap
  local config_path = os.getenv("HOME") .. "/.config/yazi/keymap.toml"
  local config_commands = parse_keymap_file(config_path)
  
  for _, cmd in ipairs(config_commands) do
    cmd.source = "config"
    table.insert(commands, cmd)
  end
  
  -- Try to read from plugin TOML files
  local plugin_tomls = get_plugin_tomls()
  for _, toml_path in ipairs(plugin_tomls) do
    local plugin_commands = parse_keymap_file(toml_path)
    for _, cmd in ipairs(plugin_commands) do
      cmd.source = "plugin:" .. toml_path:match("([^/]+)$")
      table.insert(commands, cmd)
    end
  end
  
--   debug("Total commands found: " .. #commands)
  
  return commands
end

-- Execute a yazi command string by parsing and emitting via ya.emit (works in any context)
local function emit_command(cmd_string, current_file)
  current_file = current_file or ""
  if cmd_string:match("^shell") then
    local shell_cmd = cmd_string:match('shell%s+["\']([^"\']+)["\']') or 
                     cmd_string:match('shell%s+--block%s+["\']([^"\']+)["\']')
    if shell_cmd then
      shell_cmd = shell_cmd:gsub("\\$", "")
      local is_blocking = cmd_string:match("--block") and true or false
      ya.emit("shell", { shell_cmd .. " " .. current_file, block = is_blocking })
    end
  elseif cmd_string:match("^plugin") then
    local plugin_name = cmd_string:match("plugin%s+([%w%-_]+)")
    local plugin_args = cmd_string:match("plugin%s+[%w%-_]+%s+(.+)")
    if plugin_name then
      if plugin_args then
        local args = {}
        for arg in plugin_args:gmatch("[^%s]+") do
          table.insert(args, arg)
        end
        ya.emit("plugin", { plugin_name, args = args })
      else
        ya.emit("plugin", { plugin_name })
      end
    end
  else
    local parts = {}
    for part in cmd_string:gmatch("[^%s]+") do
      table.insert(parts, part)
    end
    if #parts > 0 then
      local command = parts[1]
      local args = {}
      for i = 2, #parts do
        table.insert(args, parts[i])
      end
      ya.emit(command, #args > 0 and args or {})
    end
  end
end

-- Get hovered file path from sync context
local get_command_context = ya.sync(function(self)
  local h = cx.active.current.hovered
  return h and tostring(h.url) or ""
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- Fuzzy Matching (VSCode-style with CamelHumps)
-- ═══════════════════════════════════════════════════════════════════════════════

local function fuzzy_match(pattern, text)
  if not pattern or pattern == "" then return 0, {} end
  if not text or text == "" then return nil end

  local plen = #pattern
  local tlen = #text
  local plower = pattern:lower()
  local tlower = text:lower()

  -- Quick reject: check all pattern chars exist in order
  local pi = 1
  for ti = 1, tlen do
    if tlower:byte(ti) == plower:byte(pi) then
      pi = pi + 1
      if pi > plen then break end
    end
  end
  if pi <= plen then return nil end

  -- Helper: is position a word boundary?
  local function is_boundary(pos)
    if pos == 1 then return true end
    local prev = text:byte(pos - 1)
    -- space=32, dash=45, underscore=95, dot=46, slash=47, backslash=92, colon=58
    return prev == 32 or prev == 45 or prev == 95 or prev == 46
        or prev == 47 or prev == 92 or prev == 58
  end

  -- Helper: is position a camelCase boundary?
  local function is_camel(pos)
    if pos <= 1 then return false end
    local cur = text:byte(pos)
    local prev = text:byte(pos - 1)
    return cur >= 65 and cur <= 90 and prev >= 97 and prev <= 122
  end

  -- Compute last possible position for each pattern char (right-to-left)
  local last_possible = {}
  local ti = tlen
  for p = plen, 1, -1 do
    while ti >= 1 and tlower:byte(ti) ~= plower:byte(p) do
      ti = ti - 1
    end
    if ti < 1 then return nil end
    last_possible[p] = ti
    ti = ti - 1
  end

  -- Greedy forward pass: prefer word boundaries, then consecutive, then first
  local positions = {}
  local prev_pos = 0

  for p = 1, plen do
    local pc = plower:byte(p)
    local deadline = last_possible[p]
    local first_match = nil
    local best_match = nil
    local best_prio = -1

    for t = prev_pos + 1, deadline do
      if tlower:byte(t) == pc then
        if not first_match then first_match = t end

        local prio = 0
        if is_boundary(t) then prio = prio + 8 end
        if is_camel(t) then prio = prio + 6 end
        if t == prev_pos + 1 and prev_pos > 0 then prio = prio + 5 end
        if p == 1 and t == 1 then prio = prio + 12 end

        if prio > best_prio then
          best_prio = prio
          best_match = t
        end
        -- Stop early if we found a great match (boundary or consecutive)
        if prio >= 5 then break end
      end
    end

    local chosen = best_match or first_match
    if not chosen then return nil end
    positions[p] = chosen
    prev_pos = chosen
  end

  -- Scoring pass
  local score = 0
  for i = 1, plen do
    local pos = positions[i]
    score = score + 10 -- base per-char

    if is_boundary(pos) then score = score + 8 end
    if is_camel(pos) then score = score + 6 end
    if i == 1 and pos == 1 then score = score + 12 end

    if i > 1 and pos == positions[i - 1] + 1 then
      score = score + 5 -- consecutive
    end

    -- Gap penalty
    if i > 1 then
      score = score - (pos - positions[i - 1] - 1)
    else
      score = score - (pos - 1)
    end
  end

  return score, positions
end

-- Build highlighted ui.Span segments for text with matched positions
local function build_highlighted_spans(text, positions, is_selected)
  if not positions or #positions == 0 then
    if is_selected then
      return { ui.Span(text):style(th.indicator.current) }
    else
      return { ui.Span(text) }
    end
  end

  local pos_set = {}
  for _, p in ipairs(positions) do
    pos_set[p] = true
  end

  local spans = {}
  local i = 1
  local len = #text

  while i <= len do
    if pos_set[i] then
      local j = i
      while j <= len and pos_set[j] do j = j + 1 end
      local chunk = text:sub(i, j - 1)
      if is_selected then
        spans[#spans + 1] = ui.Span(chunk):style(th.indicator.current):bold()
      else
        spans[#spans + 1] = ui.Span(chunk):fg("cyan"):bold()
      end
      i = j
    else
      local j = i
      while j <= len and not pos_set[j] do j = j + 1 end
      local chunk = text:sub(i, j - 1)
      if is_selected then
        spans[#spans + 1] = ui.Span(chunk):style(th.indicator.current)
      else
        spans[#spans + 1] = ui.Span(chunk)
      end
      i = j
    end
  end

  return spans
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Modal Component
-- ═══════════════════════════════════════════════════════════════════════════════

function M:new(area)
  self._overlay = area:pad(ui.Pad(
    math.floor(area.h * 0.15),
    math.floor(area.w * 0.2),
    math.floor(area.h * 0.15),
    math.floor(area.w * 0.2)
  ))
  return self
end

function M:reflow()
  return { self }
end

function M:redraw()
  local area = self._overlay
  if not area or not self._children_id then return {} end

  local inner = area:pad(ui.Pad(1, 2, 1, 2))
  local filter = self.filter or ""
  local filtered = self.filtered or {}
  local cursor = self.cursor or 0

  local elements = {
    ui.Clear(area),
    ui.Border(ui.Edge.ALL):area(area):type(ui.Border.ROUNDED),
  }

  -- Title on top border
  local title_w = math.min(20, area.w - 4)
  if title_w > 0 then
    elements[#elements + 1] = ui.Line {
      ui.Span(" Command Palette "):bold()
    }:area(ui.Rect { x = area.x + 2, y = area.y, w = title_w, h = 1 })
  end

  if inner.h < 3 then return elements end

  -- Search input line
  elements[#elements + 1] = ui.Line {
    ui.Span("> "):fg("cyan"):bold(),
    ui.Span(filter),
    ui.Span("█"):fg("cyan"),
  }:area(ui.Rect { x = inner.x, y = inner.y, w = inner.w, h = 1 })

  -- Separator
  elements[#elements + 1] = ui.Line(string.rep("─", inner.w)):fg("gray")
    :area(ui.Rect { x = inner.x, y = inner.y + 1, w = inner.w, h = 1 })

  -- Results list
  local list_y = inner.y + 2
  local visible_h = math.max(0, inner.h - 2)
  local total = #filtered

  -- Scroll offset: keep cursor visible
  local offset = 0
  if cursor >= visible_h then
    offset = cursor - visible_h + 1
  end

  -- Pill-shape selection: Powerline caps take 1 cell each
  local SEL_BG = "#cba6f7" -- Catppuccin Mocha Mauve (indicator.current bg)
  local content_w = inner.w - 2 -- usable width between left and right cap

  for i = offset + 1, math.min(offset + visible_h, total) do
    local cmd = filtered[i]
    local desc = cmd.desc or "No description"
    local key_str = cmd.key or "?"
    local key_display = "[" .. key_str .. "]"
    local is_selected = (i - 1 == cursor)
    local row_y = list_y + (i - offset - 1)
    local row_area = ui.Rect { x = inner.x, y = row_y, w = inner.w, h = 1 }

    -- Build highlighted spans for desc
    local desc_spans = build_highlighted_spans(desc, cmd._desc_positions, is_selected)

    -- Padding between desc and key (content_w excludes caps)
    local padding_len = math.max(1, content_w - #desc - #key_display)
    local padding_span
    if is_selected then
      padding_span = ui.Span(string.rep(" ", padding_len)):style(th.indicator.current)
    else
      padding_span = ui.Span(string.rep(" ", padding_len))
    end

    -- Build key spans
    local key_spans = {}
    if cmd._key_positions and #cmd._key_positions > 0 then
      local bracket_style = is_selected
        and function(s) return s:style(th.indicator.current) end
        or function(s) return s end
      key_spans[#key_spans + 1] = bracket_style(ui.Span("["))
      local inner_spans = build_highlighted_spans(key_str, cmd._key_positions, is_selected)
      for _, s in ipairs(inner_spans) do key_spans[#key_spans + 1] = s end
      key_spans[#key_spans + 1] = bracket_style(ui.Span("]"))
    else
      if is_selected then
        key_spans[#key_spans + 1] = ui.Span(key_display):style(th.indicator.current)
      else
        key_spans[#key_spans + 1] = ui.Span(key_display)
      end
    end

    -- Combine all spans with pill-shape caps for selected row
    local all_spans = {}

    if is_selected then
      -- Left rounded cap: fg = selection bg, draws  on default bg
      all_spans[#all_spans + 1] = ui.Span("\xee\x82\xb6"):fg(SEL_BG)
    else
      -- Spacer to keep text aligned with selected rows
      all_spans[#all_spans + 1] = ui.Span(" ")
    end

    for _, s in ipairs(desc_spans) do all_spans[#all_spans + 1] = s end
    all_spans[#all_spans + 1] = padding_span
    for _, s in ipairs(key_spans) do all_spans[#all_spans + 1] = s end

    -- Trailing padding to fill content area, then right cap
    if is_selected then
      local total_len = #desc + padding_len + #key_display
      local extra = math.max(0, content_w - total_len)
      if extra > 0 then
        all_spans[#all_spans + 1] = ui.Span(string.rep(" ", extra)):style(th.indicator.current)
      end
      -- Right rounded cap: fg = selection bg, draws  on default bg
      all_spans[#all_spans + 1] = ui.Span("\xee\x82\xb4"):fg(SEL_BG)
    else
      all_spans[#all_spans + 1] = ui.Span(" ")
    end

    elements[#elements + 1] = ui.Line(all_spans):area(row_area)
  end

  -- Empty state
  if total == 0 and filter ~= "" then
    elements[#elements + 1] = ui.Line("   No matching commands"):fg("gray")
      :area(ui.Rect { x = inner.x, y = list_y, w = inner.w, h = 1 })
  end

  -- Counter on bottom border
  local count_str = string.format(" %d/%d ", total, #(self.commands or {}))
  local count_x = area.x + area.w - #count_str - 2
  if count_x > area.x then
    elements[#elements + 1] = ui.Line {
      ui.Span(count_str):fg("gray")
    }:area(ui.Rect { x = count_x, y = area.y + area.h - 1, w = #count_str, h = 1 })
  end

  return elements
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Sync State Management
-- ═══════════════════════════════════════════════════════════════════════════════

local toggle_ui = ya.sync(function(self)
  if self._children_id then
    Modal:children_remove(self._children_id)
    self._children_id = nil
  else
    self._children_id = Modal:children_add(self, 10)
  end
  ui.render()
end)

local init_state = ya.sync(function(self)
  -- Collect commands entirely in sync context to avoid table serialization issues
  self.commands = get_all_commands()
  self.filter = ""
  self.cursor = 0
  self.filtered = self.commands
  ui.render()
  return #self.commands
end)

local update_filter = ya.sync(function(self, filter)
  self.filter = filter
  if filter == "" then
    -- Clear match metadata and show all commands
    for _, cmd in ipairs(self.commands or {}) do
      cmd._score = nil
      cmd._desc_positions = nil
      cmd._key_positions = nil
    end
    self.filtered = self.commands or {}
  else
    local result = {}
    for _, cmd in ipairs(self.commands or {}) do
      local desc_score, desc_pos = fuzzy_match(filter, cmd.desc or "")
      local key_score, key_pos = fuzzy_match(filter, cmd.key or "")

      if desc_score or key_score then
        -- Take the better match for ranking; store positions for highlighting
        if (desc_score or -math.huge) >= (key_score or -math.huge) then
          cmd._score = desc_score
          cmd._desc_positions = desc_pos
          cmd._key_positions = nil
        else
          cmd._score = key_score
          cmd._desc_positions = nil
          cmd._key_positions = key_pos
        end
        result[#result + 1] = cmd
      else
        cmd._score = nil
        cmd._desc_positions = nil
        cmd._key_positions = nil
      end
    end
    -- Sort by score descending (best matches first)
    table.sort(result, function(a, b)
      return (a._score or 0) > (b._score or 0)
    end)
    self.filtered = result
  end
  self.cursor = 0
  local max_idx = math.max(0, #self.filtered - 1)
  if self.cursor > max_idx then self.cursor = max_idx end
  ui.render()
end)

local move_cursor = ya.sync(function(self, delta)
  local total = #(self.filtered or {})
  if total == 0 then return end
  self.cursor = self.cursor + delta
  if self.cursor < 0 then self.cursor = 0 end
  if self.cursor >= total then self.cursor = total - 1 end
  ui.render()
end)

-- Get the currently selected command data from sync context (no emission here)
local get_selected_command = ya.sync(function(self)
  local filtered = self.filtered or {}
  if #filtered == 0 then return nil, nil, nil end
  local cmd = filtered[self.cursor + 1]
  if not cmd or not cmd.run then return nil, nil, nil end

  local h = cx.active.current.hovered
  local current_file = h and tostring(h.url) or ""

  return cmd.run, cmd.desc, current_file
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- Key Input Handling
-- ═══════════════════════════════════════════════════════════════════════════════

local function build_key_candidates()
  local cands = {}
  -- Letters
  for c = string.byte("a"), string.byte("z") do
    local ch = string.char(c)
    cands[#cands + 1] = { on = ch, action = "type", char = ch }
  end
  for c = string.byte("A"), string.byte("Z") do
    local ch = string.char(c)
    cands[#cands + 1] = { on = ch, action = "type", char = ch }
  end
  -- Digits
  for c = string.byte("0"), string.byte("9") do
    local ch = string.char(c)
    cands[#cands + 1] = { on = ch, action = "type", char = ch }
  end
  -- Common symbols
  for _, ch in ipairs({ "-", "_", ".", ",", ":", ";", "/", "!", "@", "#", "$", "%%", "&", "*", "(", ")", "+", "=", "'", "?", "|", "~" }) do
    cands[#cands + 1] = { on = ch, action = "type", char = ch }
  end
  -- Space
  cands[#cands + 1] = { on = "<Space>", action = "type", char = " " }
  -- Navigation and control
  cands[#cands + 1] = { on = "<Backspace>", action = "backspace" }
  cands[#cands + 1] = { on = "<Up>", action = "up" }
  cands[#cands + 1] = { on = "<Down>", action = "down" }
  cands[#cands + 1] = { on = "<C-p>", action = "up" }
  cands[#cands + 1] = { on = "<C-n>", action = "down" }
  cands[#cands + 1] = { on = "<C-u>", action = "clear" }
  cands[#cands + 1] = { on = "<Enter>", action = "confirm" }
  cands[#cands + 1] = { on = "<Esc>", action = "quit" }
  cands[#cands + 1] = { on = "<C-c>", action = "quit" }
  return cands
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Modal Command Palette (default mode)
-- ═══════════════════════════════════════════════════════════════════════════════

local function show_modal_palette()
  local count = init_state()

  if count == 0 then
    fail("No commands found in keymap files")
    return
  end

  toggle_ui()

  local cands = build_key_candidates()
  local filter = ""

  while true do
    local idx = ya.which { cands = cands, silent = true }
    local cand = idx and cands[idx]

    if not cand then
      -- Unmatched key, ignore and continue
    elseif cand.action == "type" then
      filter = filter .. cand.char
      update_filter(filter)
    elseif cand.action == "backspace" then
      if #filter > 0 then
        filter = filter:sub(1, -2)
        update_filter(filter)
      end
    elseif cand.action == "clear" then
      filter = ""
      update_filter(filter)
    elseif cand.action == "up" then
      move_cursor(-1)
    elseif cand.action == "down" then
      move_cursor(1)
    elseif cand.action == "confirm" then
      toggle_ui()
      local cmd_string, desc, current_file = get_selected_command()
      if cmd_string then
        info("Executing: " .. (desc or cmd_string))
        emit_command(cmd_string, current_file)
      end
      return
    elseif cand.action == "quit" then
      toggle_ui()
      return
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Fzf Command Palette (use with "fzf" argument)
-- ═══════════════════════════════════════════════════════════════════════════════
local function show_command_palette()
  local commands = get_all_commands()
  
  if #commands == 0 then
    fail("No commands found in keymap files")
    return
  end
  
  local _permit = ya.hide()
  local child, err = Command("fzf")
    :arg({
      "--height=80%",
      "--layout=reverse",
      "--border",
      "--prompt=🔍 Command Palette: ",
      "--header=Type to search commands",
      "--preview-window=right:40%",
      "--preview=echo {2}",
      "--delimiter=\t",
      "--with-nth=1",
      "--bind=ctrl-/:toggle-preview"
    })
    :stdin(Command.PIPED)
    :stdout(Command.PIPED)
    :stderr(Command.INHERIT)
    :spawn()
  
  if not child then
    fail("Failed to spawn fzf. Is it installed?")
    return
  end
  
  -- Build input for fzf with right-aligned key bindings
  local input_lines = {}

  -- Get terminal width for right-alignment (fallback to 80)
  local term_width = 80
  local tw_handle = io.popen("tput cols 2>/dev/null")
  if tw_handle then
    local tw_str = tw_handle:read("*l")
    tw_handle:close()
    if tw_str then
      term_width = tonumber(tw_str) or 80
    end
  end
  -- Account for fzf chrome (border, prompt indicator, padding)
  local available_width = term_width - 6

  for _, cmd in ipairs(commands) do
    local desc = cmd.desc or "No description"
    local key_display = cmd.key or "No key"
    local key_with_brackets = "[" .. key_display .. "]"
    local padding = available_width - #desc - #key_with_brackets
    if padding < 2 then padding = 2 end
    local display = desc .. string.rep(" ", padding) .. key_with_brackets
    local line = string.format("%s\t%s", display, cmd.run)
    table.insert(input_lines, line)
  end
  
  child:write_all(table.concat(input_lines, "\n"))
  child:flush()
  
  local output, err = child:wait_with_output()
  if not output then
    fail("Cannot read fzf output")
    return
  end
  
  if not output.status.success and output.status.code ~= 130 then
    fail("fzf exited with error code: " .. tostring(output.status.code))
    return
  end
  
  -- Parse fzf output
  local selected_line = output.stdout:match("([^\n]*)")
  if not selected_line or selected_line == "" then
    return
  end
  
  local display, run_cmd = selected_line:match("([^\t]*)\t([^\t]*)")
  if run_cmd then
    -- Extract description (before the padding spaces)
    local desc = display and display:match("^(.-)%s%s") or display or "command"
    info("Executing: " .. desc)
    local current_file = get_command_context(run_cmd)
    emit_command(run_cmd, current_file)
  end
end

-- Alternative built-in interface (fallback if fzf not available)
local function show_builtin_palette()
  local commands = get_all_commands()
  
  if #commands == 0 then
    fail("No commands found in keymap files")
    return
  end
  
  -- Create candidates for ya.which with single character keys
  local candidates = {}
  local keys = "abcdefghijklmnopqrstuvwxyz0123456789"
  
  for i, cmd in ipairs(commands) do
    if i > #keys then break end -- Limit to available keys
    
    local desc = cmd.desc or "No description"
    local key_display = cmd.key or "No key"
    local display = string.format("%s (%s)", desc, key_display)
    
    table.insert(candidates, {
      on = keys:sub(i, i),
      desc = display,
      cmd = cmd.run,
      key = cmd.key
    })
  end
  
  -- Show the selection interface
  local choice = ya.which {
    cands = candidates,
    silent = true
  }
  
  if choice then
    local selected = candidates[choice]
    info("Executing: " .. (selected.desc or "Unknown command"))
    local current_file = get_command_context(selected.cmd)
    emit_command(selected.cmd, current_file)
  end
end

M.entry = function(_, args)
  local mode = args and args[1]
  if mode == "fzf" then
    show_command_palette()
  elseif mode == "builtin" then
    show_builtin_palette()
  else
    show_modal_palette()
  end
end

return M