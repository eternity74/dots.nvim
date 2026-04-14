return {
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
        model = "gpt-5-mini",
        refresh_every_n_propmts = 3,
        max_refreshes = 3,
        format_title = function(original_title)
          return original_title
        end
      },
      continue_last_chat = false,
      delete_on_clearing_chat = false,
      dir_to_save = vim.fs.joinpath(vim.fn.stdpath("data"), "codecompanion", "history"),
      enable_logging = false,
      summary = {
        create_summary_keymap = "gcs",
        browser_summary_keymap = "gbs",
        generation_opts = {
          adapter = "copilot",
          model = "gpt-5-mini",
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
  },
  agentskills = {
    opts = {
      paths = {
        { "~/skills", recursive = true },  -- Recursive search
      }
    }
  }
}
