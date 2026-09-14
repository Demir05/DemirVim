local dap = require("dap")
local dap_view = require("dap-view")

-- ─────────────────────────────────────────────────────────────
-- Breakpoint Görünümü
-- ─────────────────────────────────────────────────────────────
--
-- cmake-tools, bizim debug modülümüzden önce nvim-dap'i yükleyebilir.
-- Bu durumda nvim-dap varsayılan B / C / R işaretlerini zaten
-- tanımlamış olur.
--
-- Bu nedenle mevcut işaretleri açıkça kaldırıp kendi IDE tarzı
-- işaretlerimizi yeniden tanımlıyoruz.
-- ─────────────────────────────────────────────────────────────

local signs = {
    DapBreakpoint = {
        text = "●",
        texthl = "DiagnosticError",
        linehl = "",
        numhl = "",
    },

    DapBreakpointCondition = {
        text = "◆",
        texthl = "DiagnosticWarn",
        linehl = "",
        numhl = "",
    },

    DapBreakpointRejected = {
        text = "○",
        texthl = "DiagnosticError",
        linehl = "",
        numhl = "",
    },

    DapLogPoint = {
        text = "◆",
        texthl = "DiagnosticInfo",
        linehl = "",
        numhl = "",
    },

    DapStopped = {
        text = "▶",
        texthl = "DiagnosticWarn",
        linehl = "CursorLine",
        numhl = "",
    },
}

for name, definition in pairs(signs) do
    pcall(
        vim.fn.sign_undefine,
        name
    )

    vim.fn.sign_define(
        name,
        definition
    )
end

-- ─────────────────────────────────────────────────────────────
-- GDB Debug Adapter
-- ─────────────────────────────────────────────────────────────

dap.adapters.gdb = {
    type = "executable",

    command = "gdb",

    args = {
        "--interpreter=dap",

        -- STL ve diğer C++ türlerini GDB tarafında daha okunabilir
        -- göstermek için pretty-printing etkinleştir.
        "--eval-command",
        "set print pretty on",
    },
}

-- ─────────────────────────────────────────────────────────────
-- DAP View
-- ─────────────────────────────────────────────────────────────

dap_view.setup({
    -- Debug oturumu başlayınca paneli otomatik aç.
    -- Bütün debug oturumları bitince otomatik kapat.
    auto_toggle = true,

    -- Değişken değerlerini kaynak kodun içinde göster.
    -- Neovim 0.12+ özelliği.
    virtual_text = {
        enabled = true,
        position = "inline",
    },
})

-- ─────────────────────────────────────────────────────────────
-- Genel DAP Davranışı
-- ─────────────────────────────────────────────────────────────

-- Stack frame'e geçerken gereksiz yeni tab'lar açılmasını azalt.
dap.defaults.fallback.switchbuf =
    "usetab,uselast"

-- ─────────────────────────────────────────────────────────────
-- Yardımcılar
-- ─────────────────────────────────────────────────────────────

local function save_all()
    local ok, err = pcall(
        vim.cmd,
        "silent wall"
    )

    if not ok then
        vim.notify(
            "Dosyalar kaydedilemedi:\n"
                .. tostring(err),
            vim.log.levels.ERROR,
            {
                title = "Debugger",
            }
        )

        return false
    end

    return true
end

local function require_session(callback)
    if not dap.session() then
        vim.notify(
            "Aktif debug oturumu yok.",
            vim.log.levels.INFO,
            {
                title = "Debugger",
            }
        )

        return
    end

    callback()
end

-- ─────────────────────────────────────────────────────────────
-- Debug Başlat / Devam
-- ─────────────────────────────────────────────────────────────

local function start_or_continue()
    -- Debugger zaten çalışıyorsa F5 artık Continue anlamına gelir.
    if dap.session() then
        dap.continue()
        return
    end

    if not save_all() then
        return
    end

    -- CMakeDebug:
    --
    -- 1. Seçili executable target'ı bulur.
    -- 2. Önce target'ı build eder.
    -- 3. Build başarısızsa burada durur.
    -- 4. Build başarılıysa nvim-dap üzerinden GDB'yi başlatır.
    --
    -- Kullanıcıdan binary yolu istemeyiz.
    vim.cmd("CMakeDebug")
end

-- ─────────────────────────────────────────────────────────────
-- Breakpoint
-- ─────────────────────────────────────────────────────────────

local function toggle_breakpoint()
    dap.toggle_breakpoint()
end

local function conditional_breakpoint()
    vim.ui.input(
        {
            prompt = "Breakpoint koşulu: ",
        },
        function(condition)
            if not condition
                or condition == ""
            then
                return
            end

            dap.set_breakpoint(
                condition
            )
        end
    )
end

-- ─────────────────────────────────────────────────────────────
-- Stepping
-- ─────────────────────────────────────────────────────────────

local function step_over()
    require_session(function()
        dap.step_over()
    end)
end

local function step_into()
    require_session(function()
        dap.step_into()
    end)
end

local function step_out()
    require_session(function()
        dap.step_out()
    end)
end

-- ─────────────────────────────────────────────────────────────
-- Restart / Stop
-- ─────────────────────────────────────────────────────────────

local function restart_debug()
    if dap.session() then
        dap.restart()
        return
    end

    if not save_all() then
        return
    end

    vim.cmd("CMakeDebug")
end

local function terminate_debug()
    require_session(function()
        dap.terminate()
    end)
