return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        sourcekit = {
          cmd = { "sourcekit-lsp", "--experimental-feature", "background-indexing" },
          filetypes = { "swift", "objc", "objcpp" },
          capabilities = {
            textDocument = {
              definition = { linkSupport = false },
            },
          },
          keys = {
            {
              "<leader>cxi",
              function()
                local clients = vim.lsp.get_clients({ bufnr = 0, name = "sourcekit" })
                if #clients > 0 then
                  clients[1].request("workspace/triggerReindex", {}, function() end, 0)
                  vim.notify("sourcekit-lsp: reindexing...")
                end
              end,
              desc = "Reindex (sourcekit-lsp)",
            },
          },
          root_dir = function(bufnr, cb)
            local fname = vim.api.nvim_buf_get_name(bufnr)
            local util = require("lspconfig.util")
            local root = util.root_pattern("buildServer.json")(fname)
              or util.root_pattern("*.xcodeproj", "*.xcworkspace")(fname)
              or util.root_pattern("compile_commands.json", "Package.swift")(fname)
              or vim.fs.root(fname, ".git")
            cb(root)
          end,
        },
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "swift" } },
  },
}
