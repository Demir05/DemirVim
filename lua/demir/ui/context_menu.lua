local M = {}

local Snacks = require("snacks")

-- Sağ tıklanan noktaya imleci taşı ve ardından menüyü aç.
vim.opt.mousemodel = "popup_setpos"

-- ─────────────────────────────────────────────────────────────
-- Yardımcılar
-- ─────────────────────────────────────────────────────────────

local function lsp_supports(method)
    return #vim.lsp.get_clients({
        bufnr = 0,
        method = method,
    }) > 0
end

local function with_lsp_method(method, callback)
    if not lsp_supports(method) then
        vim.notify(
            "Bu işlem mevcut LSP tarafından desteklenmiyor.",
            vim.log.levels.WARN,
            {
                title = "Kod",
            }
        )

        return
    end

    callback()
end

local function current_file()
    local file = vim.api.nvim_buf_get_name(0)

    if file == "" then
        vim.notify(
            "Bu buffer henüz bir dosyaya bağlı değil.",
            vim.log.levels.WARN,
            {
                title = "Dosya",
            }
        )

        return nil
    end

    return file
end

local function project_root(file)
    return vim.fs.root(file, {
        ".git",
        "CMakeLists.txt",
        "CMakePresets.json",
        "pyproject.toml",
        "package.json",
        "Cargo.toml",
        "go.mod",
    }) or vim.fn.getcwd()
end

-- ─────────────────────────────────────────────────────────────
-- LSP
-- ─────────────────────────────────────────────────────────────

function M.hover()
    with_lsp_method("textDocument/hover", function()
        vim.lsp.buf.hover({
            border = "rounded",
            max_width = 90,
            max_height = 30,
        })
    end)
end

function M.definition()
    with_lsp_method("textDocument/definition", function()
        Snacks.picker.lsp_definitions()
    end)
end

function M.declaration()
    with_lsp_method("textDocument/declaration", function()
        Snacks.picker.lsp_declarations()
    end)
end

function M.implementation()
    with_lsp_method("textDocument/implementation", function()
        Snacks.picker.lsp_implementations()
    end)
end

function M.type_definition()
    with_lsp_method("textDocument/typeDefinition", function()
        Snacks.picker.lsp_type_definitions()
    end)
end

function M.references()
    with_lsp_method("textDocument/references", function()
        Snacks.picker.lsp_references()
    end)
end

function M.rename()
    with_lsp_method("textDocument/rename", function()
        vim.lsp.buf.rename()
    end)
end

function M.code_action()
    with_lsp_method("textDocument/codeAction", function()
        vim.lsp.buf.code_action()
    end)
end

function M.format()
    with_lsp_method("textDocument/formatting", function()
        vim.lsp.buf.format({
            async = false,
        })
    end)
end

-- ─────────────────────────────────────────────────────────────
-- Tanılamalar
-- ─────────────────────────────────────────────────────────────

function M.diagnostic_here()
    vim.diagnostic.open_float(nil, {
        scope = "line",
        border = "rounded",
        source = "if_many",
        severity_sort = true,
    })
end

function M.buffer_diagnostics()
    Snacks.picker.diagnostics_buffer()
end

function M.project_diagnostics()
    Snacks.picker.diagnostics()
end

-- ─────────────────────────────────────────────────────────────
--
-- ─────────────────────────────────────────────────────────────

function M.grep_word()
    Snacks.picker.grep_word()
end

function M.grep_selection()
    Snacks.picker.grep_word()
end

-- ─────────────────────────────────────────────────────────────
-- Explorer
-- ─────────────────────────────────────────────────────────────

function M.reveal_file()
    local file = current_file()

    if not file then
        return
    end

    Snacks.picker.explorer({
        cwd = project_root(file),
        follow_file = true,
    })
end

-- ─────────────────────────────────────────────────────────────
-- Dosya yolları
-- ─────────────────────────────────────────────────────────────

function M.copy_absolute_path()
    local file = current_file()

    if not file then
        return
    end

    vim.fn.setreg("+", file)

    vim.notify(
        "Tam dosya yolu panoya kopyalandı.",
        vim.log.levels.INFO,
        {
            title = "Dosya",
        }
    )
end

function M.copy_relative_path()
    local file = current_file()

    if not file then
        return
    end

    local relative = vim.fn.fnamemodify(
        file,
        ":."
    )

    vim.fn.setreg("+", relative)

    vim.notify(
        "Göreli dosya yolu panoya kopyalandı.",
        vim.log.levels.INFO,
        {
            title = "Dosya",
        }
    )
