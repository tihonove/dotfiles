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

-- ═══════════════════════════════════════════════════════════════════════════════
-- tinytoml: Pure Lua TOML parser (inlined)
-- Source: https://github.com/FourierTransformer/tinytoml
-- License: MIT | Version: tinytoml 1.0.0 | TOML spec: 1.1.0
-- DO NOT EDIT this section manually — it is a vendored copy of tinytoml.lua
-- ═══════════════════════════════════════════════════════════════════════════════
local tinytoml = {}
local TOML_VERSION = "1.1.0"
tinytoml._VERSION = "tinytoml 1.0.0"
tinytoml._TOML_VERSION = TOML_VERSION
tinytoml._DESCRIPTION = "a single-file pure Lua TOML parser"
tinytoml._URL = "https://github.com/FourierTransformer/tinytoml"
tinytoml._LICENSE = "MIT"
local sbyte = string.byte
local chars = {
   SINGLE_QUOTE = sbyte("'"),
   DOUBLE_QUOTE = sbyte('"'),
   OPEN_BRACKET = sbyte("["),
   CLOSE_BRACKET = sbyte("]"),
   BACKSLASH = sbyte("\\"),
   COMMA = sbyte(","),
   POUND = sbyte("#"),
   DOT = sbyte("."),
   CR = sbyte("\r"),
   LF = sbyte("\n"),
}
local function replace_control_chars(s)
   return string.gsub(s, "[%z\001-\008\011-\031\127]", function(c)
      return string.format("\\x%02x", string.byte(c))
   end)
