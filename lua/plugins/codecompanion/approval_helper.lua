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

--- Split command string into tokens while preserving quoted substrings.
--- Supports both POSIX/Windows style quoted paths with spaces.
--- @param cmd_str string
--- @return string[]
local function tokenize(cmd_str)
  local tokens = {}
  local current = ""
  local quote = nil
  local i = 1
  local len = #cmd_str

  while i <= len do
    local c = cmd_str:sub(i, i)

    if quote then
      if c == "\\" and i < len then
        local next_char = cmd_str:sub(i + 1, i + 1)
        if next_char == quote or next_char == "\\" then
          current = current .. next_char
          i = i + 2
        else
          current = current .. c
          i = i + 1
        end
      elseif c == quote then
        quote = nil
        i = i + 1
      else
        current = current .. c
        i = i + 1
      end
    else
      if c == '"' or c == "'" then
        quote = c
        i = i + 1
      elseif c:match("%s") then
        if current ~= "" then
          table.insert(tokens, current)
          current = ""
        end
        i = i + 1
      else
        current = current .. c
        i = i + 1
      end
    end
  end

  if current ~= "" then
    table.insert(tokens, current)
  end

  return tokens
end

--- Normalize executable token across POSIX/Windows shells.
--- @param token string
--- @return string
local function normalize_executable(token)
  local exe = token:match("([^/\\]+)$") or token
  exe = exe:lower()
  exe = exe:gsub("%.exe$", "")
  exe = exe:gsub("%.cmd$", "")
  exe = exe:gsub("%.bat$", "")
  return exe
end

--- Extract the executable name.
--- Example: "FOO=bar /usr/bin/git diff" -> "git"
--- Example: "C:\\Program Files\\Git\\bin\\git.exe status" -> "git"
--- @param cmd_str string
--- @return string|nil
local function get_executable(cmd_str)
  local tokens = tokenize(cmd_str)
  for _, token in ipairs(tokens) do
    if not token:match("^%w+=") then
      return normalize_executable(token)
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
  -- Windows read-only equivalents
  "dir",
  "type",
  "where",
  "more",
  "fc",
  "tree",
  "whoami",
  "hostname",
  "ver",
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

local function normalize_path_for_compare(path)
  local normalized = path:gsub("\\", "/")

  if vim.loop.os_uname().sysname == "Windows_NT" then
    normalized = normalized:lower()
  end

  if normalized ~= "/" then
    normalized = normalized:gsub("/+$", "")
  end
  return normalized
end

--- Allow `cd` only when target stays inside current working directory.
--- @param cmd_str string
--- @return boolean
local function is_allowed_cd_command(cmd_str)
  local tokens = tokenize(cmd_str)

  local i = 2
  while i <= #tokens do
    local t = tokens[i]
    if t == "-L" or t == "-P" or t == "/d" or t == "/D" then
      i = i + 1
    elseif t == "--" then
      i = i + 1
      break
    else
      break
    end
  end

  local target = tokens[i]
  if not target or target == "" then
    return false
  end

  local cwd = vim.loop.cwd()
  if not cwd then
    return false
  end

  local cwd_real = vim.loop.fs_realpath(cwd)
  if not cwd_real then
    return false
  end

  local absolute_target = vim.fn.fnamemodify(target, ":p")
  local target_real = vim.loop.fs_realpath(absolute_target)
  if not target_real then
    return false
  end

  local base = normalize_path_for_compare(cwd_real)
  local candidate = normalize_path_for_compare(target_real)

  return candidate == base or candidate:sub(1, #base + 1) == (base .. "/")
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

  if exe == "cd" then
    return is_allowed_cd_command(cmd_str)
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
