local plugin_enabled = vim.g.ai_plugin == "codecompanion"

local storage_path = vim.fn.stdpath("data") .. "/myplugin.json"

local function save_var(var)
  --vim.notify("Saving variable to " .. storage_path, vim.log.levels.INFO)
  local file = io.open(storage_path, "w")
  if file then
    file:write(vim.fn.json_encode(var))
    file:close()
  else
    vim.notify("Failed to save variable to " .. storage_path, vim.log.levels.ERROR)
  end
end

local function load_var()
  local file = io.open(storage_path, "r")
  if file then
    local content = file:read("*a")
    file:close()
    return vim.fn.json_decode(content)
  else
    return nil
  end
end

return {
  {
    "olimorris/codecompanion.nvim",
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
    },
    config = function(_, opts)
      local models = {
        "claude-3.7-sonnet",
        "claude-3.5-sonnet",
        "claude-3.7-sonnet-thought",
        "claude-sonnet-4",
        "gemini-2.0-flash-001",
        "gemini-2.5-pro-preview-06-05",
        "gpt-4.1",
        "gpt-4o",
        "o1",
        "o3-mini",
        "o4-mini",
      }
      local adapter_prefix = "copilot-"
      local default = load_var() or { model = "gpt-4o" }
      local model_default = default.model
      local myadapters = { opts = { show_defaults = false } }

      local curl = require("plenary.curl")
      local adapters = require("codecompanion.adapters")
      -- local copilot = adapters.resolve("copilot")
      -- local model_names = copilot.schema.model.choices(copilot)
      -- for model_name, model_info in pairs(model_names) do
      for _, model_name in pairs(models) do
        adapter = "copilot-" .. model_name
        myadapters[adapter] = function()
          return adapters.extend("copilot", {
            name = adapter,
            schema = {
              model = { default = model_name },
            }
          })
        end
      end
      opts.adapters = myadapters
      opts.strategies = {
        chat = { adapter = adapter_prefix .. model_default },
        inline = { adapter = adapter_prefix .. model_default },
      }
      opts.extensions = {
        history = {
          enabled = true,
          opts = {
            keymap = "gh",
            save_chat_keymap = "sc",
            auto_sve = true,
            expiration_days = 7,
            picker = "telescope",
            chat_filter = nil,
            picker_keymaps = {
              rename = { n = "r", i = "<M-r>" },
              delete = { n = "d", i = "<M-d>" },
              duplicate = { n = "<C-y>", i = "<C-y>" },
            },
            auto_generate_title = true,
            title_generation_opts = {
              adapter = "copilot",
              model = "gpt-4o",
              refresh_every_n_propmts = 3,
              max_refreshes = 3,
              format_title = function(original_title)
                return original_title
              end
            },
            continue_last_chat = false,
            delete_on_clearing_chat = false,
            dir_to_save = vim.fn.stdpath("data") .. "/codecompanion/history",
            enable_logging = false,
            summary = {
              create_summary_keymap = "gcs",
              browser_summary_keymap = "gbs",
              generation_opts = {
                adapter = "copilot",
                model = "gpt-4o",
                context_size = 90000,
                include_references = true,
                include_tool_outputs = true,
                system_prompt = nil,
                format_summary = nil,
              },
            },
            memory = {
              auto_create_memories_on_summary_generation = true,
              vectorcode_exe = "vectorcode",
              tool_opts = {
                default_num = 10
              },
              notify = true,
              index_on_startup = false,
            },
          },
        }
      }
      require('codecompanion').setup(opts)
      require('plugins.codecompanion.utils.extmarks').setup()

      local group = vim.api.nvim_create_augroup("CCH", {})
      vim.api.nvim_create_autocmd({ "User" }, {
        pattern = "CodeCompanionChatAdapter",
        group = group,
        callback = function(request)
          if request.data.adapter then
            save_var({ model = request.data.adapter.model.name })
          end
        end,
      })

    end,
    opts = {
      adapters = {
        opts = {
          show_defaults = false,
          show_model_choices = true,
        },
      },
      strategies = {
        chat = {
          adapter = "copilot",
          roles = {
            llm = "  Copilot Chat",
            user = "wanchnag.ryu"
          },
          streaming = true,
        },
        inline = { adapter = "copilot" },
        agent = { adapter = "copilot" },
      },
      inline = {
        layout = "buffer", -- vertical|horizontal|buffer
      },
      display = {
        chat = {
          -- Change to true to show the current model
          --show_settings = true,
          start_in_insert_mode = true,
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
        },
      },
      keymaps = {
        submit = '<C-s>',
        send = {
          callback = function(chat)
            chat:add_buf_message({ role = "llm", content = "" })
            vim.notify("Sending message...")
            vim.cmd("stopinsert")
            chat:submit()
          end,
          index = 1,
          description = "Send",
        },
        close = {
          callback = function(chat)
            chat:add_buf_message({ role = "llm", content = "" })
            vim.notify("close message...")
            vim.cmd("stopinsert")
            chat:submit()
          end,
          index = 1,
          description = "Close",
        },
      },
    },
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
