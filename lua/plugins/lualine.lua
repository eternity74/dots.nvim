  return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-web-devicons", opt = true },
    --event = { "BufNewFile", "BufRead" },
    config = function()
      require('lualine').setup {
        sections = {
          lualine_c = { {'filename', path = 1} },
          lualine_z = { { require("plugins/lualine/cc-component") }, },
        },
        inactive_sections = {
          lualine_c = { { "filename", path = 1 } }
        },
      }
    end,
  }
