local curl = require("plenary.curl")

local plugin_enabled = vim.g.ai_plugin == "codecompanion"

local storage_path = vim.fn.stdpath("data") .. "/myplugin.json"
-- Avoid unconditional deletion to prevent accidental data loss
-- os.remove(storage_path)

local fmt = string.format

local opts_extensions = require("plugins.codecompanion.extensions_config")
local prompt_library = require("plugins.codecompanion.prompt_library")
local approval_helper = require("plugins.codecompanion.approval_helper")

-- Default model
local DEFAULT_MODEL = "gpt-5.1-codex-mini"  -- 0.33x
local DEFAULT_MODEL = "gpt-5.3-codex"       -- 1x
local DEFAULT_MODEL = "claude-sonnet-4"    -- 1x
local DEFAULT_MODEL = "claude-haiku-4.5"    -- 0.33x
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
local allowed_tool_opts = {
  opts = {
    require_approval_before = false,
    require_cmd_approval = false,
  },
}


-- Workaround for stale tool-group state:
-- When a group is removed via context reconciliation, group metadata can remain
-- while all member tools are already detached from `in_use`.
-- In that case, re-adding the same group is blocked by `add_group`'s early return.
local function apply_tool_registry_group_readd_patch()
  local ok, ToolRegistry = pcall(require, "codecompanion.interactions.chat.tool_registry")
  if not ok or ToolRegistry._patched_add_group_readd then
    return
  end

  local original_add_group = ToolRegistry.add_group
  if type(original_add_group) ~= "function" then
    return
  end

  ToolRegistry.add_group = function(self, group, add_opts)
    -- If the group entry exists but none of its tools are active anymore,
    -- treat it as stale and clear it so the group can be added again.
    local group_tools = self.groups and self.groups[group]
    if type(group_tools) == "table" then
      local has_active_tool = false
      for _, tool_name in ipairs(group_tools) do
        if self.in_use and self.in_use[tool_name] then
          has_active_tool = true
          break
        end
      end

      if not has_active_tool then
        self.groups[group] = nil
      end
    end

    return original_add_group(self, group, add_opts)
  end

  -- Guard to ensure this monkey patch is applied only once per session.
  ToolRegistry._patched_add_group_readd = true
end


local function make_chat_interaction()
  return {
    adapter = make_default_adapter(),
    tools = {
      -- add human_tool with a named command inside cmds
      human_tool = require("plugins.codecompanion.tools.human_tool"),
      opts = default_tools_opts,
      read_file = allowed_tool_opts,
      grep_search = allowed_tool_opts,
      ["run_command"] = {
        opts = {
          require_approval_before = approval_helper.require_approval_before_run_command,
          require_cmd_approval = true,
        },
      },
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
        callback = function(chat)
          local ok, input_mod = pcall(require, "plugins.codecompanion.tools.human_tool.input")
          if ok and input_mod.get_pending_cb() then
            local handled = input_mod.submit()
            if handled then
              return
            end
          end
          chat:submit()
        end,
        opts = {},
      },
    },
  }
end

local cc_config = function(_, opts)
  opts = opts or {}

  local defaults = {
    prompt_library = prompt_library,
    adapters = {
      acp = {
        copilot_cli = copilot_cli_factory,
      },
      http = {
        copilot = function()
          return require("codecompanion.adapters").extend("copilot", {
            -- https://codecompanion.olimorris.dev/configuration/adapters-http#changing-adapter-schema
            schema = {
              top_p = {
                ---@type fun(self: CodeCompanion.HTTPAdapter): boolean | boolean
                enabled = function(self)
                  local model = self.schema.model.default
                  if model:find("5.4") then
                    return false
                  end
                  return true
                end
              },
            },
          })
        end,
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
  -- Apply the group re-add workaround after CodeCompanion initializes internals.
  apply_tool_registry_group_readd_patch()
  require('plugins.codecompanion.utils.extmarks').setup()
  require('plugins.codecompanion.approval_handler').setup()
  require('plugins.codecompanion.tools.human_tool.history_preprocess').setup()
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
      },
      {
        "<leader>sz",
        "<cmd>CodeCompanion /human-tool-claude<cr>",
        mode = { "n", "v" },
        noremap = true,
        silent = true,
        desc = "CodeCompanion agentic-human-tool prompt with claude",
      },
      {
        "<leader>sd",
        "<cmd>CodeCompanion /human-tool-gpt<cr>",
        mode = { "n", "v" },
        noremap = true,
        silent = true,
        desc = "CodeCompanion agentic-human-tool prompt with gpt",
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

