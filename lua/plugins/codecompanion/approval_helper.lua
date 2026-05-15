M = {}

--- Parse a bash command string into a list of individual commands.
--- Handles ;, &&, ||, | as separators. Respects quoted strings.
--- @param cmd_str string
--- @return string[]
local function parse_bash_commands(cmd_str)
  local commands = {}
  local current = ""
  local i = 1
  local len = #cmd_str

  while i <= len do
    local c = cmd_str:sub(i, i)

    -- Handle quoted strings
    if c == "'" or c == '"' then
      local quote = c
      current = current .. c
      i = i + 1
      while i <= len do
        local ch = cmd_str:sub(i, i)
        current = current .. ch
        if ch == quote then break end
        i = i + 1
      end
      i = i + 1
    -- Handle && and ||
    elseif c == "&" and cmd_str:sub(i + 1, i + 1) == "&" then
      local trimmed = current:match("^%s*(.-)%s*$")
      if trimmed ~= "" then commands[#commands + 1] = trimmed end
      current = ""
      i = i + 2
    elseif c == "|" and cmd_str:sub(i + 1, i + 1) == "|" then
      local trimmed = current:match("^%s*(.-)%s*$")
      if trimmed ~= "" then commands[#commands + 1] = trimmed end
      current = ""
      i = i + 2
    -- Handle pipe (single |)
    elseif c == "|" then
      local trimmed = current:match("^%s*(.-)%s*$")
      if trimmed ~= "" then commands[#commands + 1] = trimmed end
      current = ""
      i = i + 1
    -- Handle semicolon
    elseif c == ";" then
      local trimmed = current:match("^%s*(.-)%s*$")
      if trimmed ~= "" then commands[#commands + 1] = trimmed end
      current = ""
      i = i + 1
    else
      current = current .. c
      i = i + 1
    end
  end

  local trimmed = current:match("^%s*(.-)%s*$")
  if trimmed ~= "" then commands[#commands + 1] = trimmed end

  return commands
end

--- Extract the base command name from a command string.
--- Handles env vars prefix (e.g., "FOO=bar ls") by skipping assignments.
--- @param cmd_str string
--- @return string|nil
local function get_executable(cmd_str)
  for token in cmd_str:gmatch("%S+") do
    if not token:match("^%w+=") then
      return token:match("([^/]+)$") -- strip path prefix
    end
  end
  return nil
end

local allowed_set = {}
local allowed_commands= { "ls", "echo", "pwd", "cat", "grep", "find", "head", "tail", "findstr", "wc", "date", "uptime" }

for _, cmd in ipairs(allowed_commands) do
  allowed_set[cmd] = true
end

function M.equire_approval_before_run_command(tool, tools)
  local commands = parse_bash_commands(tool.args.cmd)

  local all_allowed = true
  for _, cmd in ipairs(commands) do
    local exe = get_executable(cmd)
    if not exe or not allowed_set[exe] then
      all_allowed = false
      break
    end
  end

  return not all_allowed
end

return M
