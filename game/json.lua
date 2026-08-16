-- game/json.lua — Mini-JSON fuer session.json (Skill Par. 6):
-- Encoder mit sortierten Schluesseln und %.17g, kleiner rekursiver Parser.
-- Kein loadstring auf Save-Dateien; die Datei ist ein Betriebsmittel, das
-- ein Mensch notfalls im Editor flicken kann.

local J = {}

local function esc(s)
  return s:gsub('[\\"]', '\\%0'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
end

function J.encode(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then return string.format("%.17g", v) end
  if t == "string" then return '"' .. esc(v) .. '"' end
  if t == "table" then
    if #v > 0 or next(v) == nil then -- Liste (oder leer)
      local parts = {}
      for i = 1, #v do parts[i] = J.encode(v[i], indent) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys) -- kanonisch (Skill Par. 4)
    local parts = {}
    local inner = indent .. "  "
    for _, k in ipairs(keys) do
      parts[#parts + 1] = inner .. '"' .. esc(k) .. '": ' .. J.encode(v[k], inner)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  error("nicht serialisierbar: " .. t)
end

-- ---------------------------------------------------------------------------
local function skip_ws(s, i)
  local _, j = s:find("^[ \t\r\n]*", i)
  return j + 1
end

local parse_value

local function parse_string(s, i)
  local out, j = {}, i + 1
  while j <= #s do
    local c = s:sub(j, j)
    if c == '"' then return table.concat(out), j + 1 end
    if c == "\\" then
      local n = s:sub(j + 1, j + 1)
      local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
      out[#out + 1] = map[n] or n
      j = j + 2
    else
      out[#out + 1] = c
      j = j + 1
    end
  end
  return nil, j, "unbeendeter String"
end

parse_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local obj = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
      local key
      key, i = parse_string(s, skip_ws(s, i))
      if key == nil then return nil, i, "Schluessel erwartet" end
      i = skip_ws(s, i)
      if s:sub(i, i) ~= ":" then return nil, i, "Doppelpunkt erwartet" end
      local val, err
      val, i, err = parse_value(s, i + 1)
      if err then return nil, i, err end
      obj[key] = val
      i = skip_ws(s, i)
      local d = s:sub(i, i)
      if d == "," then i = i + 1
      elseif d == "}" then return obj, i + 1
      else return nil, i, "Komma oder } erwartet" end
    end
  elseif c == "[" then
    local arr = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == "]" then return arr, i + 1 end
    while true do
      local val, err
      val, i, err = parse_value(s, i)
      if err then return nil, i, err end
      arr[#arr + 1] = val
      i = skip_ws(s, i)
      local d = s:sub(i, i)
      if d == "," then i = i + 1
      elseif d == "]" then return arr, i + 1
      else return nil, i, "Komma oder ] erwartet" end
    end
  elseif c == '"' then
    return parse_string(s, i)
  elseif s:sub(i, i + 3) == "true" then return true, i + 4
  elseif s:sub(i, i + 4) == "false" then return false, i + 5
  elseif s:sub(i, i + 3) == "null" then return nil, i + 4
  else
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if num and #num > 0 then return tonumber(num), i + #num end
    return nil, i, "unerwartetes Zeichen '" .. c .. "'"
  end
end

function J.decode(s)
  if type(s) ~= "string" then return nil, "kein String" end
  local val, i, err = parse_value(s, 1)
  if err then return nil, err .. " (Position " .. i .. ")" end
  return val
end

return J
