---- vim options ----
vim.o.number = true -- shows line numbers
vim.o.mouse = ""
vim.o.tabstop = 2
vim.o.expandtab = true
vim.o.softtabstop = 2
vim.o.shiftwidth = 2
vim.o.ic = true
vim.o.makeprg = m

vim.g.ai_plugin = "codecompanion"
-- vim.g.ai_plugin = "copilot"
vim.g.ai_cmp = false

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
execute 'Gvdiff' s:parents[1]
let p0_buf = bufnr("%")
execute 'Gvdiff' s:merge_base
let base_buf = bufnr("%")
execute 'Gvdiff' s:parents[0]
let p1_buf = bufnr("%")
call win_gotoid(merge_win)
exec "wincmd J"
exec "wincmd w"
echom "first-parent:" . s:parents[0] . " second-parent:" . s:parents[1] . " merge-base:" . s:merge_base
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
function find_chromium_root(fname)
    local file = vim.fn.expand("%:p")
    local dir = vim.fn.fnamemodify(file, ":h")
    while dir ~= "/" do
        local deps_path = dir .. "/chrome/VERSION"
        if vim.fn.filereadable(deps_path) == 1 then
            return dir
        end
        dir = vim.fn.fnamemodify(dir, ":h")
    end
    return vim.fn.getcwd()
end

function MyIncludeExpr(fname)
    local name = string.gsub(fname, "^//", "")
    if vim.fn.isdirectory(name) ~= 0 then
        name = name .. "/BUILD.gn"
    end
    local root = find_chromium_root(fname)
    return root .. "/" .. name
end

vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'gn' },
    callback = function(a)
      vim.opt_local.includeexpr = "v:lua.MyIncludeExpr(v:fname)"
    end,
})

-- enable spell check in git commit message
vim.api.nvim_create_autocmd('FileType', {
    pattern = {'gitcommit'},
    callback = function()
      vim.opt_local.spell = true
    end,
})

vim.keymap.set("v", "<C-c>", function()
  local clipboard = require("clipboard_osc52")
  clipboard.visual_copy()
end, { noremap = true, silent = true })
