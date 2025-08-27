local curl = require("plenary.curl")

local plugin_enabled = vim.g.ai_plugin == "codecompanion"

local storage_path = vim.fn.stdpath("data") .. "/myplugin.json"
-- os.remove(storage_path)

local opts_extensions = {
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
-- https://docs.github.com/en/copilot/concepts/billing/copilot-requests
local premium_request_multiplier = {}
premium_request_multiplier["GPT-4.1"] = 0
premium_request_multiplier["GPT-5 mini"] = 0
premium_request_multiplier["GPT-5"] = 1
premium_request_multiplier["GPT-4o"] = 0
premium_request_multiplier["GPT-o3"] = 1
premium_request_multiplier["GPT-o4-mini"] = 0.33
premium_request_multiplier["Claude Sonnet 3.5"] = 1
premium_request_multiplier["Claude Sonnet 3.7"] = 1
premium_request_multiplier["Claude Sonnet 3.7 Thinking"] = 1.25
premium_request_multiplier["Claude Sonnet 4"] = 1
premium_request_multiplier["Claude Opus 4.1"] = 10
premium_request_multiplier["Claude Opus 4"] = 10
premium_request_multiplier["Gemini 2.0 Flash"] = 0.25
premium_request_multiplier["Gemini 2.5 Pro"] = 1
premium_request_multiplier["Grok Code Fast"] = 1

local function get_token()
  if _oauth_token then
    return _oauth_token
  end

  local token = os.getenv("GITHUB_TOKEN")
  local codespaces = os.getenv("CODESPACES")
  if token and codespaces then
    return token
  end

  local config_path = vim.fs.normalize("~/.config")

  local file_paths = {
    config_path .. "/github-copilot/hosts.json",
    config_path .. "/github-copilot/apps.json",
  }

  for _, file_path in ipairs(file_paths) do
    if vim.uv.fs_stat(file_path) then
      local userdata = vim.fn.readfile(file_path)

      if vim.islist(userdata) then
        userdata = table.concat(userdata, " ")
      end

      local userdata = vim.json.decode(userdata)
      for key, value in pairs(userdata) do
        if string.find(key, "github.com") then
          return value.oauth_token
        end
      end
    end
  end
  return nil
end

local _oauth_token = get_token()

local function save_var(var)
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

local function set_key(key, value)
  local var = load_var() or {}
  var[key] = value
  save_var(var)
end

local function get_key(key)
  local var = load_var() or {}
  return var[key]
end

local function make_adapter_name(model_name)
  local multiplier = premium_request_multiplier[model_name]
  local multiplier_str = ""
  if multiplier ~= nil then
    multiplier_str = " (" .. multiplier .. "🏆)"
  end
  return model_name .. multiplier_str
end

local function get_copilot_adapter(name, id)
  local adapters = require("codecompanion.adapters")
  return adapters.extend("copilot", {
      name = name,
      schema = {
        model = { default = id },
      }
    })
end

local function build_adapters(models)
  local adapters = require("codecompanion.adapters")
  local custom_adapters = {
    opts = {
      show_defaults = false,
    }
  }
  for _, item in pairs(models) do
    adapter = make_adapter_name(item.name)
    custom_adapters[adapter] = get_copilot_adapter(adapter, item.id)
  end
  return custom_adapters
end

local function get_copilot_models()
  cached_models = get_key("copilot_models")
  cached_time = get_key("copilot_models_time")

  -- Cache for 24 hours
  if cached_models and cached_time and (os.time() - cached_time < 86400) then
    return cached_models
  end

  local config = require("codecompanion.config")
  local copilot = require("codecompanion.adapters.copilot")
  local headers = vim.deepcopy(copilot.headers)

  headers["Authorization"] = "Bearer " .. _oauth_token
  local url = "https://api.githubcopilot.com/models"

  local ok, response = pcall(function()
    return curl.get(url, {
      sync = false,
      headers = headers,
      callback = function(response)
        if false then
          local file = io.open("output.json", "w")
          file:write(response.body)
          file:close()
        end
        local ok, json = pcall(vim.json.decode, response.body)
        vim.schedule(function()
          models = {}
          for _, model in ipairs(json.data) do
            if model.model_picker_enabled and model.capabilities.type == "chat" then
              table.insert(models, { id = model.id, name = model.name } )
            end
          end
          set_key("copilot_models", models)
          set_key("copilot_models_time", os.time())
          config.adapters = vim.deepcopy(build_adapters(models))
        end)
      end
    })
  end)
  return nil
end

local copilot_stats = get_key("copilot_stats") or "Premium interaction: N/A"
local function get_copilot_stats()
  local ok, response = pcall(function()
    return curl.get("https://api.github.com/copilot_internal/user", {
      sync = false,
      headers = {
        Authorization = "Bearer " .. get_token(),
        Accept = "*/*",
        ["User-Agent"] = "CodeCompanion.nvim",
      },
      callback = function(response)
        local ok, json = pcall(vim.json.decode, response.body)
        vim.schedule(function()
          local premium = json.quota_snapshots.premium_interactions
          local used = premium.percent_remaining
          set_key("copilot_stats", string.format(
              "Premium interaction: %d / %d",
              premium.entitlement - premium.remaining,
              premium.entitlement))
        end)
      end
    })
  end)
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
      local adapters = require("codecompanion.adapters")
      local copilot = adapters.resolve("copilot")

      local bootstrap_models = {
        { id = "gemini-2.5-pro", name = "Gemini 2.5 Pro" },
      }
      get_copilot_stats()
      models = get_copilot_models() or bootstrap_models
      local model_default = get_key("selected_model") or bootstrap_models[1]
      opts.adapters = build_adapters(models)
      opts.inline = {layout = "buffer"}
      opts.strategies = {
        chat = {
          adapter = get_copilot_adapter(make_adapter_name(model_default.name), model_default.id),
          roles = {
            llm = "  Copilot Chat",
            user = "wanchnag.ryu"
          },
          streaming = true,
        },
        inline = { adapter = get_copilot_adapter(make_adapter_name(model_default.name), model_default.id) },
      }
      opts.display = {
        chat = {
          intro_message = copilot_stats,
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
        },
      }
      opts.extensions = opts_extensions
      require('codecompanion').setup(opts)
      require('plugins.codecompanion.utils.extmarks').setup()

      local group = vim.api.nvim_create_augroup("CCH", {})
      vim.api.nvim_create_autocmd({ "User" }, {
        pattern = "CodeCompanionChatAdapter",
        group = group,
        callback = function(request)
          if request.data.adapter then
            set_key("selected_model", { id = request.data.adapter.model.id, name = request.data.adapter.model.name })
          end
        end,
      })
    end,
    opts = {
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
      opts = {
        system_prompt = "You are coding guru expecially You're chromium cpp expert. You are here to help me with my coding problems. " ..
          "You are very helpful and friendly. You are very good at understanding code and providing solutions." ..
          "You use MZ slang and many emojis. " ..
          "Use korean.",
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
