local M = {}

local uv = vim.uv

-- BuildSentry currently exposes only a small public API.  The timing overlay
-- therefore has to integrate with implementation modules, but all such access
-- is kept in this file, capability-checked, and made fail-closed.  BuildSentry
-- itself explicitly documents that its APIs and behaviour may change.

local timer = nil
local installed = false
local api = nil

-- Keep timing metadata outside BuildSentry task objects.  This avoids adding
-- DemirVim-owned fields to plugin-owned state and lets dead tasks be collected.
local timings = setmetatable({}, { __mode = "k" })
local tracked_tasks = setmetatable({}, { __mode = "k" })

local RUNNING = {
    RUN = true,
    RUNNING = true,
}

local SUCCESS = {
    OK = true,
    SUCCESS = true,
}

local FAILED = {
    FAIL = true,
    FAILED = true,
}

local TERMINATED = {
    TRM = true,
    TERMINATED = true,
}

local function notify_once(message, level)
    vim.schedule(function()
        vim.notify_once(message, level or vim.log.levels.WARN, {
            title = "BuildSentry Time",
        })
    end)
end

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
    local task_day = os.date("%Y-%m-%d", timestamp)

    if task_day == today then
        return os.date("%H:%M:%S", timestamp)
    end

    return os.date("%d.%m %H:%M:%S", timestamp)
end

