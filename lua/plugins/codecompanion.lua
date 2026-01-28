local curl = require("plenary.curl")

local plugin_enabled = vim.g.ai_plugin == "codecompanion"

local storage_path = vim.fn.stdpath("data") .. "/myplugin.json"
os.remove(storage_path)

local fmt = string.format

local opts_extensions = require("plugins.codecompanion.extensions_config")

local cc_config = function(_, opts)
  local config = require("codecompanion.config")
  local util = require("codecompanion.utils")
  -- get_copilot_stats()
  -- models = get_copilot_models() or bootstrap_models
  -- local model_default = get_key("selected_model") or bootstrap_models[1]
  --[[
      opts.adapters = {
        http = build_adapters(models)
      }
      --]]
  opts = vim.tbl_deep_extend("force", opts, {
    inline = {layout = "buffer"},
    interactions = {
      -- CHAT INTERACTION -------------------------------------------------
      chat = {
        -- adapter = { name = "copilot", model = "gpt-5-mini" },
        -- adapter = { name = "copilot", model = "claude-sonnet-4.5" },
        adapter = { name = "copilot", model = "claude-haiku-4.5" },
        tools = {
          opts = {
            --[[
            default_tools = {
              "kairos__retrieve_patch",
            },
            --]]
            system_prompt = {
              enabled = true,
              replace_main_system_prompt = false,
              prompt = function(args)
                return "Use kairos__retrieve_patch tool to fetch gerrit code review information when applicable."
              end,
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
The current date is %s.
The user's Neovim verion is %s.
The user is working on a %s machine. Please respond with system specific commands if applicable.
The user is developing chromium open source project. Provide relevant information when applicable.
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
          --[[
              change_adapter  = {
                callback = function(chat)
                  vim.inspect("Change Adapter")
                  local function select_opts(prompt, conditional)
                    return {
                      prompt = prompt,
                      kind = "codecompanion.nvim",
                      format_item = function(item)
                        local option_name = " " .. item.name
                        if conditional == item.name then
                          option_name = "* " .. item.name
                        end
                        local billing = item.billing .. "x"
                        local space_len = 35 - #option_name - #billing
                        return option_name .. string.rep(" ", space_len) .. billing
                      end,
                    }
                  end
                  local adapters = vim.deepcopy(config.adapters.http)
                  local current_adapter = chat.adapter.name
                  local current_model = vim.deepcopy(chat.adapter.schema.model.default)

                  local adapters_list = vim.iter(adapters)
                    :filter(function(adapter)
                      return adapter ~= "opts" and adapter ~= "non_llm"
                    end)
                    :map(function(name, adapter)
                      local billing = adapter.billing or "xx"
                      return { billing = adapter.billing, name = adapter.name }
                    end)
                    :totable()
                  table.sort(adapters_list, function(a, b)
                    if a.billing == 0 and b.billing == 0 then
                      return a.name < b.name
                    end
                    if a.billing == 0 or b.billing == 0 then
                      return a.billing == 0
                    end
                    return a.name < b.name
                  end)
                  vim.ui.select(adapters_list, select_opts("Select Adapter", current_adapter), function(selected)
                    if not selected or selected.name == current_adapter then
                      return
                    end

                    chat.adapter = require("codecompanion.adapters").resolve(adapters[selected.name])
                    util.fire(
                      "ChatAdapter",
                      { bufnr = chat.bufnr, adapter = require("codecompanion.adapters").make_safe(chat.adapter) }
                    )
                    chat.ui.adapter = chat.adapter
                    chat:apply_settings()
                    local system_prompt = config.opts.system_prompt
                    if type(system_prompt) == "function" then
                      if chat.messages[1] and chat.messages[1].role == "system" then
                        local opts = { adapter = chat.adapter, language = config.opts.language }
                        chat.messages[1].content = system_prompt(opts)
                      end
                    end
                  end)

                end
              }
              --]]
        },
      },
      -- INLINE INTERACTION -----------------------------------------------
      inline = {
        --adapter = get_copilot_adapter(model_default),
        adapter = "copilot",
        model = "gpt-5-mini",
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

  -- MCPHub 로드 완료 후 default_tools 설정
  local group = vim.api.nvim_create_augroup("CodeCompanionMCPHub", {})
  vim.api.nvim_create_autocmd({ "User" }, {
    group = group,
    pattern = {"CodeCompanionChatAdapter", "CodeCompanionChatCreated"},
    once = true,
    callback = function(request)
      -- MCPHub의 tools가 이미 등록됨
      local config = require("codecompanion.config")
      config.interactions.chat.tools.opts = { default_tools = {"kairos__retrieve_patch"} }
      -- vim.notify(vim.inspect(config.interactions.chat.tools), vim.log.levels.INFO, { title = "CodeCompanion MCPHub Tools" })
    end,
  })

  -- for lualine
  --[[
      local group = vim.api.nvim_create_augroup("CCH", {})
      vim.api.nvim_create_autocmd({ "User" }, {
        pattern = "CodeCompanionChatAdapter",
        group = group,
        callback = function(request)
          if request.data.adapter then
            set_key("selected_model", { id = request.data.adapter.model.name, name = request.data.adapter.name } )
          end
        end,
      })
  --]]
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
      "ravitemer/mcphub.nvim",
      "ravitemer/codecompanion-history.nvim",
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

-- NOT USED CURRENTLY -----------------------------------------------------------
--[[
local function get_github_token()
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

local _oauth_token = get_github_token()

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

local bootstrap_models = {
  { id = "gpt-5-mini", name = "GPT-5 mini (Preview)", billing = "0" },
}
local function get_copilot_adapter(model)
  local adapters = require("codecompanion.adapters")
  return adapters.extend("copilot", {
      name = model.name,
      type = "http",
      billing = model.billing or "0",
      schema = {
        model = { default = model.id },
      },
    })
end

local function build_adapters(models)
  local custom_adapters = {
    opts = {
      --show_defaults = false,
    }
  }
  for _, item in pairs(models) do
    custom_adapters[item.name] = get_copilot_adapter(item)
  end
  return custom_adapters
end

local function fetch_copilot_token(callback)
  local cached = get_key("copilotToken")
  if cached and cached.expires_at and os.time() < cached.expires_at then
    callback(cached.token)
  end

  local ok, response = pcall(function()
    return curl.get("https://api.github.com/copilot_internal/v2/token", {
      headers = {
        Authorization = "Bearer " .. get_github_token(),
        ["X-GitHub-Api-Version"] = "2025-04-01"
      },
      callback = function(response)
        local ok, json = pcall(vim.json.decode, response.body)
        vim.schedule(function()
          if false then
            local file = io.open("user.json", "w")
            file:write(response.body)
            file:close()
          end
          set_key("copilotToken", { token = json.token, expires_at = os.time() + json.refresh_in })
          callback(json.token)
        end)
      end
    })
  end)
end

local function get_copilot_models()
  cached_models = get_key("copilot_models")
  cached_time = get_key("copilot_models_time")

  -- Cache for 24 hours
  if cached_models and cached_time and (os.time() - cached_time < 86400) then
    return cached_models
  end
  fetch_copilot_token(function(copilot_token)
    local config = require("codecompanion.config")
    local adapters = require("codecompanion.adapters")
    local copilot = adapters.resolve("copilot")
    local headers = vim.deepcopy(copilot.headers)
    headers["Authorization"] = "Bearer " .. copilot_token
    headers["X-GitHub-Api-Version"] = "2025-07-16" -- it provides billing info

    local url = "https://api.githubcopilot.com/models"
    local ok, response = pcall(function()
      return curl.get(url, {
        headers = headers,
        callback = function(response)
          if true then
            local file = io.open("output.json", "w")
            file:write(response.body)
            file:close()
          end
          local ok, json = pcall(vim.json.decode, response.body)
          vim.schedule(function()
            models = {}
            for _, model in ipairs(json.data) do
              if model.model_picker_enabled and model.capabilities.type == "chat" then
                table.insert(models, { id = model.id, name = model.name, billing = model.billing.multiplier } )
              end
            end
            set_key("copilot_models", models)
            set_key("copilot_models_time", os.time())
            config.adapters.http = vim.deepcopy(build_adapters(models))
          end)
        end
      })
    end)
  end)
  return nil
end

local copilot_stats = get_key("copilot_stats") or "Premium interaction: N/A"
local function get_copilot_stats()
  local ok, response = pcall(function()
    return curl.get("https://api.github.com/copilot_internal/user", {
      sync = false,
      headers = {
        Authorization = "Bearer " .. get_github_token(),
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
--]]

