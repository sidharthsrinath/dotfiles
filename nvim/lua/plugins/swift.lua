return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        sourcekit = {
          cmd = { "sourcekit-lsp" },
          filetypes = { "swift", "objc", "objcpp" },
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
