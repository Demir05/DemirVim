local Snacks = require("snacks")

local group = vim.api.nvim_create_augroup("DemirLspKeymaps", {
    clear = true,
})

vim.api.nvim_create_autocmd("LspAttach", {
    group = group,

    callback = function(event)
        local buffer = event.buf

        local function map(lhs, rhs, desc)
            vim.keymap.set("n", lhs, rhs, {
                buffer = buffer,
                silent = true,
                desc = desc,
            })
        end

        -- ─────────────────────────────────────────────────────
        -- Bilgi
        -- ─────────────────────────────────────────────────────

        -- İmlecin altındaki sembol hakkında bilgi göster.
        map("K", function()
            vim.lsp.buf.hover({
                border = "rounded",
                max_width = 90,
                max_height = 30,
            })
        end, "Sembol bilgisini göster")

        -- Fonksiyon imzasını ve parametreleri göster.
        map("<leader>h", function()
            vim.lsp.buf.signature_help({
                border = "rounded",
                max_width = 90,
                max_height = 30,
            })
        end, "Fonksiyon imzasını göster")

        -- ─────────────────────────────────────────────────────
        -- Kod içerisinde gezinme
        -- ─────────────────────────────────────────────────────

        -- Tanıma git.
        map("gd", function()
            Snacks.picker.lsp_definitions()
        end, "Tanıma git")

        -- Bildirime git.
        map("gD", function()
            Snacks.picker.lsp_declarations()
        end, "Bildirime git")

        -- Tüm kullanımları göster.
        map("gr", function()
            Snacks.picker.lsp_references()
        end, "Referansları göster")

        -- Gerçeklemeye git.
        map("gI", function()
            Snacks.picker.lsp_implementations()
        end, "Gerçeklemeye git")

        -- Tür tanımına git.
        map("gy", function()
            Snacks.picker.lsp_type_definitions()
        end, "Tür tanımına git")

        -- ─────────────────────────────────────────────────────
        -- Kod düzenleme
        -- ─────────────────────────────────────────────────────

        -- Sembolü proje genelinde yeniden adlandır.
        map("<leader>r", function()
            vim.lsp.buf.rename()
        end, "Yeniden adlandır")

        -- Mevcut konum için kullanılabilir kod eylemlerini göster.
        map("<leader>a", function()
            vim.lsp.buf.code_action()
        end, "Kod eylemleri")
    end,
})
