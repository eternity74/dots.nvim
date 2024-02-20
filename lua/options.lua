---- vim options ----
vim.o.number = true -- shows line numbers
vim.o.mouse = ""
vim.o.tabstop = 2
vim.o.expandtab = true
vim.o.softtabstop = 2
vim.o.shiftwidth = 2

vim.api.nvim_create_autocmd({ "BufRead" }, {
  pattern = { "COMMIT_EDITMSG" },
  command = "set tw=72 colorcolumn=51,+1",
})

-- clang-format conf
vim.g.clang_format_path = "/home/wanchang.ryu/bin/clang-format"
vim.keymap.set(
  { "n", "v" },
  "<F5>",
  ":py3f /home/wanchang.ryu/wtools/bin/clang-format.py<CR>",
  { noremap = true }
)
