local curl = require("plenary.curl")

local plugin_enabled = vim.g.ai_plugin == "codecompanion"

local storage_path = vim.fn.stdpath("data") .. "/myplugin.json"
-- Avoid unconditional deletion to prevent accidental data loss
-- os.remove(storage_path)

local fmt = string.format

local opts_extensions = require("plugins.codecompanion.extensions_config")
local prompt_library = require("plugins.codecompanion.prompt_library")

-- Default model
local DEFAULT_MODEL = "gpt-5.1-codex-mini"  -- 0.33x
local DEFAULT_MODEL = "gpt-4.1"             -- 0x
local DEFAULT_MODEL = "gpt-5-mini"          -- 0x

-- Adapter helpers
local function make_default_adapter()
  return { name = "copilot", model = DEFAULT_MODEL }
end

local function copilot_cli_factory()
  return require("codecompanion.adapters").extend("copilot_cli", {})
end

-- Tools defaults
local DEFAULT_TOOLS = { "agent_skills", "human_tool" }
local default_tools_opts = {
  default_tools = DEFAULT_TOOLS,
  system_prompt = { enabled = true, replace_main_system_prompt = false },
}
local read_file_tool_opts = {
  opts = {
    require_approval_before = false,
    require_cmd_approval = false,
  },
}