end

-- ─────────────────────────────────────────────────────────────
-- Menü yardımcıları
-- ─────────────────────────────────────────────────────────────

local function escape_label(label)
    return label
        :gsub("\\", "\\\\")
        :gsub(" ", "\\ ")
end

local function menu_path(label)
    return "PopUp." .. escape_label(label)
end

local function popup_priority(priority)
    return "1." .. tostring(priority)
end

local function lua_action(function_name)
    return string.format(
        '<Cmd>lua require("demir.ui.context_menu").%s()<CR>',
        function_name
    )
end

local function normal_menu(priority, label, action)
    vim.cmd(
        "nnoremenu <silent> "
            .. popup_priority(priority)
            .. " "
            .. menu_path(label)
            .. " "
            .. action
    )
end

local function visual_menu(priority, label, action)
    vim.cmd(
        "vnoremenu <silent> "
            .. popup_priority(priority)
            .. " "
            .. menu_path(label)
            .. " "
            .. action
    )
end

local function insert_menu(priority, label, action)
    vim.cmd(
        "inoremenu <silent> "
            .. popup_priority(priority)
            .. " "
            .. menu_path(label)
            .. " "
            .. action
    )
end

local function normal_separator(priority, name)
    normal_menu(
        priority,
        "-" .. name .. "-",
        "<Nop>"
    )
end

local function visual_separator(priority, name)
    visual_menu(
        priority,
        "-" .. name .. "-",
        "<Nop>"
    )
end

local function insert_separator(priority, name)
    insert_menu(
        priority,
        "-" .. name .. "-",
        "<Nop>"
    )
end

-- ─────────────────────────────────────────────────────────────
-- Menü etkin / devre dışı durumu
-- ─────────────────────────────────────────────────────────────

local function set_enabled(label, enabled)
    local state = enabled and "enable" or "disable"

    vim.cmd(
        "silent! amenu "
            .. state
            .. " "
            .. menu_path(label)
    )
end

-- ─────────────────────────────────────────────────────────────
-- Neovim varsayılan sağ tık menüsünü kaldır
-- ─────────────────────────────────────────────────────────────

pcall(vim.cmd, "aunmenu PopUp")
pcall(vim.cmd, "autocmd! nvim.popupmenu")

-- ═════════════════════════════════════════════════════════════
-- NORMAL MODE
-- ═════════════════════════════════════════════════════════════

-- Kod / LSP

normal_menu(
    10,
    "󰏫 Sembol Bilgisi",
    lua_action("hover")
)

normal_menu(
    20,
    "󰌑 Tanıma Git",
    lua_action("definition")
)

normal_menu(
    30,
    "󰈮 Bildirime Git",
    lua_action("declaration")
)

normal_menu(
    40,
    "󰡱 Gerçeklemeye Git",
    lua_action("implementation")
)

normal_menu(
    50,
    "󰙅 Tür Tanımına Git",
    lua_action("type_definition")
)

normal_menu(
    60,
    "󰈇 Referansları Göster",
    lua_action("references")
)

normal_menu(
    70,
    "󰑕 Yeniden Adlandır",
    lua_action("rename")
)

normal_menu(
    80,
    "󰌵 Kod Eylemleri",
    lua_action("code_action")
)

normal_menu(
    90,
    "󰉼 Dosyayı Biçimlendir",
    lua_action("format")
)

normal_separator(
    100,
    "kod"
)

-- Tanılamalar

normal_menu(
    110,
    "󰅚 Bu Satırdaki Sorun",
    lua_action("diagnostic_here")
)

normal_menu(
    120,
    "󰈙 Dosyanın Sorunları",
    lua_action("buffer_diagnostics")
)

normal_menu(
    130,
    "󰓦 Proje Sorunları",
    lua_action("project_diagnostics")
)

normal_separator(
    140,
    "sorunlar"
)

-- Arama / Dosya

normal_menu(
    150,
    "󰱼 Kelimeyi Projede Ara",
    lua_action("grep_word")
)

normal_menu(
    160,
    "󰙅 Explorer'da Göster",
    lua_action("reveal_file")
)

normal_menu(
    170,
    "󰅍 Göreli Yolu Kopyala",
    lua_action("copy_relative_path")
)

normal_menu(
    180,
    "󰅍 Tam Yolu Kopyala",
    lua_action("copy_absolute_path")
)

normal_separator(
    190,
    "dosya"
)

