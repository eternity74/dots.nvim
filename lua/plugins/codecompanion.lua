local curl = require("plenary.curl")

local plugin_enabled = vim.g.ai_plugin == "codecompanion"

local storage_path = vim.fn.stdpath("data") .. "/myplugin.json"
os.remove(storage_path)

local fmt = string.format

local opts_extensions = require("plugins.codecompanion.extensions_config")
local prompt_library = require("plugins.codecompanion.prompt_library")

--local default_model = "gemini-3-flash-preview"
-- local default_model = "claude-haiku-4.5"
--local default_model = "gpt-5.1-codex-mini"
local default_model = "gpt-5-mini"

local default_adapter = {
  name = "copilot",
  model = default_model,
}

local cc_config = function(_, opts)
  local config = require("codecompanion.config")
  local util = require("codecompanion.utils")
  opts = vim.tbl_deep_extend("force", opts, {
    prompt_library = prompt_library,
    adapters = {
      acp = {
        copilot_cli = function()
          return require("codecompanion.adapters").extend("copilot_cli", {})
        end,
      },
    },
    inline = {layout = "buffer"},
    interactions = {
      -- CHAT INTERACTION -------------------------------------------------
      chat = {
        adapter = default_adapter,
        --adapter = "copilot_cli",
        tools = {
          opts = {
            default_tools = {
              "agent_skills",
              --"files",
            },
            system_prompt = {
              enabled = true,
              replace_main_system_prompt = false,
            },
          },
          ["read_file"] = {
            opts = {
              require_approval_before = false,
              require_cmd_approval = false,
            },
          }
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
        --adapter = get_copilot_adapter(model_default),
        streaming = true,
        keymaps = {
          send = {
            modes = { n = "<C-s>", i = "<C-s>" },
            opts = {},
          },
        },
      },
      -- INLINE INTERACTION -----------------------------------------------
      inline = {
        --adapter = get_copilot_adapter(model_default),
        adapter = "copilot",
        model = default_model,
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
        -- intro_message = copilot_stats,
        -- Change to true to show the current model
        -- show_settings = true,
        -- start_in_insert_mode = true,
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
    },
  }) -- end of opts
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
      "ravitemer/mcphub.nvim",
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
