---- vim options ----
vim.o.number = true -- shows line numbers
vim.o.mouse = ""
vim.o.tabstop = 2
vim.o.expandtab = true
vim.o.softtabstop = 2
vim.o.shiftwidth = 2
vim.o.ic = true
vim.o.makeprg = m

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

vim.api.nvim_create_user_command("MyMergeTool", function()
  vim.api.nvim_exec(
    [[
function! s:rename_buf(buffer, name)
let current = bufnr("%")
execute a:buffer . 'bufdo file ' . fnameescape(a:name)
execute 'buffer ' . current
endfunction

let s:filename = expand("%.h")
exec "only"
exec "e " . s:filename
let merge_win = win_getid()
let s:parents = split(system("git log -1 --merges --pretty=%p"))
let s:merge_base = system("git merge-base " . s:parents[0] . " " . s:parents[1])
execute 'Gvdiff' s:parents[0]
let p0_buf = bufnr("%")
execute 'Gvdiff' s:merge_base
let base_buf = bufnr("%")
execute 'Gvdiff' s:parents[1]
let p1_buf = bufnr("%")
call win_gotoid(merge_win)
exec "wincmd J"
exec "wincmd w"
echom s:parents s:merge_base
"echom p0_buf p1_buf base_buf

"let current = bufnr("%")
"execute p0_buf . 'bufdo file downstream'
"execute p1_buf . 'bufdo file upstream'
"execute base_buf . 'bufdo file merge-base'
"execute 'buffer ' . current
  ]],
    false
  )
end, {})

-- for chromium source navigation
function MyIncludeExpr(fname)
    local name = string.gsub(fname, "^//", "")
    if vim.fn.isdirectory(name) ~= 0 then
        name = name .. "/BUILD.gn"
    end
    return name
end

vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'gn' },
    callback = function(a)
      vim.opt_local.includeexpr = "v:lua.MyIncludeExpr(v:fname)"
    end,
})
--