local function format_duration(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        return nil
    end

    if seconds < 0.01 then
        return "<0.01s"
    end

    if seconds < 10 then
        return string.format("%.2fs", seconds)
    end

    if seconds < 60 then
        return string.format("%.1fs", seconds)
    end

    local minutes = math.floor(seconds / 60)
    local remaining_seconds = math.floor(seconds % 60)

    if minutes < 60 then
        return string.format("%dm %02ds", minutes, remaining_seconds)
    end

    local hours = math.floor(minutes / 60)
    local remaining_minutes = minutes % 60

    return string.format("%dh %02dm %02ds", hours, remaining_minutes, remaining_seconds)
end

local function status_kind(task)
    if type(task) ~= "table" then
        return "unknown"
    end

    local status = task.status

    if RUNNING[status] then
        return "running"
    elseif SUCCESS[status] then
        return "success"
    elseif FAILED[status] then
        return "failed"
    elseif TERMINATED[status] then
        return "terminated"
    end

    return "unknown"
end

local function begin_task(task)
    if type(task) ~= "table" then
        return
    end

    timings[task] = {
        started_ns = now_ns(),
        started_clock = now_wall_clock(),
        finished_ns = nil,
    }
    tracked_tasks[task] = true
end

local function finish_task_if_needed(task)
    local timing = timings[task]

    if not timing or timing.finished_ns then
        return
    end

    if status_kind(task) == "running" then
        return
    end

    timing.finished_ns = now_ns()
end

local function task_duration(task)
    local timing = timings[task]

    if not timing or not timing.started_ns then
        return nil
    end

    local finished = timing.finished_ns or now_ns()
    local delta = finished - timing.started_ns

    if delta < 0 then
        return nil
    end

    return delta / 1e9
end

-- All private BuildSentry module discovery lives behind this boundary.
local function resolve_private_api()
    local ok_task, task_module = pcall(require, "buildsentry.task")
    local ok_list, task_list = pcall(require, "buildsentry.ui.task_list")
    local ok_state, state = pcall(require, "buildsentry.state")

    if not ok_task or type(task_module) ~= "table" or type(task_module.new) ~= "function" then
        return nil, "buildsentry.task.new is unavailable"
    end

    if
        not ok_list
        or type(task_list) ~= "table"
        or type(task_list.generate_task_format) ~= "function"
    then
        return nil, "buildsentry.ui.task_list.generate_task_format is unavailable"
    end

    return {
        task_module = task_module,
        task_list = task_list,
        state = ok_state and type(state) == "table" and state or nil,
        live_update = type(task_list.update) == "function",
    }
end

local function task_window_is_open()
    local state = api and api.state
    local windows = type(state) == "table" and state.windows or nil
    local win = type(windows) == "table" and windows.task or nil

    return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function wrap_task(task)
    if type(task) ~= "table" then
        return task
    end

    local original_start = task.start

    if type(original_start) ~= "function" then
        return task
    end

    task.start = function(self, ...)
        begin_task(self)
        return original_start(self, ...)
    end

    return task
end

local function extend_task_format(original_generate, task, selected)
    -- Finish timestamps are captured independently by the poller as well, but
    -- doing it here makes the final render immediately consistent.
    finish_task_if_needed(task)

    local format = original_generate(task, selected)
    local timing = timings[task]

    -- Tasks created before this integration was installed have no trustworthy
    -- start timestamp.  Do not fabricate a duration from first render time.
    if not timing then
        return format
    end

    if type(format) ~= "table" or type(format.virt_lines) ~= "table" then
        notify_once(
            "BuildSentry's task format no longer exposes virt_lines; timing overlay was skipped.",
            vim.log.levels.WARN
        )
        return format
    end

    local duration = task_duration(task)
    local duration_text = format_duration(duration)

    if not duration_text then
        return format
    end

    local kind = status_kind(task)

    if kind == "running" then
        duration_text = duration_text .. "…"
    end

    local normal_hl = kind == "success" and "DiagnosticOk"
        or kind == "failed" and "DiagnosticError"
        or kind == "terminated" and "DiagnosticWarn"
        or "DiagnosticInfo"

    local prefix_hl = selected and "Visual" or "Comment"
    local value_hl = selected and "Visual" or normal_hl

    table.insert(format.virt_lines, {
        { "  󰥔 ", prefix_hl },
        { format_clock(timing.started_clock), value_hl },
        { " · ", prefix_hl },
        { duration_text, value_hl },
    })

    return format
end

local function update_tracked_tasks()
    local can_redraw = api and api.live_update and task_window_is_open()

    for task in pairs(tracked_tasks) do
        finish_task_if_needed(task)

        if can_redraw and status_kind(task) == "running" then
            -- BuildSentry owns the actual render/update path.  This call is
            -- intentionally isolated and protected because it is not part of
            -- BuildSentry's documented public API.
            pcall(api.task_list.update, task)
        end
    end
end

local function close_timer()
    if not timer then
        return
    end

    pcall(timer.stop, timer)

    local ok, closing = pcall(timer.is_closing, timer)
    if not ok or not closing then
        pcall(timer.close, timer)
    end

    timer = nil
end

local function start_timer()
    if timer then
        return true
    end

    local ok, new_timer = pcall(uv.new_timer)

    if not ok or not new_timer then
        notify_once("A libuv timer could not be created; live task timing is disabled.", vim.log.levels.WARN)
        return false
    end

    timer = new_timer

    local started, err = pcall(timer.start, timer, 250, 250, vim.schedule_wrap(update_tracked_tasks))

    if not started then
        close_timer()
        notify_once("The task timing timer could not be started: " .. tostring(err), vim.log.levels.WARN)
        return false
    end

    return true
end

function M.setup()
    if installed or vim.g.demir_buildsentry_time_loaded then
        return true
    end

    local resolved, reason = resolve_private_api()

    if not resolved then
        notify_once(
            "BuildSentry timing integration was disabled because the plugin internals changed: " .. tostring(reason),
            vim.log.levels.WARN
        )
        return false
    end

    api = resolved

    -- Validate every mandatory hook before changing either function.  This
    -- avoids a half-installed monkey patch that would be wrapped again later.
    local original_new = api.task_module.new
    local original_generate = api.task_list.generate_task_format

    api.task_module.new = function(...)
        return wrap_task(original_new(...))
    end

    api.task_list.generate_task_format = function(task, selected)
        return extend_task_format(original_generate, task, selected)
    end

    installed = true
    vim.g.demir_buildsentry_time_loaded = true

    start_timer()

    local group = vim.api.nvim_create_augroup("DemirBuildSentryTime", {
        clear = true,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = close_timer,
    })

    return true
end

function M.status()
    return {
        installed = installed or vim.g.demir_buildsentry_time_loaded == true,
        timer_active = timer ~= nil,
        live_update = api and api.live_update == true or false,
        state_available = api and api.state ~= nil or false,
    }
end

return M