local function make_chat_interaction()
  return {
    adapter = make_default_adapter(),
    tools = {
      -- add human_tool with a named command inside cmds
      human_tool = require("plugins.codecompanion.tools.human_tool"),
      --[[
      human_tool = {
        description = "On every response call this tool to get further instruction from the user. This tool should be called at least once in every response unless the user explicitly tells 'stop'",
        name = "human_tool",
        cmds = {
---@param self CodeCompanion.Tool.HumanTool
          ---@param args table The arguments from the LLM's tool call
          ---@param opts { input: any, output_cb: fun(result: table) }
          ---@return nil|{ status: "success"|"error", data: string }
          function(self, args, opts)
            -- Notify and record incoming input.
            local input = args.input or ""
            vim.notify(input, vim.log.levels.INFO)
            self.chat:add_tool_output(self.tool, input)

            -- Create or reuse a scratch buffer stored on self.
            local bufnr = self._human_input_bufnr
            local buf_name = "CodeCompanion:HumanInput"
            if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
              -- If a buffer with the desired name already exists, reuse it instead of creating a new one.
              local existing = vim.fn.bufnr(buf_name)
              if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
                bufnr = existing
              else
                bufnr = vim.api.nvim_create_buf(false, true) -- listed=false, scratch=true
                -- Set buffer name only when it does not collide with another buffer.
                if vim.fn.bufnr(buf_name) == -1 then
                  pcall(vim.api.nvim_buf_set_name, bufnr, buf_name)
                end

                -- Set buffer options for a temporary editing buffer.
                vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
                vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
                vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
                vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

                -- Create a buffer-local user command to finish editing.
                -- This command will call the provided output callback instead of resuming a coroutine.
                pcall(function()
                  vim.api.nvim_buf_create_user_command(bufnr, "CCFinish", function()
                    -- Collect buffer contents and invoke the async callback.
                    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
                    local result = table.concat(lines, "\n")
                    -- Call the provided output callback if available.
                    if opts and type(opts.output_cb) == "function" then
                      pcall(opts.output_cb, { status = "success", data = tostring(result) })
                    else
                      -- Fallback: store result on self for consumers that read it later.
                      self._human_input_result = tostring(result)
                    end
                    -- Cleanup pointer so buffer can be recreated next time.
                    self._human_input_bufnr = nil
                  end, { desc = "Finish editing and return content to CodeCompanion" })
                end)

                -- Add buffer-local keymaps for Ctrl-S to finish editing.
                -- These mappings call the CCFinish command in Normal/Visual, and exit Insert then run CCFinish in Insert.
                pcall(function()
                  -- Normal mode mapping
                  vim.api.nvim_buf_set_keymap(bufnr, "n", "<C-s>", ":CCFinish<CR>", { noremap = true, silent = true })
                  -- Insert mode mapping: exit insert and run CCFinish
                  vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-s>", "<Esc>:CCFinish<CR>", { noremap = true, silent = true })
                  -- Visual mode mapping
                  vim.api.nvim_buf_set_keymap(bufnr, "v", "<C-s>", ":<C-u>CCFinish<CR>", { noremap = true, silent = true })
                end)

                -- Cleanup pointer if buffer gets detached/deleted.
                vim.api.nvim_buf_attach(bufnr, false, {
                  on_detach = function()
                    self._human_input_bufnr = nil
                  end,
                })
              end

              self._human_input_bufnr = bufnr
            else
              -- Ensure a CCFinish command exists on reused buffer; attempt to create it safely.
              pcall(function()
                vim.api.nvim_buf_create_user_command(bufnr, "CCFinish", function()
                  vim.notify("CCFinish command executed", vim.log.levels.INFO)
                  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
                  local result = table.concat(lines, "\n")
                  if opts and type(opts.output_cb) == "function" then
                    pcall(opts.output_cb, { status = "success", data = tostring(result) })
                  else
                    self._human_input_result = tostring(result)
                  end
                  self._human_input_bufnr = nil
                end, { desc = "Finish editing and return content to CodeCompanion" })

                -- Re-apply buffer-local keymaps on reused buffer (safe to overwrite).
                vim.api.nvim_buf_set_keymap(bufnr, "n", "<C-s>", ":CCFinish<CR>", { noremap = true, silent = true })
                vim.api.nvim_buf_set_keymap(bufnr, "i", "<C-s>", "<Esc>:CCFinish<CR>", { noremap = true, silent = true })
                vim.api.nvim_buf_set_keymap(bufnr, "v", "<C-s>", ":<C-u>CCFinish<CR>", { noremap = true, silent = true })
              end)
            end

            -- Populate buffer with the incoming input.
            local lines = {}
            for s in string.gmatch(input, "([^\n]*)\n?") do table.insert(lines, s) end
            if #lines == 0 then lines = { "" } end
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

            -- Show the buffer in a reuse-friendly way: reuse an existing window showing the buf
            local winid
            for _, w in ipairs(vim.api.nvim_list_wins()) do
              if vim.api.nvim_win_get_buf(w) == bufnr then
                winid = w
                break
              end
            end

            if not winid or not vim.api.nvim_win_is_valid(winid) then
              -- Open a split and show the buffer (adjust size as needed).
              vim.cmd("belowright split")
              winid = vim.api.nvim_get_current_win()
              vim.api.nvim_win_set_buf(winid, bufnr)
              vim.api.nvim_win_set_height(winid, math.max(6, math.floor(vim.o.lines * 0.20)))
            else
              vim.api.nvim_set_current_win(winid)
            end

            -- Move cursor to end for convenience.
            local last = math.max(1, vim.api.nvim_buf_line_count(bufnr))
            pcall(vim.api.nvim_win_set_cursor, winid, { last, 0 })

            -- Do not yield here; the result will be delivered asynchronously via opts.output_cb
          end,
        },
        system_prompt = [[# Human Tool (`human_tool`)
Use this tool to request further instructions from the human. This tool must be called at least once per response. 
],
        schema = {
          type = "function",
          ["function"] = {
            name = "human_tool",
            description = "A tool to get further instruction from the user. This tool should be called at least once in every response with all LLM output instructions unless the user explicitly tells 'stop'.",
            parameters = {
              type = "object",
              properties = {
                input = {
                  type = "string",
                  description = "All output from the LLM to the human. This should be a message describing what the LLM answer for the previous chat. The human will see this message and continue chat.",
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
            return vim.notify("setup function called for human_tool", vim.log.levels.INFO)
          end,
          ---@param self CodeCompanion.Tool.HumanTool
          ---@param meta { tools: CodeCompanion.Tools }
          on_exit = function(self, meta)
            return vim.notify("on_exit function called for human_tool", vim.log.levels.INFO)
          end,
        },
        output = {
          ---@param self CodeCompanion.Tool.HumanTool
          ---@param stdout table
          ---@param meta { tools: CodeCompanion.Tools, cmd: table }
          success = function(self, stdout, meta)
            local chat = meta.tools.chat
            return chat:add_tool_output(self, tostring(stdout[1]))
          end,
          ---@param self CodeCompanion.Tool.HumanTool
          ---@param stderr table The error output from the tool command
          ---@param meta { tools: CodeCompanion.Tools, cmd: table }
          error = function(self, stderr, meta)
            return vim.notify("Error in human_tool: " .. table.concat(stderr, "\n"), vim.log.levels.ERROR)
          end,
        },
      },
      --]]
      opts = default_tools_opts,
      read_file = read_file_tool_opts,
    },
    roles = {
      user = "wanchnag.ryu",
    },
    opts = {
      ---@param ctx CodeCompanion.SystemPrompt.Context
      ---@return string
      system_prompt = function(ctx)
        return ctx.default_system_prompt
          .. fmt(
            [[Additional context:
All non-code text responses must be written in the %s language.
All comment on the code must use english.
The current date is %s.
The user's Neovim verion is %s.
The user is working on a %s machine. Please respond with system specific commands if applicable.
]],
            ctx.language,
            ctx.date,
            ctx.neovim_version,
            ctx.os
          )
      end,
    },
    streaming = true,
    keymaps = {
      send = {
        modes = { n = "<C-s>", i = "<C-s>" },
        opts = {},
      },
    },
  }
end

local cc_config = function(_, opts)
  local config = require("codecompanion.config")
  local util = require("codecompanion.utils")

  opts = opts or {}

  local defaults = {
    prompt_library = prompt_library,
    adapters = {
      acp = {
        copilot_cli = copilot_cli_factory,
      },
    },
    inline = { layout = "buffer" },
    interactions = {
      chat = make_chat_interaction(),
      inline = {
        adapter = "copilot",
        model = DEFAULT_MODEL,
        variables = {
          ["hfile"] = {
            callback = function()
              -- get current buffer's filename and return file content with filename
              local util = require("codecompanion.utils")
              local filename = util.get_current_buffer_filename()
              -- convert filename to header filename
              local header_filename = filename:gsub("%.cpp$", ".h"):gsub("%.c$", ".h"):gsub("%.cc$", ".h")
              -- return early if header file does not exist
              if vim.fn.filereadable(header_filename) == 0 then
                return ""
              end
              local file_content = util.read_file_content(header_filename)
              return "// " .. header_filename .. "\n" .. file_content
            end,
            description = "header file",
            opts = {
              contains_code = true,
            },
          },
        },
      },
    },
    -- DISPLAY OPTIONS ---------------------------------------------------
    display = {
      chat = {
        icons = {
          pinned_buffer = " ",
          watched_buffer = "👀 ",
        },
        window = {
          layout = "vertical", -- float|vertical|horizontal|buffer
        },
      },
      diff = {
        provider = "mini_diff",
        enabled = false,
      },
    },
    extensions = opts_extensions,
    -- GENERAL OPTIONS ---------------------------------------------------
    opts = {
      language = "korean",
      log_level = "DEBUG", -- TRACE|DEBUG|ERROR|INFO
    },
  }

  -- Merge defaults with user options: user-provided opts override defaults
  opts = vim.tbl_deep_extend("force", defaults, opts)

  require('codecompanion').setup(opts)
  require('plugins.codecompanion.utils.extmarks').setup()
  require('plugins.codecompanion.approval_handler').setup()
end

return {
  {
    "olimorris/codecompanion.nvim",
    lazy = false,
    cmd = {
      "CodeCompanion",
      "CodeCompanionActions",
      "CodeCompanionChat",
      "CodeCompanionCmd",
    },
    enabled = plugin_enabled,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      { 'MeanderingProgrammer/render-markdown.nvim', ft = { 'markdown', 'codecompanion' } },
      "ravitemer/codecompanion-history.nvim",
      --"ttgrules/cc-adapter-copilot-cli-acp", -- for copilot-cli
      "cairijun/codecompanion-agentskills.nvim", -- for skills
    },
    config = cc_config,
    keys = {
      {
        "<leader>aa",
        "<cmd>CodeCompanionActions<cr>",
        mode = { "n", "v" },
        noremap = true,
        silent = true,
        desc = "CodeCompanion actions",
      },
      {
        "<leader>ac",
        "<cmd>CodeCompanionChat Toggle<cr>",
        mode = { "n", "v" },
        noremap = true,
        silent = true,
        desc = "CodeCompanion chat",
      },
      {
        "<leader>ad",
        "<cmd>CodeCompanionChat Add<cr>",
        mode = "v",
        noremap = true,
        silent = true,
        desc = "CodeCompanion add to chat",
      }
    },
  },
  {
    "zbirenbaum/copilot.lua",
    enabled = plugin_enabled,
    cmd = "Copilot",
    build = ":Copilot auth",
    event = "BufReadPost",
    opts = {
      suggestion = {
        enabled = not vim.g.ai_cmp,
        auto_trigger = true,
        hide_during_completion = vim.g.ai_cmp,
        keymap = {
          accept = "<TAB>", -- not vim.g.ai_cmp and "<TAB>" or false,
          next = "<M-]>",
          prev = "<M-[>",
        },
      },
      panel = { enabledd = true, auto_refresh = true },
      filetypes = { markdown = true, help = true },
    },
  },
}

