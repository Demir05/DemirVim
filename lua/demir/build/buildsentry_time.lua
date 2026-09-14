local M = {}

local uv = vim.uv

local task_module = require("buildsentry.task")
local task_list = require("buildsentry.ui.task_list")
local state = require("buildsentry.state")

local timer = nil

-- Bu dosya yanlışlıkla iki kez yüklenirse BuildSentry'yi
-- iki kez sarmalamayı engeller.
if vim.g.demir_buildsentry_time_loaded then
    return M
end

vim.g.demir_buildsentry_time_loaded = true

-- ─────────────────────────────────────────────────────────────
-- Zaman yardımcıları
-- ─────────────────────────────────────────────────────────────

local function now_ns()
    return uv.hrtime()
end

local function now_wall_clock()
    return os.time()
end

local function format_clock(timestamp)
    if not timestamp then
        return "--:--:--"
    end

    local today = os.date("%Y-%m-%d")
    local task_day = os.date(
        "%Y-%m-%d",
        timestamp
    )

    -- Aynı gün içindeki tasklarda tarih kalabalığı oluşturma.
    if task_day == today then
        return os.date(
            "%H:%M:%S",
            timestamp
        )
    end

    -- Neovim çok uzun süre açık kalır ve task önceki güne
    -- ait olursa tarihi de göster.
    return os.date(
        "%d.%m %H:%M:%S",
        timestamp
    )
end

local function format_duration(seconds)
    if seconds < 0.01 then
        return "<0.01s"
    end

    if seconds < 10 then
        return string.format(
            "%.2fs",
            seconds
        )
    end

    if seconds < 60 then
        return string.format(
            "%.1fs",
            seconds
        )
    end

    local minutes =
        math.floor(seconds / 60)

    local remaining_seconds =
        math.floor(seconds % 60)

    if minutes < 60 then
        return string.format(
            "%dm %02ds",
            minutes,
            remaining_seconds
        )
    end

    local hours =
        math.floor(minutes / 60)

    local remaining_minutes =
        minutes % 60

    return string.format(
        "%dh %02dm %02ds",
        hours,
        remaining_minutes,
        remaining_seconds
    )
end

local function task_duration(task)
    local started =
        task._demir_started_ns

    if not started then
        return nil
    end

    local finished =
        task._demir_finished_ns
        or now_ns()

    return (
        finished - started
    ) / 1e9
end

-- ─────────────────────────────────────────────────────────────
-- Task zaman bilgisini yönet
-- ─────────────────────────────────────────────────────────────

local function begin_task(task)
    task._demir_started_ns =
        now_ns()

    task._demir_started_clock =
        now_wall_clock()

    task._demir_finished_ns =
        nil
end

local function finish_task_if_needed(task)
    if task.status == "RUN" then
        return
    end

    if not task._demir_started_ns then
        return
    end

    if task._demir_finished_ns then
        return
    end

    task._demir_finished_ns =
        now_ns()
end

-- ─────────────────────────────────────────────────────────────
-- Yeni BuildSentry tasklarını zamanla
-- ─────────────────────────────────────────────────────────────

local original_new =
    task_module.new

task_module.new = function(...)
    local task =
        original_new(...)

    local original_start =
        task.start

    task.start = function(self, ...)
        -- İlk çalıştırmada ve Restart işleminde sayaç
        -- yeniden başlar.
        begin_task(self)

        return original_start(
            self,
            ...
        )
    end

    return task
end

-- ─────────────────────────────────────────────────────────────
-- BuildSentry renderer'ını genişlet
-- ─────────────────────────────────────────────────────────────

local original_generate_task_format =
    task_list.generate_task_format

task_list.generate_task_format =
    function(task, selected)
        -- Eski bir task bu katman yüklenmeden önce oluşturulmuşsa
        -- yine de güvenli biçimde başlangıç bilgisi oluştur.
        if not task._demir_started_ns then
            begin_task(task)
        end

        finish_task_if_needed(task)

        local format =
            original_generate_task_format(
                task,
                selected
            )

        local duration =
            task_duration(task)

        if not duration then
            return format
        end

        local clock =
            format_clock(
                task._demir_started_clock
            )

        local duration_text =
            format_duration(duration)

        if task.status == "RUN" then
            duration_text =
                duration_text .. "…"
        end

        local normal_hl =
            task.status == "OK"
                and "DiagnosticOk"
            or task.status == "FAIL"
                and "DiagnosticError"
            or task.status == "TRM"
                and "DiagnosticWarn"
            or "DiagnosticInfo"

        local prefix_hl =
            selected
                and "Visual"
                or "Comment"

        local value_hl =
            selected
                and "Visual"
                or normal_hl

        -- BuildSentry zaten output için virt_lines kullanıyor.
        -- Aynı mekanizmaya ikinci bilgi satırımızı ekliyoruz.
        table.insert(
            format.virt_lines,
            {
                {
                    "  󰥔 ",
                    prefix_hl,
                },
                {
                    clock,
                    value_hl,
                },
                {
                    " · ",
                    prefix_hl,
                },
                {
                    duration_text,
                    value_hl,
                },
            }
        )

        return format
    end

-- ─────────────────────────────────────────────────────────────
-- Canlı süre güncellemesi
-- ─────────────────────────────────────────────────────────────

local function update_running_tasks()
    local task_window =
        state.windows.task

    -- BuildSentry kapalıysa hiçbir şey yapma.
    if
        not task_window
        or not vim.api.nvim_win_is_valid(
            task_window
        )
    then
        return
    end

    for _, task in ipairs(state.tasks) do
        if task.status == "RUN" then
            -- BuildSentry'nin kendi update mekanizmasını
            -- kullanıyoruz. Buffer'a doğrudan müdahale etmiyoruz.
            pcall(
                task_list.update,
                task
            )
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Setup
-- ─────────────────────────────────────────────────────────────

function M.setup()
    if timer then
        return
    end

    timer =
        uv.new_timer()

    timer:start(
        250,
        250,
        vim.schedule_wrap(
            update_running_tasks
        )
    )

    local group =
        vim.api.nvim_create_augroup(
            "DemirBuildSentryTime",
            {
                clear = true,
            }
        )

    vim.api.nvim_create_autocmd(
        "VimLeavePre",
        {
            group = group,

            callback = function()
                if not timer then
                    return
                end

                timer:stop()

                if not timer:is_closing() then
                    timer:close()
                end

                timer = nil
            end,
        }
    )
end

return M
