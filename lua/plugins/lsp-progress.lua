return {
   {
    'linrongbin16/lsp-progress.nvim',
    dependencies = { 'nvim-lualine/lualine.nvim' }, -- lualine 보장
    config = function()
      require('lsp-progress').setup()

      vim.api.nvim_create_augroup("lualine_augroup", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        group = "lualine_augroup",
        pattern = "LspProgressStatusUpdated",
        callback = require("lualine").refresh,
      })
    end
  }
}
