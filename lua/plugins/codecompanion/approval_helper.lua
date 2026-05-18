local M = {}

--- Parse a bash command string into a list of individual commands.
--- Handles separators (;, &&, ||, |) while preserving quoted text.
--- @param cmd_str string
--- @return string[]
local function parse_bash_commands(cmd_str)
  local commands = {}
  local current = ""
  local i = 1
  local len = #cmd_str

  while i <= len do
    local c = cmd_str:sub(i, i)

    -- Keep quoted strings intact so separators inside quotes are ignored.
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
    elseif c == "|" then
      local trimmed = current:match("^%s*(.-)%s*$")
      if trimmed ~= "" then commands[#commands + 1] = trimmed end
      current = ""
      i = i + 1
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

--- Split a command string into whitespace-separated tokens.
--- @param cmd_str string
--- @return string[]
local function tokenize(cmd_str)
  local tokens = {}
  for token in cmd_str:gmatch("%S+") do
    table.insert(tokens, token)
  end
  return tokens
end

--- Extract the executable name.
--- Example: "FOO=bar /usr/bin/git diff" -> "git"
--- @param cmd_str string
--- @return string|nil
local function get_executable(cmd_str)
  for token in cmd_str:gmatch("%S+") do
    if not token:match("^%w+=") then
      return token:match("([^/]+)$")
    end
  end
  return nil
end

local function to_set(items)
  local set = {}
  for _, item in ipairs(items) do
    set[item] = true
  end
  return set
end

-- Standalone read-only commands that are safe to run directly.
local allowed_commands = to_set({
  "ls",
  "echo",
  "pwd",
  "cat",
  "grep",
  "rg",
  "find",
  "head",
  "tail",
  "findstr",
  "wc",
  "date",
  "uptime",
  "sed",
  "awk",
  "sort",
  "uniq",
  "cut",
  "tr",
  "stat",
  "file",
  "realpath",
})

-- Subcommand-level allowlist for tools that mix read/write operations.
local allowed_git_subcommands = to_set({
  "diff",
  "status",
  "log",
  "show",
  "rev-parse",
  "branch",
  "ls-files",
})

--- Find git subcommand while skipping global options.
--- Supports forms like:
---   git -C <path> diff
---   git --git-dir=/path --work-tree=/path status
--- @param tokens string[]
--- @return string|nil
local function extract_git_subcommand(tokens)
  local i = 2 -- token 1 is executable (`git`)

  while i <= #tokens do
    local t = tokens[i]

    if t == "-C" or t == "-c" or t == "--git-dir" or t == "--work-tree" then
      i = i + 2
    elseif t:match("^%-%-git%-dir=") or t:match("^%-%-work%-tree=") then
      i = i + 1
    elseif t:sub(1, 1) == "-" then
      i = i + 1
    else
      return t
    end
  end

  return nil
end

--- Validate read-only git usage.
--- @param cmd_str string
--- @return boolean
local function is_allowed_git_read_command(cmd_str)
  local tokens = tokenize(cmd_str)
  local subcmd = extract_git_subcommand(tokens)
  return subcmd ~= nil and allowed_git_subcommands[subcmd] == true
end

--- Check if a single shell command is allowlisted.
--- @param cmd_str string
--- @return boolean
local function is_allowlisted_command(cmd_str)
  local exe = get_executable(cmd_str)
  if not exe then
    return false
  end

  if exe == "git" then
    return is_allowed_git_read_command(cmd_str)
  end

  return allowed_commands[exe] == true
end

function M.require_approval_before_run_command(tool, tools)
  local commands = parse_bash_commands(tool.args.cmd or "")

  for _, cmd in ipairs(commands) do
    if not is_allowlisted_command(cmd) then
      return true
    end
  end

  return false
end

return M
