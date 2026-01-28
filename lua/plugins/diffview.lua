--[[
How to use:
:DiffviewOpen
:DiffviewOpen HEAD~2
:DiffviewOpen HEAD~4..HEAD~2
:DiffviewOpen d4a7b0d
:DiffviewOpen d4a7b0d^!
:DiffviewOpen d4a7b0d..519b30e
:DiffviewOpen origin/main...HEAD
--]]
return {
  "sindrets/diffview.nvim",
  opts = {
    gerrit_style_filesort = true
  }
}
