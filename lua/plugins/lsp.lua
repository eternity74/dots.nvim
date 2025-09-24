return {
  "neovim/nvim-lspconfig",
  enabled = false,
  config = function()
    require'lspconfig'.clangd.setup{
      cmd = {
        "/home/wanchang.ryu/clangd_19.1.2/bin/clangd",
        "--remote-index-address=10.178.101.103:50051",
        "--project-root=/home/wanchang.ryu/src/atlas/build-atlas/local/chromium/src/",
        "--path-mappings=/home/wanchang.ryu/src/atls/build-altas/local/chromium/src/=/home/wanchang.ryu//src/rp/build-starfish/BUILD/work/o22-webosmllib32-linux-gnueabi/lib32-webruntime-clang/120.0.6099.269-pro.47-r1/git/src/",
        "--background-index=false",
      },
      filetypes = { "c", "cpp", "cc", "h" },
    }
  end,
}