end

-- ─────────────────────────────────────────────────────────────
-- Pause
-- ─────────────────────────────────────────────────────────────

local function pause_debug()
    require_session(function()
        dap.pause()
    end)
end

-- ─────────────────────────────────────────────────────────────
-- Debug Paneli
-- ─────────────────────────────────────────────────────────────

local function toggle_debug_view()
    dap_view.toggle()
end

-- ─────────────────────────────────────────────────────────────
-- Watch
-- ─────────────────────────────────────────────────────────────

local function add_watch()
    if not dap.session() then
        vim.notify(
            "Watch eklemek için önce debug oturumu başlat.",
            vim.log.levels.INFO,
            {
                title = "Debugger",
            }
        )

        return
    end

    dap_view.add_expr()
end

-- ─────────────────────────────────────────────────────────────
-- Debug Oturumu Bildirimleri
-- ─────────────────────────────────────────────────────────────

dap.listeners.after.event_initialized[
    "demir_debug"
] = function()
    vim.notify(
        "Debug oturumu başladı.",
        vim.log.levels.INFO,
        {
            title = "GDB",
        }
    )
end

dap.listeners.after.event_stopped[
    "demir_debug"
] = function()
    vim.notify(
        "Program duraklatıldı.",
        vim.log.levels.INFO,
        {
            title = "GDB",
        }
    )
end

dap.listeners.before.event_terminated[
    "demir_debug"
] = function()
    vim.notify(
        "Debug oturumu sonlandırıldı.",
        vim.log.levels.INFO,
        {
            title = "GDB",
        }
    )
end

dap.listeners.before.event_exited[
    "demir_debug"
] = function()
    vim.notify(
        "Program sona erdi.",
        vim.log.levels.INFO,
        {
            title = "GDB",
        }
    )
end

-- ─────────────────────────────────────────────────────────────
-- Debug Merkezi
-- ─────────────────────────────────────────────────────────────

local debug_actions = {
    {
        label = "▶  Başlat / Devam",
        action = start_or_continue,
    },

    {
        label = "⏸  Duraklat",
        action = pause_debug,
    },

    {
        label = "●  Breakpoint Ekle / Kaldır",
        action = toggle_breakpoint,
    },

    {
        label = "◆  Koşullu Breakpoint",
        action = conditional_breakpoint,
    },

    {
        label = "↷  Step Over",
        action = step_over,
    },

    {
        label = "↓  Step Into",
        action = step_into,
    },

    {
        label = "↑  Step Out",
        action = step_out,
    },

    {
        label = "󰁪  Watch Ekle",
        action = add_watch,
    },

    {
        label = "↻  Yeniden Başlat",
        action = restart_debug,
    },

    {
        label = "■  Durdur",
        action = terminate_debug,
    },

    {
        label = "◫  Debug Panelini Aç / Kapat",
        action = toggle_debug_view,
    },
}

local function open_debug_center()
    vim.ui.select(
        debug_actions,
        {
            prompt = "Debug Merkezi",

            format_item = function(item)
                return item.label
            end,
        },

        function(choice)
            if not choice then
                return
            end

            choice.action()
        end
    )
end

-- ─────────────────────────────────────────────────────────────
-- Kısayollar
-- ─────────────────────────────────────────────────────────────

local map = vim.keymap.set

-- Space+d
-- Bebek dostu görsel debug merkezi.
map(
    "n",
    "<leader>d",
    open_debug_center,
    {
        desc = "Debug merkezi",
    }
)

-- F5
-- Oturum yoksa:
--     Build -> Debug
--
-- Oturum varsa:
--     Continue
map(
    { "n", "i", "v" },
    "<F5>",
    start_or_continue,
    {
        desc = "Debug başlat / devam et",
    }
)

-- F9
-- Breakpoint ekle / kaldır.
map(
    { "n", "i", "v" },
    "<F9>",
    toggle_breakpoint,
    {
        desc = "Breakpoint aç / kapat",
    }
)

-- F10
-- Step Over.
map(
    { "n", "i", "v" },
    "<F10>",
    step_over,
    {
        desc = "Step over",
    }
)

-- F11
-- Step Into.
map(
    { "n", "i", "v" },
    "<F11>",
    step_into,
    {
        desc = "Step into",
    }
)

-- Shift+F11
-- Step Out.
map(
    { "n", "i", "v" },
    "<S-F11>",
    step_out,
    {
        desc = "Step out",
    }
)

-- Space+dt
-- Debug panelini manuel aç / kapat.
map(
    "n",
    "<leader>dt",
    toggle_debug_view,
    {
        desc = "Debug paneli",
    }
)

-- Space+dr
-- Debug oturumunu yeniden başlat.
map(
    "n",
    "<leader>dr",
    restart_debug,
    {
        desc = "Debug yeniden başlat",
    }
)

-- Space+dx
-- Debug oturumunu sonlandır.
map(
    "n",
    "<leader>dx",
    terminate_debug,
    {
        desc = "Debug durdur",
    }
)

-- Space+dp
-- Çalışan programı duraklat.
map(
    "n",
    "<leader>dp",
    pause_debug,
    {
        desc = "Debug duraklat",
    }
)

-- Space+dw
-- İmleç altındaki ifadeyi watch listesine ekle.
map(
    "n",
    "<leader>dw",
    add_watch,
    {
        desc = "Watch ekle",
    }
)
