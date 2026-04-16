--- Paste files from system clipboard into the current directory.
--- On Linux reads file URIs from xclip, on macOS from NSPasteboard.

local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

local function entry()
	local cwd = get_cwd()
	local os = ya.target_os()

	if os == "macos" then
		local output = Command("osascript"):arg({ "-l", "JavaScript", "-e", [[
			ObjC.import('AppKit');
			ObjC.import('stdlib');
			var files = $.NSPasteboard.generalPasteboard.propertyListForType('NSFilenamesPboardType');
			if (files && files.count > 0) {
				var result = [];
				for (var i = 0; i < files.count; i++) {
					result.push(files.objectAtIndex(i).js);
				}
				result.join('\n');
			} else {
				'';
			}
		]] }):stdout(Command.PIPED):output()

		if output and output.stdout ~= "" then
			local count = 0
			for path in output.stdout:gmatch("[^\n]+") do
				Command("cp"):arg({ "-R", path, cwd }):status()
				count = count + 1
			end
			ya.notify {
				title = "Paste",
				content = count .. " item(s) pasted",
				timeout = 3,
			}
		else
			ya.notify {
				title = "Paste",
				content = "No files in clipboard",
				timeout = 3,
				level = "warn",
			}
		end
	else
		-- Linux: read file URIs from xclip
		local output = Command("xclip")
			:arg({ "-selection", "clipboard", "-t", "text/uri-list", "-o" })
			:stdout(Command.PIPED)
			:output()

		if output and output.stdout ~= "" then
			local count = 0
			for uri in output.stdout:gmatch("[^\n]+") do
				local path = uri:gsub("^file://", "")
				if path ~= "" then
					Command("cp"):arg({ "-R", path, cwd }):status()
					count = count + 1
				end
			end
			ya.notify {
				title = "Paste",
				content = count .. " item(s) pasted",
				timeout = 3,
			}
		else
			ya.notify {
				title = "Paste",
				content = "No files in clipboard",
				timeout = 3,
				level = "warn",
			}
		end
	end
end

return { entry = entry }
