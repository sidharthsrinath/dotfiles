-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git", "clone", "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    {
        "ellisonleao/gruvbox.nvim",
        lazy = false,
        priority = 1000, -- load before other plugins
        config = function()
            vim.o.background = "dark"
            vim.cmd("colorscheme gruvbox")
        end,
    },
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        lazy = false,
        init = function(plugin)
            -- nvim-treesitter stores queries under runtime/, add it to rtp
            vim.opt.rtp:prepend(plugin.dir .. "/runtime")
        end,
        config = function()
            require("nvim-treesitter").install({ "cpp", "c", "lua" })

            vim.api.nvim_create_autocmd("FileType", {
                pattern = { "c", "cpp", "lua" },
                callback = function(ev)
                    pcall(vim.treesitter.start, ev.buf)
                end,
            })
        end,
    },
})
