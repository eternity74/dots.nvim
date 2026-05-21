--- Monkey-patch: Add streaming floating window to shell command tool execution.
--- Shows real-time stdout in a floating window while tools run shell commands.
local log = require("codecompanion.utils.log")

local M = {}

local did_setup = false

---Strip ANSI color codes
---@param tbl table
---@return table
local function strip_ansi(tbl)
  for i, v in ipairs(tbl) do
    tbl[i] = v:gsub("\027%[[0-9;]*%a", "")
  end
  return tbl
end

---Execute a shell command with optional stdout streaming
---@param cmd table
---@param on_stdout? function
---@param callback function
local function execute_shell_command_streaming(cmd, on_stdout, callback)
  local os_utils = require("codecompanion.utils.os")
  local opts = {}
  if on_stdout then
    opts.stdout = on_stdout
  end
  if vim.fn.has("win32") == 1 then
    local shell_cmd = table.concat(cmd, " ") .. "\r\nEXIT %ERRORLEVEL%\r\n"
    opts.stdin = shell_cmd
    opts.env = { PROMPT = "\r\n" }
    vim.system({ "cmd.exe", "/Q", "/K" }, opts, callback)
  else
    vim.system(os_utils.build_shell_command(cmd), opts, callback)
  end
end

---Create a streaming cmd function that shows output in a floating window
---@param cmd table The command array
---@param flag? string Optional flag to set on completion
---@return function
local function make_streaming_cmd_fn(cmd, flag)
  ---@param tools CodeCompanion.Tools
  return function(tools, _, opts)
    local cb = vim.schedule_wrap(opts.output_cb)
    local stream_enabled = vim.g.codecompanion_stream_tool_output ~= false

    local stream_bufnr, stream_winnr
    local stream_lines = {}
    local stream_max_lines = 500
    local stdout_chunks = {}

    local on_stdout = stream_enabled and function(_, data)
      if not data then
        return
      end
      table.insert(stdout_chunks, data)

      vim.schedule(function()
        -- Create floating window on first chunk
        if not stream_bufnr or not vim.api.nvim_buf_is_valid(stream_bufnr) then
          stream_bufnr = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_set_option_value("filetype", "log", { buf = stream_bufnr })
          vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = stream_bufnr })
          local width = math.floor(vim.o.columns * 0.4)
          local height = math.floor(vim.o.lines * 0.25)
          stream_winnr = vim.api.nvim_open_win(stream_bufnr, false, {
            relative = "editor",
            anchor = "SE",
            border = "rounded",
            width = width,
            height = height,
            row = vim.o.lines - 2,
            col = vim.o.columns,
            title = " " .. table.concat(cmd, " ") .. " ",
            title_pos = "center",
            style = "minimal",
          })
        end

        -- Append new lines
        local new_lines = vim.split(data, "\n", { trimempty = false })
        for _, line in ipairs(new_lines) do
          if line ~= "" then
            table.insert(stream_lines, strip_ansi({ line })[1])
          end
        end

        -- Trim to max lines
        if #stream_lines > stream_max_lines then
          stream_lines = vim.list_slice(stream_lines, #stream_lines - stream_max_lines + 1, #stream_lines)
        end

        if stream_bufnr and vim.api.nvim_buf_is_valid(stream_bufnr) then
          vim.api.nvim_buf_set_lines(stream_bufnr, 0, -1, false, stream_lines)
          if stream_winnr and vim.api.nvim_win_is_valid(stream_winnr) and #stream_lines > 0 then
            vim.api.nvim_win_set_cursor(stream_winnr, { #stream_lines, 0 })
            vim.api.nvim_win_call(stream_winnr, function()
              vim.cmd("normal! zb")
            end)
          end
        end
        vim.cmd("redraw")
      end)
    end or nil

    local function close_stream_window()
      vim.defer_fn(function()
        if stream_winnr and vim.api.nvim_win_is_valid(stream_winnr) then
          vim.api.nvim_win_close(stream_winnr, true)
        end
      end, 3000)
    end

    execute_shell_command_streaming(cmd, on_stdout, function(out)
      vim.schedule(close_stream_window)

      if flag then
        tools.chat.tool_registry.flags = tools.chat.tool_registry.flags or {}
        tools.chat.tool_registry.flags[flag] = (out.code == 0)
      end

      local eol_pattern = vim.fn.has("win32") == 1 and "\r?\n" or "\n"

      if out.code == 0 then
        local stdout = (#stdout_chunks > 0) and table.concat(stdout_chunks, "") or (out.stdout or "")
        local stdout_data = strip_ansi(vim.split(stdout, eol_pattern, { trimempty = true }))
        cb({ status = "success", data = stdout_data })
      else
        local combined = {}
        if out.stderr and out.stderr ~= "" then
          vim.list_extend(combined, strip_ansi(vim.split(out.stderr, eol_pattern, { trimempty = true })))
        end
        if out.stdout and out.stdout ~= "" then
          vim.list_extend(combined, strip_ansi(vim.split(out.stdout, eol_pattern, { trimempty = true })))
        end
        cb({ status = "error", data = combined })
      end
    end)
  end
end

function M.setup()
  if did_setup then
    log:debug("[cc_patch][orchestrator_streaming] setup skipped (already applied)")
    return
  end
  log:debug("[cc_patch][orchestrator_streaming] setup start")
  did_setup = true

  vim.defer_fn(function()
    local ok, Orchestrator = pcall(require, "codecompanion.interactions.chat.tools.orchestrator")
    if not ok or not Orchestrator then
      log:warn("[cc_patch][orchestrator_streaming] orchestrator module not available; patch skipped")
      return
    end

    -- Patch setup_next_tool: before cmd_to_func_tool runs, convert cmd entries
    -- to streaming functions. cmd_to_func_tool skips entries that are already functions.
    local original_setup_next_tool = Orchestrator.setup_next_tool
    if type(original_setup_next_tool) ~= "function" then
      log:warn("[cc_patch][orchestrator_streaming] setup_next_tool is not a function; patch skipped")
      return
    end

    log:info("[cc_patch][orchestrator_streaming] patched Orchestrator.setup_next_tool")
    Orchestrator.setup_next_tool = function(self, input)
      -- Let original pop from queue and call handlers.setup()
      -- But we need to intercept BEFORE cmd_to_func_tool is called.
      -- Since we can't split the original, we pre-convert cmds after queue pop.

      if self.queue:is_empty() then
        return original_setup_next_tool(self, input)
      end

      -- Peek at the next tool's cmds and convert cmd tables to streaming functions
      local next_tool = self.queue:peek()
      if next_tool and next_tool.cmds then
        for i, cmd_entry in ipairs(next_tool.cmds) do
          if type(cmd_entry) ~= "function" then
            local flag = cmd_entry.flag
            local cmd = cmd_entry.cmd or cmd_entry
            if type(cmd) == "string" then
              cmd = vim.split(cmd, " ", { trimempty = true })
            end
            if type(cmd) == "table" then
              next_tool.cmds[i] = make_streaming_cmd_fn(cmd, flag)
            end
          end
        end
      end

      return original_setup_next_tool(self, input)
    end
  end, 50)
end

return M
