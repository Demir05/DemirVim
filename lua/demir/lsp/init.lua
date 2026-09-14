local capabilities = require("blink.cmp").get_lsp_capabilities()

-- ─────────────────────────────────────────────────────────────
-- Ortak LSP Ayarları
-- ─────────────────────────────────────────────────────────────

vim.lsp.config("*", {
    capabilities = capabilities,
})

-- ─────────────────────────────────────────────────────────────
-- Lua
-- ─────────────────────────────────────────────────────────────

vim.lsp.config("lua_ls", {
    settings = {
        Lua = {
            runtime = {
                version = "LuaJIT",
            },

            diagnostics = {
                globals = {
                    "vim",
                },
            },

            workspace = {
                checkThirdParty = false,

                library = vim.api.nvim_get_runtime_file(
                    "",
                    true
                ),
            },

            telemetry = {
                enable = false,
            },
        },
    },
})

-- ─────────────────────────────────────────────────────────────
-- Language Servers
-- ─────────────────────────────────────────────────────────────

local servers = {
    "clangd",    -- C / C++
    "lua_ls",    -- Lua
    "jsonls",    -- JSON / JSONC
    "yamlls",    -- YAML
    "marksman",  -- Markdown
    "bashls",    -- Bash / shell
    "cmake",     -- CMake
}

vim.lsp.enable(servers)