end
local function _error(sm, message, anchor)
   local error_message = {}
   if sm.filename then
      error_message = { "\n\nIn '", sm.filename, "', line ", sm.line_number, ":\n\n  " }
      local _, end_line = sm.input:find(".-\n", sm.line_number_char_index)
      error_message[#error_message + 1] = sm.line_number
      error_message[#error_message + 1] = " | "
      error_message[#error_message + 1] = replace_control_chars(sm.input:sub(sm.line_number_char_index, end_line))
      error_message[#error_message + 1] = (end_line and "\n" or "\n\n")
   end
   error_message[#error_message + 1] = message
   error_message[#error_message + 1] = "\n"
   if anchor ~= nil then
      error_message[#error_message + 1] = "\nSee https://toml.io/en/v"
      error_message[#error_message + 1] = TOML_VERSION
      error_message[#error_message + 1] = "#"
      error_message[#error_message + 1] = anchor
      error_message[#error_message + 1] = " for more details"
   end
   error(table.concat(error_message))
end
local _unpack = unpack or table.unpack
local _tointeger = math.tointeger or tonumber
local _utf8char = utf8 and utf8.char or function(cp)
   if cp < 128 then
      return string.char(cp)
   end
   local suffix = cp % 64
   local c4 = 128 + suffix
   cp = (cp - suffix) / 64
   if cp < 32 then
      return string.char(192 + (cp), (c4))
   end
   suffix = cp % 64
   local c3 = 128 + suffix
   cp = (cp - suffix) / 64
   if cp < 16 then
      return string.char(224 + (cp), c3, c4)
   end
   suffix = cp % 64
   cp = (cp - suffix) / 64
   return string.char(240 + (cp), 128 + (suffix), c3, c4)
end
local function validate_utf8(input, toml_sub)
   local i, len, line_number, line_number_start = 1, #input, 1, 1
   local byte, second, third, fourth = 0, 129, 129, 129
   toml_sub = toml_sub or false
   while i <= len do
      byte = sbyte(input, i)
      if byte <= 127 then
         if toml_sub then
            if byte < 9 then return false, line_number, line_number_start, "TOML only allows some control characters, but they must be escaped in double quoted strings"
            elseif byte == chars.CR and sbyte(input, i + 1) ~= chars.LF then return false, line_number, line_number_start, "TOML requires all '\\r' be followed by '\\n'"
            elseif byte == chars.LF then
               line_number = line_number + 1
               line_number_start = i + 1
            elseif byte >= 11 and byte <= 31 and byte ~= 13 then return false, line_number, line_number_start, "TOML only allows some control characters, but they must be escaped in double quoted strings"
            elseif byte == 127 then return false, line_number, line_number_start, "TOML only allows some control characters, but they must be escaped in double quoted strings" end
         end
         i = i + 1
      elseif byte >= 194 and byte <= 223 then
         second = sbyte(input, i + 1)
         i = i + 2
      elseif byte == 224 then
         second = sbyte(input, i + 1); third = sbyte(input, i + 2)
         if second ~= nil and second >= 128 and second <= 159 then return false, line_number, line_number_start, "Invalid UTF-8 Sequence" end
         i = i + 3
      elseif byte == 237 then
         second = sbyte(input, i + 1); third = sbyte(input, i + 2)
         if second ~= nil and second >= 160 and second <= 191 then return false, line_number, line_number_start, "Invalid UTF-8 Sequence" end
         i = i + 3
      elseif (byte >= 225 and byte <= 236) or byte == 238 or byte == 239 then
         second = sbyte(input, i + 1); third = sbyte(input, i + 2)
         i = i + 3
      elseif byte == 240 then
         second = sbyte(input, i + 1); third = sbyte(input, i + 2); fourth = sbyte(input, i + 3)
         if second ~= nil and second >= 128 and second <= 143 then return false, line_number, line_number_start, "Invalid UTF-8 Sequence" end
         i = i + 4
      elseif byte == 241 or byte == 242 or byte == 243 then
         second = sbyte(input, i + 1); third = sbyte(input, i + 2); fourth = sbyte(input, i + 3)
         i = i + 4
      elseif byte == 244 then
         second = sbyte(input, i + 1); third = sbyte(input, i + 2); fourth = sbyte(input, i + 3)
         if second ~= nil and second >= 160 and second <= 191 then return false, line_number, line_number_start, "Invalid UTF-8 Sequence" end
         i = i + 4
      else
         return false, line_number, line_number_start, "Invalid UTF-8 Sequence"
      end
      if second == nil or second < 128 or second > 191 then return false, line_number, line_number_start, "Invalid UTF-8 Sequence" end
      if third == nil or third < 128 or third > 191 then return false, line_number, line_number_start, "Invalid UTF-8 Sequence" end
      if fourth == nil or fourth < 128 or fourth > 191 then return false, line_number, line_number_start, "Invalid UTF-8 Sequence" end
   end
   return true
end
local function find_newline(sm)
   sm._, sm.end_seq = sm.input:find("\r?\n", sm.i)
   if sm.end_seq == nil then
      sm._, sm.end_seq = sm.input:find(".-$", sm.i)
   end
   sm.line_number = sm.line_number + 1
   sm.i = sm.end_seq + 1
   sm.line_number_char_index = sm.i
end
local escape_sequences = {
   ['b'] = '\b',
   ['t'] = '\t',
   ['n'] = '\n',
   ['f'] = '\f',
   ['r'] = '\r',
   ['e'] = '\027',
   ['\\'] = '\\',
   ['"'] = '"',
}
local function handle_backslash_escape(sm)
   if sm.multiline_string then
      if sm.input:find("^\\[ \t]-\r?\n", sm.i) then
         sm._, sm.end_seq = sm.input:find("%S", sm.i + 1)
         sm.i = sm.end_seq - 1
         return "", false
      end
   end
   sm._, sm.end_seq, sm.match = sm.input:find('^([\\btrfne"])', sm.i + 1)
   local escape = escape_sequences[sm.match]
   if escape then
      sm.i = sm.end_seq
      if sm.match == '"' then
         return escape, true
      else
         return escape, false
      end
   end
   sm._, sm.end_seq, sm.match, sm.ext = sm.input:find("^(x)([0-9a-fA-F][0-9a-fA-F])", sm.i + 1)
   if sm.match then
      local codepoint_to_insert = _utf8char(tonumber(sm.ext, 16))
      if not validate_utf8(codepoint_to_insert) then
         _error(sm, "Escaped UTF-8 sequence not valid UTF-8 character: '\\" .. sm.match .. sm.ext .. "'", "string")
      end
      sm.i = sm.end_seq
      return codepoint_to_insert, false
   end
   sm._, sm.end_seq, sm.match, sm.ext = sm.input:find("^(u)([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])", sm.i + 1)
   if not sm.match then
      sm._, sm.end_seq, sm.match, sm.ext = sm.input:find("^(U)([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])", sm.i + 1)
   end
   if sm.match then
      local codepoint_to_insert = _utf8char(tonumber(sm.ext, 16))
      if not validate_utf8(codepoint_to_insert) then
         _error(sm, "Escaped UTF-8 sequence not valid UTF-8 character: '\\" .. sm.match .. sm.ext .. "'", "string")
      end
      sm.i = sm.end_seq
      return codepoint_to_insert, false
   end
   return nil
end
local function close_string(sm)
   local escape
   local reset_quote
   local start_field, end_field = sm.i + 1, 0
   local second, third = sbyte(sm.input, sm.i + 1), sbyte(sm.input, sm.i + 2)
   local quote_count = 0
   local output = {}
   local found_closing_quote = false
   sm.multiline_string = false
   if second == chars.DOUBLE_QUOTE and third == chars.DOUBLE_QUOTE then
      if sm.mode == "table" then _error(sm, "Cannot have multiline strings as table keys", "table") end
      sm.multiline_string = true
      start_field = sm.i + 3
      second, third = sbyte(sm.input, sm.i + 3), sbyte(sm.input, sm.i + 4)
      if second == chars.LF then
         start_field = start_field + 1
      elseif second == chars.CR and third == chars.LF then
         start_field = start_field + 2
      end
      sm.i = start_field - 1
   end
   while found_closing_quote == false and sm.i <= sm.input_length do
      sm.i = sm.i + 1
      sm.byte = sbyte(sm.input, sm.i)
      if sm.byte == chars.BACKSLASH then
         output[#output + 1] = sm.input:sub(start_field, sm.i - 1)
         escape, reset_quote = handle_backslash_escape(sm)
         if reset_quote then quote_count = 0 end
         if escape ~= nil then
            output[#output + 1] = escape
         else
            sm._, sm._, sm.match = sm.input:find("(.-[^'\"])", sm.i + 1)
            _error(sm, "TOML only allows specific escape sequences. Invalid escape sequence found: '\\" .. sm.match .. "'", "string")
         end
         start_field = sm.i + 1
      elseif sm.multiline_string then
         if sm.byte == chars.DOUBLE_QUOTE then
            quote_count = quote_count + 1
            if quote_count == 5 then
               end_field = sm.i - 3
               output[#output + 1] = sm.input:sub(start_field, end_field)
               found_closing_quote = true
               break
            end
         else
            if quote_count >= 3 then
               end_field = sm.i - 4
               output[#output + 1] = sm.input:sub(start_field, end_field)
               found_closing_quote = true
               sm.i = sm.i - 1
               break
            else
               quote_count = 0
            end
         end
      else
         if sm.byte == chars.DOUBLE_QUOTE then
            end_field = sm.i - 1
            output[#output + 1] = sm.input:sub(start_field, end_field)
            found_closing_quote = true
            break
         elseif sm.byte == chars.CR or sm.byte == chars.LF then
            _error(sm, "String does not appear to be closed. Use multi-line (triple quoted) strings if non-escaped newlines are desired.", "string")
         end
      end
   end
   if not found_closing_quote then
      if sm.multiline_string then
         _error(sm, "Unable to find closing triple-quotes for multi-line string", "string")
      else
         _error(sm, "Unable to find closing quote for string", "string")
      end
   end
   sm.i = sm.i + 1
   sm.value = table.concat(output)
   sm.value_type = "string"
end
local function close_literal_string(sm)
   sm.byte = 0
   local start_field, end_field = sm.i + 1, 0
   local second, third = sbyte(sm.input, sm.i + 1), sbyte(sm.input, sm.i + 2)
   local quote_count = 0
   sm.multiline_string = false
   if second == chars.SINGLE_QUOTE and third == chars.SINGLE_QUOTE then
      if sm.mode == "table" then _error(sm, "Cannot have multiline strings as table keys", "table") end
      sm.multiline_string = true
      start_field = sm.i + 3
      second, third = sbyte(sm.input, sm.i + 3), sbyte(sm.input, sm.i + 4)
      if second == chars.LF then
         start_field = start_field + 1
      elseif second == chars.CR and third == chars.LF then
         start_field = start_field + 2
      end
      sm.i = start_field
   end
   while end_field ~= 0 or sm.i <= sm.input_length do
      sm.i = sm.i + 1
      sm.byte = sbyte(sm.input, sm.i)
      if sm.multiline_string then
         if sm.byte == chars.SINGLE_QUOTE then
            quote_count = quote_count + 1
            if quote_count == 5 then
               end_field = sm.i - 3
               break
            end
         else
            if quote_count >= 3 then
               end_field = sm.i - 4
               sm.i = sm.i - 1
               break
            else
               quote_count = 0
            end
         end
      else
         if sm.byte == chars.SINGLE_QUOTE then
            end_field = sm.i - 1
            break
         elseif sm.byte == chars.CR or sm.byte == chars.LF then
            _error(sm, "String does not appear to be closed. Use multi-line (triple quoted) strings if non-escaped newlines are desired.", "string")
         end
      end
   end
   if end_field == 0 then
      if sm.multiline_string then
         _error(sm, "Unable to find closing triple quotes for multi-line literal string", "string")
      else
         _error(sm, "Unable to find closing quote for literal string", "string")
      end
   end
   sm.i = sm.i + 1
   sm.value = sm.input:sub(start_field, end_field)
   sm.value_type = "string"
end
local function close_bare_string(sm)
   sm._, sm.end_seq, sm.match = sm.input:find("^([a-zA-Z0-9-_]+)", sm.i)
   if sm.match then
      sm.i = sm.end_seq + 1
      sm.multiline_string = false
      sm.value = sm.match
      sm.value_type = "string"
   else
      _error(sm, "Bare keys can only contain 'a-zA-Z0-9-_'. Invalid bare key found: '" .. sm.input:sub(sm.input:find("[^ #\r\n,]+", sm.i)) .. "'", "keys")
   end
end
local function remove_underscores_number(sm, number, anchor)
   if number:find("_") then
      if number:find("__") then _error(sm, "Numbers cannot have consecutive underscores. Found " .. anchor .. ": '" .. number .. "'", anchor) end
      if number:find("^_") or number:find("_$") then _error(sm, "Underscores are not allowed at beginning or end of a number. Found " .. anchor .. ": '" .. number .. "'", anchor) end
      if number:find("%D_%d") or number:find("%d_%D") then _error(sm, "Underscores must have digits on either side. Found " .. anchor .. ": '" .. number .. "'", anchor) end
      number = number:gsub("_", "")
   end
   return number
end
local integer_match = {
   ["b"] = { "^0b([01_]+)$", 2 },
   ["o"] = { "^0o([0-7_]+)$", 8 },
   ["x"] = { "^0x([0-9a-fA-F_]+)$", 16 },
}
local function validate_integer(sm, value)
   sm._, sm._, sm.match = value:find("^([-+]?[%d_]+)$")
   if sm.match then
      if sm.match:find("^[-+]?0[%d_]") then _error(sm, "Integers can't start with a leading 0. Found integer: '" .. sm.match .. "'", "integer") end
      sm.match = remove_underscores_number(sm, sm.match, "integer")
      sm.value = _tointeger(sm.match)
      sm.value_type = "integer"
      return true
   end
   if value:find("^0[box]") then
      local pattern_bits = integer_match[value:sub(2, 2)]
      sm._, sm._, sm.match = value:find(pattern_bits[1])
      if sm.match then
         sm.match = remove_underscores_number(sm, sm.match, "integer")
         sm.value = tonumber(sm.match, pattern_bits[2])
         sm.value_type = "integer"
         return true
      end
   end
end
local function validate_float(sm, value)
   sm._, sm._, sm.match, sm.ext = value:find("^([-+]?[%d_]+%.[%d_]+)(.*)$")
   if sm.match then
      if sm.match:find("%._") or sm.match:find("_%.") then _error(sm, "Underscores in floats must have a number on either side. Found float: '" .. sm.match .. sm.ext .. "'", "float") end
      if sm.match:find("^[-+]?0[%d_]") then _error(sm, "Floats can't start with a leading 0. Found float: '" .. sm.match .. sm.ext .. "'", "float") end
      sm.match = remove_underscores_number(sm, sm.match, "float")
      if sm.ext ~= "" then
         if sm.ext:find("^[eE][-+]?[%d_]+$") then
            sm.ext = remove_underscores_number(sm, sm.ext, "float")
            sm.value = tonumber(sm.match .. sm.ext)
            sm.value_type = "float"
            return true
         end
      else
         sm.value = tonumber(sm.match)
         sm.value_type = "float"
         return true
      end
   end
   sm._, sm._, sm.match = value:find("^([-+]?[%d_]+[eE][-+]?[%d_]+)$")
   if sm.match then
      if sm.match:find("_[eE]") or sm.match:find("[eE]_") then _error(sm, "Underscores in floats cannot be before or after the e. Found float: '" .. sm.match .. sm.ext .. "'", "float") end
      sm.match = remove_underscores_number(sm, sm.match, "float")
      sm.value = tonumber(sm.match)
      sm.value_type = "float"
      return true
   end
end
local max_days_in_month = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local function validate_seconds(sm, sec, anchor)
   if sec > 60 then _error(sm, "Seconds must be less than 61. Found second: " .. sec .. " in: '" .. sm.match .. "'", anchor) end
end
local function validate_hours_minutes(sm, hour, min, anchor)
   if hour > 23 then _error(sm, "Hours must be less than 24. Found hour: " .. hour .. " in: '" .. sm.match .. "'", anchor) end
   if min > 59 then _error(sm, "Minutes must be less than 60. Found minute: " .. min .. " in: '" .. sm.match .. "'", anchor) end
end
local function validate_month_date(sm, year, month, day, anchor)
   if month == 0 or month > 12 then _error(sm, "Month must be between 01-12. Found month: " .. month .. " in: '" .. sm.match .. "'", anchor) end
   if day == 0 or day > max_days_in_month[month] then
      local months = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
      _error(sm, "Too many days in the month. Found " .. day .. " days in " .. months[month] .. ", which only has " .. max_days_in_month[month] .. " days in: '" .. sm.match .. "'", anchor)
   end
   if month == 2 then
      local leap_year = (year % 4 == 0) and not (year % 100 == 0) or (year % 400 == 0)
      if leap_year == false then
         if day > 28 then _error(sm, "Too many days in month. Found " .. day .. " days in February, which only has 28 days if it's not a leap year in: '" .. sm.match .. "'", anchor) end
      end
   end
end
local function assign_time_local(sm, match, hour, min, sec, msec)
   sm.value_type = "time-local"
   if sm.options.parse_datetime_as == "string" then
      sm.value = sm.options.type_conversion[sm.value_type](match)
   else
      sm.value = sm.options.type_conversion[sm.value_type]({ hour = hour, min = min, sec = sec, msec = msec })
   end
end
local function assign_date_local(sm, match, year, month, day)
   sm.value_type = "date-local"
   if sm.options.parse_datetime_as == "string" then
      sm.value = sm.options.type_conversion[sm.value_type](match)
   else
      sm.value = sm.options.type_conversion[sm.value_type]({ year = year, month = month, day = day })
   end
end
local function assign_datetime_local(sm, match, year, month, day, hour, min, sec, msec)
   sm.value_type = "datetime-local"
   if sm.options.parse_datetime_as == "string" then
      sm.value = sm.options.type_conversion[sm.value_type](match)
   else
      sm.value = sm.options.type_conversion[sm.value_type]({ year = year, month = month, day = day, hour = hour, min = min, sec = sec, msec = msec or 0 })
   end
end
local function assign_datetime(sm, match, year, month, day, hour, min, sec, msec, tz)
   if tz then
      local hour_s, min_s
      sm._, sm._, hour_s, min_s = tz:find("^[+-](%d%d):(%d%d)$")
      validate_hours_minutes(sm, _tointeger(hour_s), _tointeger(min_s), "offset-date-time")
   end
   sm.value_type = "datetime"
   if sm.options.parse_datetime_as == "string" then
      sm.value = sm.options.type_conversion[sm.value_type](match)
   else
      sm.value = sm.options.type_conversion[sm.value_type]({ year = year, month = month, day = day, hour = hour, min = min, sec = sec, msec = msec or 0, time_offset = tz or "00:00" })
   end
end
local function validate_datetime(sm, value)
   local hour_s, min_s, sec_s, msec_s
   local hour, min, sec
   sm._, sm._, sm.match, hour_s, min_s, sm.ext = value:find("^((%d%d):(%d%d))(.*)$")
   if sm.match then
      hour, min = _tointeger(hour_s), _tointeger(min_s)
      validate_hours_minutes(sm, hour, min, "local-time")
      if sm.ext ~= "" then
         sm._, sm._, sec_s = sm.ext:find("^:(%d%d)$")
         if sec_s then
            sec = _tointeger(sec_s)
            validate_seconds(sm, sec, "local-time")
            assign_time_local(sm, sm.match .. sm.ext, hour, min, sec, 0)
            return true
         end
         sm._, sm._, sec_s, msec_s = sm.ext:find("^:(%d%d)%.(%d+)$")
         if sec_s then
            sec = _tointeger(sec_s)
            validate_seconds(sm, sec, "local-time")
            assign_time_local(sm, sm.match .. sm.ext, hour, min, sec, _tointeger(msec_s))
            return true
         end
      else
         assign_time_local(sm, sm.match .. ":00", hour, min, 0, 0)
         return true
      end
   end
   local year_s, month_s, day_s
   local year, month, day
   sm._, sm._, sm.match, year_s, month_s, day_s = value:find("^((%d%d%d%d)%-(%d%d)%-(%d%d))$")
   if sm.match then
      year, month, day = _tointeger(year_s), _tointeger(month_s), _tointeger(day_s)
      validate_month_date(sm, year, month, day, "local-date")
      assign_date_local(sm, sm.match, year, month, day)
      local potential_end_seq
      if sm.input:find("^ %d", sm.i) then
         sm._, potential_end_seq, sm.match = sm.input:find("^ ([%S]+)", sm.i)
         value = value .. " " .. sm.match
         sm.end_seq = potential_end_seq
         sm.i = sm.end_seq + 1
      else
         return true
      end
   end
   sm._, sm._, sm.match, year_s, month_s, day_s, hour_s, min_s, sm.ext =
   value:find("^((%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d))(.*)$")
   if sm.match then
      hour, min = _tointeger(hour_s), _tointeger(min_s)
      validate_hours_minutes(sm, hour, min, "local-time")
      year, month, day = _tointeger(year_s), _tointeger(month_s), _tointeger(day_s)
      validate_month_date(sm, year, month, day, "local-date-time")
      local temp_ext
      sm._, sm._, sec_s, temp_ext = sm.ext:find("^:(%d%d)(.*)$")
      if sec_s then
         sec = _tointeger(sec_s)
         validate_seconds(sm, sec, "local-time")
         sm.match = sm.match .. ":" .. sec_s
         sm.ext = temp_ext
      else
         sm.match = sm.match .. ":00"
      end
      if sm.ext ~= "" then
         sm.match = sm.match .. sm.ext
         if sm.ext:find("^%.%d+$") then
            sm._, sm._, msec_s = sm.ext:find("^%.(%d+)Z$")
            assign_datetime_local(sm, sm.match, year, month, day, hour, min, sec, _tointeger(msec_s))
            return true
         elseif sm.ext:find("^%.%d+Z$") then
            sm._, sm._, msec_s = sm.ext:find("^%.(%d+)Z$")
            assign_datetime(sm, sm.match, year, month, day, hour, min, sec, _tointeger(msec_s))
            return true
         elseif sm.ext:find("^%.%d+[+-]%d%d:%d%d$") then
            local tz_s
            sm._, sm._, msec_s, tz_s = sm.ext:find("^%.(%d+)([+-]%d%d:%d%d)$")
            assign_datetime(sm, sm.match, year, month, day, hour, min, sec, _tointeger(msec_s), tz_s)
            return true
         elseif sm.ext:find("^[Zz]$") then
            assign_datetime(sm, sm.match, year, month, day, hour, min, sec)
            return true
         elseif sm.ext:find("^[+-]%d%d:%d%d$") then
            local tz_s
            sm._, sm._, tz_s = sm.ext:find("^([+-]%d%d:%d%d)$")
            assign_datetime(sm, sm.match, year, month, day, hour, min, sec, 0, tz_s)
            return true
         end
      else
         assign_datetime_local(sm, sm.match, year, month, day, hour, min, sec)
         return true
      end
   end
end
local validators = {
   validate_integer,
   validate_float,
   validate_datetime,
}
local exact_matches = {
   ["true"] = { true, "bool" },
   ["false"] = { false, "bool" },
   ["+inf"] = { math.huge, "float" },
   ["inf"] = { math.huge, "float" },
   ["-inf"] = { -math.huge, "float" },
   ["+nan"] = { (0 / 0), "float" },
   ["nan"] = { (0 / 0), "float" },
   ["-nan"] = { (-(0 / 0)), "float" },
}
local function close_other_value(sm)
   local successful_type
   sm._, sm.end_seq, sm.match = sm.input:find("^([^ #\r\n,%[{%]}]+)", sm.i)
   if sm.match == nil then
      _error(sm, "Key has been assigned, but value doesn't seem to exist", "keyvalue-pair")
   end
   sm.i = sm.end_seq + 1
   local value = sm.match
   local exact_value = exact_matches[value]
   if exact_value ~= nil then
      sm.value = exact_value[1]
      sm.value_type = exact_value[2]
      return
   end
   for _, validator in ipairs(validators) do
      successful_type = validator(sm, value)
      if successful_type == true then
         return
      end
   end
   _error(sm, "Unable to determine type of value for: '" .. value .. "'", "keyvalue-pair")
end
local function create_array(sm)
   sm.nested_arrays = sm.nested_arrays + 1
   if sm.nested_arrays >= sm.options.max_nesting_depth then
      _error(sm, "Maximum nesting depth has exceeded " .. sm.options.max_nesting_depth .. ". If this larger nesting depth is required, feel free to set 'max_nesting_depth' in the parser options.")
   end
   sm.arrays[sm.nested_arrays] = {}
   sm.i = sm.i + 1
end
local function add_array_comma(sm)
   table.insert(sm.arrays[sm.nested_arrays], sm.value)
   sm.value = nil
   sm.i = sm.i + 1
end
local function close_array(sm)
   if sm.value ~= nil then
      add_array_comma(sm)
   else
      sm.i = sm.i + 1
   end
   sm.value = sm.arrays[sm.nested_arrays]
   sm.value_type = "array"
   sm.nested_arrays = sm.nested_arrays - 1
   if sm.nested_arrays == 0 then
      return "assign"
   elseif sm.nested_inline_tables > 0
      and sm.inline_table_backup[sm.nested_inline_tables]
      and sm.nested_arrays == sm.inline_table_backup[sm.nested_inline_tables].nested_arrays then
      return "assign"
   else
      return "inside_array"
   end
end
local function create_table(sm)
   sm.tables = {}
   sm.byte = sbyte(sm.input, sm.i + 1)
   if sm.byte == chars.OPEN_BRACKET then
      sm.i = sm.i + 2
      sm.table_type = "arrays_of_tables"
   else
      sm.i = sm.i + 1
      sm.table_type = "table"
   end
end
local function add_table_dot(sm)
   sm.tables[#sm.tables + 1] = sm.value
   sm.i = sm.i + 1
end
local function close_table(sm)
   sm.byte = sbyte(sm.input, sm.i + 1)
   if sm.table_type == "arrays_of_tables" and sm.byte ~= chars.CLOSE_BRACKET then
      _error(sm, "Arrays of Tables should be closed with ']]'", "array-of-tables")
   end
   if sm.byte == chars.CLOSE_BRACKET then
      sm.i = sm.i + 2
   else
      sm.i = sm.i + 1
   end
   sm.tables[#sm.tables + 1] = sm.value
   local out_table = sm.output
   local meta_out_table = sm.meta_table
   for i = 1, #sm.tables - 1 do
      if out_table[sm.tables[i]] == nil then
         out_table[sm.tables[i]] = {}
         out_table = out_table[sm.tables[i]]
         meta_out_table[sm.tables[i]] = { type = "auto-dictionary" }
         meta_out_table = meta_out_table[sm.tables[i]]
      else
         if (meta_out_table[sm.tables[i]]).type == "value" then
            _error(sm, "Cannot override previously definied value '" .. sm.tables[i] .. "' with new table definition: '" .. table.concat(sm.tables, ".") .. "'")
         end
         local next_table = out_table[sm.tables[i]][#out_table[sm.tables[i]]]
         local next_meta_table = meta_out_table[sm.tables[i]][#meta_out_table[sm.tables[i]]]
         if next_table == nil then
            out_table = out_table[sm.tables[i]]
            meta_out_table = meta_out_table[sm.tables[i]]
         else
            out_table = next_table
            meta_out_table = next_meta_table
         end
      end
   end
   local final_table = sm.tables[#sm.tables]
   if sm.table_type == "table" then
      if out_table[final_table] == nil then
         out_table[final_table] = {}
         meta_out_table[final_table] = { type = "dictionary" }
      elseif (meta_out_table[final_table]).type == "value" then
         _error(sm, "Cannot override existing value '" .. sm.value .. "' with new table")
      elseif (meta_out_table[final_table]).type == "dictionary" then
         _error(sm, "Cannot override existing table '" .. sm.value .. "' with new table")
      elseif (meta_out_table[final_table]).type == "array" then
         _error(sm, "Cannot override existing array '" .. sm.value .. "' with new table")
      elseif (meta_out_table[final_table]).type == "value-dictionary" then
         _error(sm, "Cannot override existing value '" .. sm.value .. "' with new table")
      end
      (meta_out_table[final_table]).type = "dictionary"
      sm.current_table = out_table[final_table]
      sm.current_meta_table = meta_out_table[final_table]
   elseif sm.table_type == "arrays_of_tables" then
      if out_table[final_table] == nil then
         out_table[final_table] = {}
         meta_out_table[final_table] = { type = "array" }
      elseif (meta_out_table[final_table]).type == "value" then
         _error(sm, "Cannot override existing value '" .. sm.value .. "' with new table")
      elseif (meta_out_table[final_table]).type == "dictionary" then
         _error(sm, "Cannot override existing table '" .. sm.value .. "' with new table")
      elseif (meta_out_table[final_table]).type == "auto-dictionary" then
         _error(sm, "Cannot override existing table '" .. sm.value .. "' with new table")
      elseif (meta_out_table[final_table]).type == "value-dictionary" then
         _error(sm, "Cannot override existing value '" .. sm.value .. "' with new table")
      end
      table.insert(out_table[final_table], {})
      table.insert(meta_out_table[final_table], { type = "dictionary" })
      sm.current_table = out_table[final_table][#out_table[final_table]]
      sm.current_meta_table = meta_out_table[final_table][#meta_out_table[final_table]]
   end
end
local function assign_key(sm)
   if sm.multiline_string == false then
      sm.keys[#sm.keys + 1] = sm.value
   else
      _error(sm, "Cannot have multi-line string as keys. Found key: '" .. tostring(sm.value) .. "'", "keys")
   end
   sm.value = nil
   sm.value_type = nil
   sm.i = sm.i + 1
end
local function assign_value(sm)
   local output = {}
   output = sm.value
   local out_table = sm.current_table
   local meta_out_table = sm.current_meta_table
   for i = 1, #sm.keys - 1 do
      if out_table[sm.keys[i]] == nil then
         out_table[sm.keys[i]] = {}
         meta_out_table[sm.keys[i]] = { type = "value-dictionary" }
      elseif (meta_out_table[sm.keys[i]]).type == "value" then
         _error(sm, "Cannot override existing value '" .. sm.keys[i] .. "' in '" .. table.concat(sm.keys, ".") .. "'")
      elseif (meta_out_table[sm.keys[i]]).type == "dictionary" then
         _error(sm, "Cannot override existing table '" .. sm.keys[i] .. "' in '" .. table.concat(sm.keys, ".") .. "'")
      elseif (meta_out_table[sm.keys[i]]).type == "array" then
         _error(sm, "Cannot override existing array '" .. sm.keys[i] .. "' in '" .. table.concat(sm.keys, ".") .. "'")
      end
      out_table = out_table[sm.keys[i]]
      meta_out_table = meta_out_table[sm.keys[i]]
   end
   local last_table = sm.keys[#sm.keys]
   if out_table[last_table] ~= nil then
      _error(sm, "Cannot override previously defined key '" .. sm.keys[#sm.keys] .. "'")
   end
   out_table[last_table] = output
   meta_out_table[last_table] = { type = "value" }
   sm.keys = {}
   sm.value = nil
end
local function error_invalid_state(sm)
   local error_message = "Incorrectly formatted TOML. "
   local found = sm.input:sub(sm.i, sm.i); if found == "\r" or found == "\n" then found = "newline character" end
   if sm.mode == "start_of_line" then error_message = error_message .. "At start of line, could not find a key. Found '='"
   elseif sm.mode == "inside_table" then error_message = error_message .. "In a table definition, expected a '.' or ']'. Found: '" .. found .. "'"
   elseif sm.mode == "inside_key" then error_message = error_message .. "In a key defintion, expected a '.' or '='. Found: '" .. found .. "'"
   elseif sm.mode == "value" then error_message = error_message .. "Unspecified value, key was specified, but no value provided."
   elseif sm.mode == "inside_array" then error_message = error_message .. "Inside an array, expected a ']', '}' (if inside inline table), ',', newline, or comment. Found: " .. found
   elseif sm.mode == "wait_for_newline" then error_message = error_message .. "Just assigned value or created table. Expected newline or comment before continuing."
   end
   _error(sm, error_message)
end
local function create_inline_table(sm)
   sm.nested_inline_tables = sm.nested_inline_tables + 1
   if sm.nested_inline_tables >= sm.options.max_nesting_depth then
      _error(sm, "Maximum nesting depth has exceeded " .. sm.options.max_nesting_depth .. ". If this larger nesting depth is required, feel free to set 'max_nesting_depth' in the parser options.")
   end
   local backup = {
      previous_state = sm.mode,
      meta_table = sm.meta_table,
      current_table = sm.current_table,
      keys = { _unpack(sm.keys) },
      nested_arrays = sm.nested_arrays,
   }
   local new_inline_table = {}
   sm.current_table = new_inline_table
   sm.inline_table_backup[sm.nested_inline_tables] = backup
   sm.current_table = {}
   sm.meta_table = {}
   sm.keys = {}
   sm.i = sm.i + 1
end
local function close_inline_table(sm)
   if sm.value ~= nil then
      assign_value(sm)
   end
   sm.i = sm.i + 1
   sm.value = sm.current_table
   sm.value_type = "inline-table"
   local restore = sm.inline_table_backup[sm.nested_inline_tables]
   sm.keys = restore.keys
   sm.meta_table = restore.meta_table
   sm.current_table = restore.current_table
   sm.nested_inline_tables = sm.nested_inline_tables - 1
   if restore.previous_state == "array" then
      return "inside_array"
   elseif restore.previous_state == "value" then
      return "assign"
   else
      _error(sm, "close_inline_table should not be called from the previous state: " .. restore.previous_state .. ". Please submit an issue with your TOML file so we can look into the issue!")
   end
end
local function skip_comma(sm)
   sm.i = sm.i + 1
end
local transitions = {
   ["start_of_line"] = {
      [sbyte("#")] = { find_newline, "start_of_line" },
      [sbyte("\r")] = { find_newline, "start_of_line" },
      [sbyte("\n")] = { find_newline, "start_of_line" },
      [sbyte('"')] = { close_string, "inside_key" },
      [sbyte("'")] = { close_literal_string, "inside_key" },
      [sbyte("[")] = { create_table, "table" },
      [sbyte("=")] = { error_invalid_state, "error" },
      [sbyte("}")] = { close_inline_table, "?" },
      [0] = { close_bare_string, "inside_key" },
   },
   ["table"] = {
      [sbyte('"')] = { close_string, "inside_table" },
      [sbyte("'")] = { close_literal_string, "inside_table" },
      [0] = { close_bare_string, "inside_table" },
   },
   ["inside_table"] = {
      [sbyte(".")] = { add_table_dot, "table" },
      [sbyte("]")] = { close_table, "wait_for_newline" },
      [0] = { error_invalid_state, "error" },
   },
   ["key"] = {
      [sbyte('"')] = { close_string, "inside_key" },
      [sbyte("'")] = { close_literal_string, "inside_key" },
      [sbyte("}")] = { close_inline_table, "?" },
      [sbyte("\r")] = { find_newline, "key" },
      [sbyte("\n")] = { find_newline, "key" },
      [sbyte("#")] = { find_newline, "key" },
      [0] = { close_bare_string, "inside_key" },
   },
   ["inside_key"] = {
      [sbyte(".")] = { assign_key, "key" },
      [sbyte("=")] = { assign_key, "value" },
      [0] = { error_invalid_state, "error" },
   },
   ["value"] = {
      [sbyte("'")] = { close_literal_string, "assign" },
      [sbyte('"')] = { close_string, "assign" },
      [sbyte("{")] = { create_inline_table, "key" },
      [sbyte("[")] = { create_array, "array" },
      [sbyte("\n")] = { error_invalid_state, "error" },
      [sbyte("\r")] = { error_invalid_state, "error" },
      [0] = { close_other_value, "assign" },
   },
   ["array"] = {
      [sbyte("'")] = { close_literal_string, "inside_array" },
      [sbyte('"')] = { close_string, "inside_array" },
      [sbyte("[")] = { create_array, "array" },
      [sbyte("]")] = { close_array, "?" },
      [sbyte("#")] = { find_newline, "array" },
      [sbyte("\r")] = { find_newline, "array" },
      [sbyte("\n")] = { find_newline, "array" },
      [sbyte("{")] = { create_inline_table, "key" },
      [0] = { close_other_value, "inside_array" },
   },
   ["inside_array"] = {
      [sbyte(",")] = { add_array_comma, "array" },
      [sbyte("]")] = { close_array, "?" },
      [sbyte("}")] = { close_inline_table, "?" },
      [sbyte("#")] = { find_newline, "inside_array" },
      [sbyte("\r")] = { find_newline, "inside_array" },
      [sbyte("\n")] = { find_newline, "inside_array" },
      [0] = { error_invalid_state, "error" },
   },
   ["assign"] = {
      [sbyte(",")] = { assign_value, "wait_for_key" },
      [sbyte("}")] = { close_inline_table, "?" },
      [0] = { assign_value, "wait_for_newline" },
   },
   ["wait_for_key"] = {
      [sbyte(",")] = { skip_comma, "key" },
   },
   ["wait_for_newline"] = {
      [sbyte("#")] = { find_newline, "start_of_line" },
      [sbyte("\r")] = { find_newline, "start_of_line" },
      [sbyte("\n")] = { find_newline, "start_of_line" },
      [0] = { error_invalid_state, "error" },
   },
}
local function generic_type_conversion(raw_value) return raw_value end
function tinytoml.parse(filename, options)
   local sm = {}
   local default_options = {
      max_nesting_depth = 1000,
      max_filesize = 100000000,
      load_from_string = false,
      parse_datetime_as = "string",
      type_conversion = {
         ["datetime"] = generic_type_conversion,
         ["datetime-local"] = generic_type_conversion,
         ["date-local"] = generic_type_conversion,
         ["time-local"] = generic_type_conversion,
      },
   }
   if options then
      if options.max_nesting_depth ~= nil then
         assert(type(options.max_nesting_depth) == "number", "the tinytoml option 'max_nesting_depth' takes in a 'number'. You passed in the value '" .. tostring(options.max_nesting_depth) .. "' of type '" .. type(options.max_nesting_depth) .. "'")
      end
      if options.max_filesize ~= nil then
         assert(type(options.max_filesize) == "number", "the tinytoml option 'max_filesize' takes in a 'number'. You passed in the value '" .. tostring(options.max_filesize) .. "' of type '" .. type(options.max_filesize) .. "'")
      end
      if options.load_from_string ~= nil then
         assert(type(options.load_from_string) == "boolean", "the tinytoml option 'load_from_string' takes in a 'function'. You passed in the value '" .. tostring(options.load_from_string) .. "' of type '" .. type(options.load_from_string) .. "'")
      end
      if options.parse_datetime_as ~= nil then
         assert(type(options.parse_datetime_as) == "string", "the tinytoml option 'parse_datetime_as' takes in either the 'string' or 'table' (as type 'string'). You passed in the value '" .. tostring(options.parse_datetime_as) .. "' of type '" .. type(options.parse_datetime_as) .. "'")
      end
      if options.type_conversion ~= nil then
         assert(type(options.type_conversion) == "table", "the tinytoml option 'type_conversion' takes in a 'table'. You passed in the value '" .. tostring(options.type_conversion) .. "' of type '" .. type(options.type_conversion) .. "'")
         for key, value in pairs(options.type_conversion) do
            assert(type(key) == "string")
            if not default_options.type_conversion[key] then
               error("")
            end
            assert(type(value) == "function")
         end
      end
      options.max_nesting_depth = options.max_nesting_depth or default_options.max_nesting_depth
      options.max_filesize = options.max_filesize or default_options.max_filesize
      options.load_from_string = options.load_from_string or default_options.load_from_string
      options.parse_datetime_as = options.parse_datetime_as or default_options.parse_datetime_as
      options.type_conversion = options.type_conversion or default_options.type_conversion
      if options.load_from_string == true then
         sm.input = filename
         sm.filename = "string input"
      end
      for key, value in pairs(default_options.type_conversion) do
         if options.type_conversion[key] == nil then
            options.type_conversion[key] = value
         end
      end
   else
      options = default_options
   end
   sm.options = options
   if options.load_from_string == false then
      local file = io.open(filename, "r")
      if not file then error("Unable to open file: '" .. filename .. "'") end
      if file:seek("end") > options.max_filesize then error("Filesize is larger than 100MB. If this is intentional, please set the 'max_filesize' (in bytes) in options") end
      file:seek("set")
      sm.input = file:read("*all")
      file:close()
      sm.filename = filename
   end
   sm.i = 1
   sm.keys = {}
   sm.arrays = {}
   sm.output = {}
   sm.meta_table = {}
   sm.line_number = 1
   sm.line_number_char_index = 1
   sm.nested_arrays = 0
   sm.inline_table_backup = {}
   sm.nested_inline_tables = 0
   sm.table_type = "table"
   sm.input_length = #sm.input
   sm.current_table = sm.output
   sm.current_meta_table = sm.meta_table
   if sm.input_length == 0 then return {} end
   local valid, line_number, line_number_start, message = validate_utf8(sm.input, true)
   if not valid then
      sm.line_number = line_number
      sm.line_number_char_index = line_number_start
      _error(sm, message, "preliminaries")
   end
   sm.mode = "start_of_line"
   local dynamic_next_mode = "start_of_line"
   local transition = nil
   sm._, sm.i = sm.input:find("[^ \t]", sm.i)
   if not sm.i then return {} end
   while sm.i <= sm.input_length do
      sm.byte = sbyte(sm.input, sm.i)
      transition = transitions[sm.mode][sm.byte]
      if transition == nil then
         transition = transitions[sm.mode][0]
      end
      if transition[2] == "?" then
         dynamic_next_mode = transition[1](sm)
         sm.mode = dynamic_next_mode
      else
         transition[1](sm)
         sm.mode = transition[2]
      end
      sm._, sm.i = sm.input:find("[^ \t]", sm.i)
      if sm.i == nil then
         break
      end
   end
   if sm.mode == "assign" then
      sm.i = sm.input_length
      assign_value(sm)
   end
   if sm.mode == "inside_array" or sm.mode == "array" then
      _error(sm, "Unable to find closing bracket of array", "array")
   end
   if sm.mode == "key" then
      _error(sm, "Incorrect formatting for key", "keys")
   end
   if sm.mode == "value" then
      _error(sm, "Key has been assigned, but value doesn't seem to exist", "keyvalue-pair")
   end
   if sm.nested_inline_tables ~= 0 then
      _error(sm, "Unable to find closing bracket of inline table", "inline-table")
   end
   return sm.output
end
local function is_array(input_table)
   local count = #(input_table)
   return count > 0 and next(input_table, count) == nil
end
local short_sequences = {
   [sbyte('\b')] = '\\b',
   [sbyte('\t')] = '\\t',
   [sbyte('\n')] = '\\n',
   [sbyte('\f')] = '\\f',
   [sbyte('\r')] = '\\r',
   [sbyte('\t')] = '\\t',
   [sbyte('\\')] = '\\\\',
   [sbyte('"')] = '\\"',
}
local function escape_string(str, multiline, is_key)
   if not is_key and #str >= 5 and str:find("%d%d") then
      local sm = { input = str, i = 1, line_number = 1, line_number_char_index = 1 }
      sm.options = {}
      sm.options.type_conversion = {
         ["datetime"] = generic_type_conversion,
         ["datetime-local"] = generic_type_conversion,
         ["date-local"] = generic_type_conversion,
         ["time-local"] = generic_type_conversion,
      }
      sm.options.parse_datetime_as = "string"
      sm._, sm.end_seq, sm.match = sm.input:find("^([^ #\r\n,%[{%]}]+)", sm.i)
      sm.i = sm.end_seq + 1
      if validate_datetime(sm, sm.match) then
         if sm.value_type == "datetime" or sm.value_type == "datetime-local" or
            sm.value_type == "date-local" or sm.value_type == "time-local" then
            return sm.value
         end
      end
   end
   local byte
   local found_newline = false
   local final_string = string.gsub(str, '[%z\001-\031\127\\"]', function(c)
      byte = sbyte(c)
      if short_sequences[byte] then
         if multiline and (byte == chars.CR or byte == chars.LF) then
            found_newline = true
            return c
         else
            return short_sequences[byte]
         end
      else
         return string.format("\\x%02x", byte)
      end
   end)
   if found_newline then
      final_string = '"""' .. final_string .. '"""'
   else
      final_string = '"' .. final_string .. '"'
   end
   if not validate_utf8(final_string, true) then
      error("String is not valid UTF-8, cannot encode to TOML")
   end
   return final_string
end
local function escape_key(str)
   if str:find("^[A-Za-z0-9_-]+$") then
      return str
   else
      return escape_string(str, false, true)
   end
end
local to_inf_and_beyound = {
   ["inf"] = true,
   ["-inf"] = true,
   ["nan"] = true,
   ["-nan"] = true,
}
local function float_to_string(x)
   if to_inf_and_beyound[tostring(x)] then
      return tostring(x)
   end
   for precision = 15, 17 do
      local s = ('%%.%dg'):format(precision):format(x)
      if tonumber(s) == x then
         return s
      end
   end
   return tostring(x)
end
local function encode_element(element, allow_multiline_strings)
   if type(element) == "table" then
      local encoded_string = {}
      if is_array(element) then
         table.insert(encoded_string, "[")
         local remove_trailing_comma = false
         for _, array_element in ipairs(element) do
            remove_trailing_comma = true
            table.insert(encoded_string, encode_element(array_element, allow_multiline_strings))
            table.insert(encoded_string, ", ")
         end
         if remove_trailing_comma then table.remove(encoded_string) end
         table.insert(encoded_string, "]")
         return table.concat(encoded_string)
      else
         table.insert(encoded_string, "{")
         local remove_trailing_comma = false
         for k, v in pairs(element) do
            remove_trailing_comma = true
            table.insert(encoded_string, k)
            table.insert(encoded_string, " = ")
            table.insert(encoded_string, encode_element(v, allow_multiline_strings))
            table.insert(encoded_string, ", ")
         end
         if remove_trailing_comma then table.remove(encoded_string) end
         table.insert(encoded_string, "}")
         return table.concat(encoded_string)
      end
   elseif type(element) == "string" then
      return escape_string(element, allow_multiline_strings, false)
   elseif type(element) == "number" then
      return float_to_string(element)
   elseif type(element) == "boolean" then
      return tostring(element)
   else
      error("Unable to encode type '" .. type(element) .. "' into a TOML type")
   end
end
local function encode_depth(encoded_string, depth)
   table.insert(encoded_string, '\n[')
   table.insert(encoded_string, table.concat(depth, '.'))
   table.insert(encoded_string, ']\n')
end
local function encoder(input_table, encoded_string, depth, options)
   local printed_table_info = false
   for k, v in pairs(input_table) do
      if type(v) ~= "table" or (type(v) == "table" and is_array(v)) then
         if not printed_table_info and #depth > 0 then
            encode_depth(encoded_string, depth)
            printed_table_info = true
         end
         table.insert(encoded_string, escape_key(k))
         table.insert(encoded_string, " = ")
         local status, error_or_encoded_element = pcall(encode_element, v, options.allow_multiline_strings)
         if not status then
            local error_message = { "\n\nWhile encoding '" }
            local _
            if #depth > 0 then
               error_message[#error_message + 1] = table.concat(depth, ".")
               error_message[#error_message + 1] = "."
            end
            error_message[#error_message + 1] = escape_key(k)
            error_message[#error_message + 1] = "', received the following error message:\n\n"
            _, _, error_or_encoded_element = error_or_encoded_element:find(".-:.-: (.*)")
            error_message[#error_message + 1] = error_or_encoded_element
            error(table.concat(error_message))
         end
         table.insert(encoded_string, error_or_encoded_element)
         table.insert(encoded_string, "\n")
      end
   end
   for k, v in pairs(input_table) do
      if type(v) == "table" and not is_array(v) then
         if next(v) == nil then
            table.insert(depth, escape_key(k))
            encode_depth(encoded_string, depth)
            table.remove(depth)
         else
            table.insert(depth, escape_key(k))
            encoder(v, encoded_string, depth, options)
            table.remove(depth)
         end
      end
   end
   return encoded_string
end
function tinytoml.encode(input_table, options)
   options = options or {
      allow_multiline_strings = false,
   }
   return table.concat(encoder(input_table, {}, {}, options))
end
-- ═══════════════════════════════════════════════════════════════════════════════
-- END tinytoml
-- ═══════════════════════════════════════════════════════════════════════════════

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

local get_page_size = ya.sync(function(self)
  local area = self._overlay
  if not area then return 10 end
  local inner = area:pad(ui.Pad(1, 2, 1, 2))
  return math.max(1, inner.h - 2)
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
  cands[#cands + 1] = { on = "<PageUp>", action = "page_up" }
  cands[#cands + 1] = { on = "<PageDown>", action = "page_down" }
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
    elseif cand.action == "page_up" then
      move_cursor(-get_page_size())
    elseif cand.action == "page_down" then
      move_cursor(get_page_size())
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