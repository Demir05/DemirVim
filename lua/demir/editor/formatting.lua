local conform = require("conform")

-- ─────────────────────────────────────────────────────────────
-- Formatter Yapılandırması
-- ─────────────────────────────────────────────────────────────

conform.setup({
    formatters_by_ft = {
        -- C / C++
        c = {
            "clang_format",
        },

        cpp = {
            "clang_format",
        },

        objc = {
            "clang_format",
        },

        objcpp = {
            "clang_format",
        },

        -- Lua
        lua = {
            "stylua",
        },

        -- CMake
        cmake = {
            "gersemi",
        },

        -- Shell
        sh = {
            "shfmt",
        },

        bash = {
            "shfmt",
        },

        -- JSON
        json = {
            "prettier",
        },

        jsonc = {
            "prettier",
        },

        -- YAML
        yaml = {
            "prettier",
        },

        -- Markdown
        markdown = {
            "prettier",
        },

        -- JavaScript / TypeScript
        javascript = {
            "prettier",
        },

        javascriptreact = {
            "prettier",
        },

        typescript = {
            "prettier",
        },

        typescriptreact = {
            "prettier",
        },

        -- Web
        html = {
            "prettier",
        },

        css = {
            "prettier",
        },

        scss = {
            "prettier",
        },

        less = {
            "prettier",
        },
    },

    -- Formatter hata verirse bildirim göster.
    notify_on_error = true,

    -- Kaydederken otomatik format.
    format_on_save = function(bufnr)
        local filetype =
            vim.bo[bufnr].filetype

        -- Markdown otomatik formatlanmasın.
        -- Space+m ile manuel olarak formatlanabilir.
        if filetype == "markdown" then
            return nil
        end

        return {
            timeout_ms = 3000,

            -- Conform formatter'ı varsa onu kullan.
            -- Yoksa LSP formatter'a düş.
            lsp_format = "fallback",
        }
    end,
})

-- ─────────────────────────────────────────────────────────────
-- Manuel Format
-- ─────────────────────────────────────────────────────────────

local function format_buffer()
    conform.format({
        async = true,

        -- Conform formatter'ı varsa onu kullan.
        -- Yoksa LSP formatter'a düş.
        lsp_format = "fallback",

        timeout_ms = 3000,
    })
end

-- ─────────────────────────────────────────────────────────────
-- Kısayollar
-- ─────────────────────────────────────────────────────────────

vim.keymap.set(
    "n",
    "<leader>m",
    format_buffer,
    {
        desc = "Dosyayı biçimlendir",
    }
)
