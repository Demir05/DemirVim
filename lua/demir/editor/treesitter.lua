local treesitter = require("nvim-treesitter")

local parsers = {
    "c",
    "cpp",
    "cmake",
    "lua",
    "markdown",
    "markdown_inline",
    "bash",
    "json",
    "yaml",
    "toml",
}

treesitter.install(parsers)

vim.api.nvim_create_autocmd("FileType", {
    pattern = {
        "c",
        "cpp",
        "cmake",
        "lua",
        "markdown",
        "bash",
        "sh",
        "json",
        "yaml",
        "toml",
    },

    callback = function()
        pcall(vim.treesitter.start)
    end,
})
