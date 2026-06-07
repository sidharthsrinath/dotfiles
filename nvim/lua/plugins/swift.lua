-- Rebuilds xcode-build-server's `.compile` flag database via an incremental
-- xcodebuild + `parse -a`. Only recompiles changed files, so it's cheap to run
-- after adding files / changing build flags / a big rebase. Derives the project
-- and scheme from the nearest buildServer.json, so it works for any
-- xcode-build-server project, not just this one.
local function refresh_compile_flags()
  local fname = vim.api.nvim_buf_get_name(0)
  local bs = vim.fs.find("buildServer.json", { upward = true, path = vim.fs.dirname(fname) })[1]
  if not bs then
    vim.notify("sourcekit: no buildServer.json found upward from this file", vim.log.levels.WARN)
    return
  end
  local root = vim.fs.dirname(bs)
  local ok, cfg = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(bs), "\n"))
  end)
  if not ok or not cfg.scheme or not cfg.workspace then
    vim.notify("sourcekit: buildServer.json missing scheme/workspace", vim.log.levels.ERROR)
    return
  end
  local project = (cfg.workspace:gsub("/project%.xcworkspace$", ""))
  local cmd = string.format(
    "xcodebuild -project %q -scheme %q -destination 'generic/platform=iOS Simulator' "
      .. "-configuration Debug ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build 2>&1 "
      .. "| xcode-build-server parse -a -o %q",
    project,
    cfg.scheme,
    root .. "/.compile"
  )
  vim.notify("sourcekit: refreshing .compile (incremental build of " .. cfg.scheme .. ")...")
  vim.fn.jobstart({ "bash", "-lc", cmd }, {
    cwd = root,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          vim.notify("sourcekit: .compile refreshed — run :LspRestart to apply")
        else
          vim.notify("sourcekit: refresh failed (exit " .. code .. ")", vim.log.levels.ERROR)
        end
      end)
    end,
  })
end

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
            {
              "<leader>cxc",
              refresh_compile_flags,
              desc = "Refresh compile flags (.compile)",
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