-- Düzenleme

normal_menu(
    200,
    "󰕌 Geri Al",
    "u"
)

normal_menu(
    210,
    "󰑎 İleri Al",
    "<C-r>"
)

normal_menu(
    220,
    " Satırı Kes",
    '"+dd'
)

normal_menu(
    230,
    " Satırı Kopyala",
    '"+yy'
)

normal_menu(
    240,
    "󰆴 Satırı Sil",
    '"_dd'
)

normal_menu(
    250,
    " Yapıştır",
    '"+gP'
)

normal_menu(
    260,
    "󰒆 Tümünü Seç",
    "ggVG"
)

-- ═════════════════════════════════════════════════════════════
-- VISUAL MODE
-- ═════════════════════════════════════════════════════════════

visual_menu(
    10,
    "󰌵 Kod Eylemleri",
    lua_action("code_action")
)

visual_menu(
    20,
    "󰈞 Seçimi Projede Ara",
    lua_action("grep_selection")
)

visual_separator(
    30,
    "visual"
)

visual_menu(
    40,
    " Kes",
    '"+x'
)

visual_menu(
    50,
    " Kopyala",
    '"+y'
)

visual_menu(
    60,
    "󰆴 Sil",
    '"_x'
)

visual_menu(
    70,
    " Yapıştır",
    '"+P'
)

visual_menu(
    80,
    "󰒆 Tümünü Seç",
    "gg0oG$"
)

-- ═════════════════════════════════════════════════════════════
-- INSERT MODE
-- ═════════════════════════════════════════════════════════════

insert_menu(
    10,
    " Yapıştır",
    "<C-r>+"
)

insert_separator(
    20,
    "insert"
)

insert_menu(
    30,
    "󰒆 Tümünü Seç",
    "<C-Home><C-O>VG"
)

-- ═════════════════════════════════════════════════════════════
-- BAĞLAMA DUYARLI MENÜ
-- ═════════════════════════════════════════════════════════════

local group = vim.api.nvim_create_augroup(
    "DemirContextMenu",
    {
        clear = true,
    }
)

vim.api.nvim_create_autocmd("MenuPopup", {
    group = group,
    pattern = "*",

    callback = function()
        -- LSP özellikleri yalnızca gerçekten destekleniyorsa aktif.
        set_enabled(
            "󰏫 Sembol Bilgisi",
            lsp_supports("textDocument/hover")
        )

        set_enabled(
            "󰌑 Tanıma Git",
            lsp_supports("textDocument/definition")
        )

        set_enabled(
            "󰈮 Bildirime Git",
            lsp_supports("textDocument/declaration")
        )

        set_enabled(
            "󰡱 Gerçeklemeye Git",
            lsp_supports("textDocument/implementation")
        )

        set_enabled(
            "󰙅 Tür Tanımına Git",
            lsp_supports("textDocument/typeDefinition")
        )

        set_enabled(
            "󰈇 Referansları Göster",
            lsp_supports("textDocument/references")
        )

        set_enabled(
            "󰑕 Yeniden Adlandır",
            lsp_supports("textDocument/rename")
        )

        set_enabled(
            "󰌵 Kod Eylemleri",
            lsp_supports("textDocument/codeAction")
        )

        set_enabled(
            "󰉼 Dosyayı Biçimlendir",
            lsp_supports("textDocument/formatting")
        )

        -- Bu satırda diagnostic yoksa seçenek pasif olsun.
        local line = vim.api.nvim_win_get_cursor(0)[1] - 1

        local line_diagnostics = vim.diagnostic.get(
            0,
            {
                lnum = line,
            }
        )

        set_enabled(
            "󰅚 Bu Satırdaki Sorun",
            #line_diagnostics > 0
        )

        -- Mevcut buffer'da diagnostic yoksa pasif.
        local buffer_diagnostics = vim.diagnostic.get(0)

        set_enabled(
            "󰈙 Dosyanın Sorunları",
            #buffer_diagnostics > 0
        )

        -- Dosyaya özel işlemler yalnızca gerçek bir buffer adı
        -- bulunduğunda aktif.
        local has_file = vim.api.nvim_buf_get_name(0) ~= ""

        set_enabled(
            "󰙅 Explorer'da Göster",
            has_file
        )

        set_enabled(
            "󰅍 Göreli Yolu Kopyala",
            has_file
        )

        set_enabled(
            "󰅍 Tam Yolu Kopyala",
            has_file
        )
    end,
})

return M
