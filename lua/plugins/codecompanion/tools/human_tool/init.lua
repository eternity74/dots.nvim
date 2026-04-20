local config = require("codecompanion.config")
local input_mod = require("plugins.codecompanion.tools.human_tool.input")
local log = require("codecompanion.utils.log")
local render_mod = require("plugins.codecompanion.tools.human_tool.render")
local window_mod = require("plugins.codecompanion.tools.human_tool.window")
local context_mod = require("plugins.codecompanion.tools.human_tool.context")

local human_tool_augroup_id

local M = {
  description = "Communicate with LLM in a Human, allowing the LLM to communicate to the user.",
  name = "human_tool",
  cmds = {
    ---@param self CodeCompanion.Tools
    ---@param args table
    ---@param opts { input: any, output_cb: fun(result: table) }
    ---@return nil
    function(self, args, opts)
      log:debug("HumanTool called with opts: %s", vim.inspect(opts))
      local llm_response = tostring(args.input or "")
      local output_cb = opts.output_cb

      vim.schedule(function()
        if self.chat then
          self.chat:add_buf_message({
            role = config.constants.LLM_ROLE,
            content = llm_response,
          })
        end
        input_mod.open(self.chat, llm_response, output_cb)
      end)
    end,
  },
  system_prompt = [[## HumanTool (`human_tool`)

## CONTEXT
- You have access to a human_tool running within CodeCompanion, in Neovim.
- This tool is the mandatory communication bridge between the human and the LLM.

### OBJECTIVE
- Ensure every assistant response is delivered through `human_tool`.
- This includes:
  1. the first response to the user's initial message,
  2. every follow-up response after messages coming from `human_tool`.

### RESPONSE POLICY
- For every turn, call `human_tool` with the message you want to send to the human.
- Never bypass `human_tool`.
- Use it both to provide information and to ask for clarification.
- When the tool responds `stop`, LLM should stop call human_tool and wait for the next user message to trigger the next response.
]],
  schema = {
    type = "function",
    ["function"] = {
      name = "human_tool",
      description = "A mandatory bridge tool for communicating with the human user. Use it on every turn, including the initial response and all follow-up responses.",
      parameters = {
        type = "object",
        properties = {
          input = {
            type = "string",
            description = "The exact message to send to the human. Every assistant response (initial and follow-up) must be delivered through this field.",
          },
          turn_type = {
            type = "string",
            enum = { "initial", "followup" },
            description = "Classifies whether this is the first response to the user's initial message (`initial`) or a response to subsequent interaction (`followup`).",
          },
        },
        required = { "input" },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  handlers = {
    ---@param self CodeCompanion.Tool.HumanTool
    ---@param meta { tools: CodeCompanion.Tools }
    setup = function(self, meta)
      local chat = meta.tools and meta.tools.chat
      if not chat or not chat.bufnr then
        return
      end

      human_tool_augroup_id = vim.api.nvim_create_augroup("CodeCompanionHumanTool_" .. chat.bufnr, { clear = true })

      vim.api.nvim_create_autocmd("BufWinLeave", {
        group = human_tool_augroup_id,
        buffer = chat.bufnr,
        callback = function()
          window_mod.close()
        end,
      })

      vim.api.nvim_create_autocmd("BufWinEnter", {
        group = human_tool_augroup_id,
        buffer = chat.bufnr,
        callback = function()
          if not input_mod.get_pending_cb() then
            return
          end
          if not window_mod.is_valid_buffer(input_mod.get_buf()) then
            return
          end
          if window_mod.is_valid(window_mod.get()) then
            vim.api.nvim_set_current_win(window_mod.get())
            local line_count = vim.api.nvim_buf_line_count(input_mod.get_buf())
            vim.api.nvim_win_set_cursor(window_mod.get(), { math.max(line_count, 1), 0 })
            vim.cmd("startinsert")
            return
          end

          local win_height = math.max(10, math.floor(vim.o.lines * 0.15))
          local window_id = window_mod.open_under_chat(chat, win_height)
          if not window_id then
            return
          end

          vim.api.nvim_win_set_buf(window_mod.get(), input_mod.get_buf())
          local line_count = vim.api.nvim_buf_line_count(input_mod.get_buf())
          vim.api.nvim_set_current_win(window_id)
          vim.api.nvim_win_set_cursor(window_mod.get(), { math.max(line_count, 1), 0 })
          vim.cmd("startinsert")
        end,
      })
    end,

    ---@param self CodeCompanion.Tool.HumanTool
    ---@param meta { tools: CodeCompanion.Tools }
    on_exit = function(self, meta)
      window_mod.close({ force = true })

      if human_tool_augroup_id then
        pcall(vim.api.nvim_del_augroup_by_id, human_tool_augroup_id)
        human_tool_augroup_id = nil
      end
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.HumanTool
    ---@param stdout table
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local user_input = vim.iter(stdout):flatten():join("\n")
      local replaced_input = render_mod.render_user_input(chat, user_input)

      local lines = vim.split(replaced_input, "\n", { plain = true })
      local out_lines = {}
      local header_trim = vim.trim(context_mod.header)
      local i = 1
      while i <= #lines do
        if vim.trim(lines[i]) == header_trim then
          -- skip the header line and all subsequent lines that start with "> "
          i = i + 1
          while i <= #lines and (lines[i]:sub(1, 2) == "> ") do
            i = i + 1
          end
        else
          table.insert(out_lines, lines[i])
          i = i + 1
        end
      end

      local output_message = table.concat(out_lines, "\n")

      vim.schedule(function()
        if meta.tools.chat then
          meta.tools.chat:add_buf_message({
            role = config.constants.USER_ROLE,
            content = output_message,
          })
        end
      end)

      log:debug("[wanchang] HumanTool success with self.function_call.call_id: %s", self.function_call.call_id)
      return chat:add_tool_output(self, output_message)
    end,

    ---@param self CodeCompanion.Tool.HumanTool
    ---@param stderr table
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      return vim.notify("HumanTool An error occurred", vim.log.levels.ERROR)
    end,
  },
}

return M
