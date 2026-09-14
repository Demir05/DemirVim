local diagnostic = vim.diagnostic
local Snacks = require("snacks")

-- ─────────────────────────────────────────────────────────────
-- Simgeler
-- ─────────────────────────────────────────────────────────────

local icons = {
    [diagnostic.severity.ERROR] = "",
    [diagnostic.severity.WARN] = "",
    [diagnostic.severity.INFO] = "",
    [diagnostic.severity.HINT] = "",
}

local highlights = {
    [diagnostic.severity.ERROR] = "DiagnosticSignError",
    [diagnostic.severity.WARN] = "DiagnosticSignWarn",
    [diagnostic.severity.INFO] = "DiagnosticSignInfo",
    [diagnostic.severity.HINT] = "DiagnosticSignHint",
}

-- ─────────────────────────────────────────────────────────────
-- Kısa satır içi mesaj
-- ─────────────────────────────────────────────────────────────

local function compact_message(item)
    local message = item.message
        :gsub("\n", " ")
        :gsub("%s+", " ")

    -- Satırın sağ tarafını dev bir hata mesajıyla doldurma.
    if vim.fn.strdisplaywidth(message) > 100 then
        message = vim.fn.strcharpart(message, 0, 97) .. "…"
    end

    return message
end

-- ─────────────────────────────────────────────────────────────
-- Diagnostic yapılandırması
-- ─────────────────────────────────────────────────────────────

diagnostic.config({
    -- ERROR > WARN > INFO > HINT sıralaması.
    severity_sort = true,

    -- Insert modunda da clangd/lua_ls vb. sonuçlarını güncelle.
    update_in_insert = true,

    -- ---------------------------------------------------------
    -- Sol işaret sütunu
    -- ---------------------------------------------------------

    signs = {
        priority = 20,

        text = icons,
    },

    -- ---------------------------------------------------------
    -- Alt çizgiler
    --
    -- INFO/HINT için kodu sürekli çizerek görüntüyü kirletmiyoruz.
    -- Yalnızca hata ve uyarılar altı çizili.
    -- ---------------------------------------------------------

    underline = {
        severity = {
            min = diagnostic.severity.WARN,
        },
    },

    -- ---------------------------------------------------------
    -- Satır içi diagnostic
    --
    -- Yalnızca imlecin bulunduğu satırdaki ERROR/WARN mesajını
    -- gösterir. Diğer satırlarda yalnızca simge ve underline kalır.
    -- ---------------------------------------------------------

    virtual_text = {
        current_line = true,

        severity = {
            min = diagnostic.severity.WARN,
        },

        spacing = 2,

        source = false,

        prefix = function(item)
            return icons[item.severity] or "●"
        end,

        format = compact_message,
    },

    -- Aynı bilgiyi ayrıca alt satırlara basıp ekranı büyütme.
    virtual_lines = false,

    -- ---------------------------------------------------------
    -- Diagnostic popup
    -- ---------------------------------------------------------

    float = {
        border = "rounded",

        scope = "line",

        severity_sort = true,

        source = "if_many",

        header = {
            " 󰒡 Tanılama ",
            "DiagnosticInfo",
        },

        prefix = function(item)
            return (icons[item.severity] or "●") .. " ",
                highlights[item.severity]
        end,

        suffix = function(item)
            if item.code then
                return "  [" .. tostring(item.code) .. "]",
                    "Comment"
            end

            return ""
        end,

        max_width = 100,
        max_height = 25,
    },

    -- Dosyanın sonundan sonraki diagnostic'e basıldığında
    -- tekrar dosyanın başına ışınlanma.
    jump = {
        wrap = false,
    },
})

-- ─────────────────────────────────────────────────────────────
-- Proje problemleri
-- ─────────────────────────────────────────────────────────────
--
-- Space+p
--
-- Açık çalışma dizinindeki bütün diagnostics'i aranabilir,
-- önizlemeli Snacks picker içinde gösterir.
-- ─────────────────────────────────────────────────────────────

vim.keymap.set("n", "<leader>p", function()
    Snacks.picker.diagnostics()
end, {
    desc = "Proje problemleri",
})
