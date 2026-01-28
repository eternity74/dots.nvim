vim.api.nvim_create_user_command('LspRefsByName', function(opts)
  local name = opts.args
  if name == '' then
    name = vim.fn.input('Symbol: ')
    if name == '' then return end
  end

  -- workspace/symbol로 심볼 검색
  vim.lsp.buf_request_all(0, 'workspace/symbol', { query = name }, function(results)
    local sym_locs = {}
    for _, res in pairs(results) do
      if res.result then
        for _, sym in ipairs(res.result) do
          -- SymbolInformation은 .location 필드에 위치정보가 있음
          local loc = sym.location or sym -- 안전장치
          if loc and loc.uri and loc.range then
            table.insert(sym_locs, loc)
          end
        end
      end
    end

    if vim.tbl_isempty(sym_locs) then
      print('LSP: no symbol found for "' .. name .. '"')
      return
    end

    -- 찾은 각 위치에 대해 references 요청
    local pending = #sym_locs
    local all_refs = {}
    for _, loc in ipairs(sym_locs) do
      -- 버퍼 로드(필요하면)
      local bufnr = vim.uri_to_bufnr(loc.uri)
      vim.fn.bufload(bufnr)

      local params = {
        textDocument = { uri = loc.uri },
        position = loc.range.start,
        context = { includeDeclaration = true },
      }

      vim.lsp.buf_request_all(bufnr, 'textDocument/references', params, function(refs_res)
        for _, r in pairs(refs_res) do
          if r.result then
            for _, rloc in ipairs(r.result) do
              table.insert(all_refs, rloc)
            end
          end
        end

        pending = pending - 1
        if pending == 0 then
          if vim.tbl_isempty(all_refs) then
            print('LSP: no references found for "' .. name .. '"')
            return
          end
          local items = vim.lsp.util.locations_to_items(all_refs)
          vim.fn.setqflist({}, ' ', { title = 'LspRefs: ' .. name, items = items })
          vim.cmd('copen')
        end
      end)
    end
  end)
end, { nargs = '?' })

return {
  "neovim/nvim-lspconfig",
  enabled = true,
  config = function()

    -- Go LSP 설정 🐹
    vim.lsp.config.gopls = {
      cmd = { '/home/wanchang.ryu/go/bin/gopls' },
      filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
      root_markers = { 'go.work', 'go.mod', '.git' },
      settings = {
        gopls = {
          analyses = {
            unusedparams = true,
          },
          staticcheck = true,
          gofumpt = true,
        },
      },
    }

    -- C/C++ LSP 설정 🚀
    vim.lsp.config.clangd = {
      cmd = {
        -- 'third_party/llvm-build/Release+Asserts/bin/clangd',
        '/home/wanchang.ryu/bin/clangd',
        '--background-index',
        '--clang-tidy',
        '--header-insertion=iwyu',
        '--completion-style=detailed',
        '--function-arg-placeholders=1',
        '--fallback-style=chromium',
        '--parse-forwarding-functions=true',
        '--enable-config',
        --"--compile-commands-dir=out/Release",
        '-j', '24',
      },
      filetypes = { 'cc', 'c', 'cpp', 'h' },
      root_markers = {
        'compile_commands.json',
        --'out/Release/compile_commands.json',
        '.git', -- fallback
        'DEPS', -- chromium 프로젝트 marker
      },
      capabilities = {
        offsetEncoding = { "utf-16" }
      },
      init_options = {
        clangdFileStatus = true, -- 상태 표시 (옵션)
      },
    }

    -- LSP 활성화 ㄱㄱ 🎯
    vim.lsp.enable('gopls')
    vim.lsp.enable('clangd')

    -- 키맵 설정 ⌨️
    vim.api.nvim_create_autocmd('LspAttach', {
      callback = function(args)
        local bufnr = args.buf
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = 'Go to Definition', buffer = bufnr })
        -- vim.keymap.set('n', 'K', vim.lsp.buf.hover, { desc = 'Hover Documentation', buffer = bufnr })
        -- vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { desc = 'Rename', buffer = bufnr })
        -- 필요한 키맵 더 추가 가능! 🎯
      vim.keymap.set('n', '<Space><Space>', function()
        vim.diagnostic.open_float({
          border = 'rounded',
          focus = false,
        })
end, { noremap = true, silent = true })
      end,
    })
  end
}
