local M = {}

local tutorial_path = vim.fn.stdpath("config") .. "/TUTORIAL.md"

local CONTEXT_VAR = "demir_statusline_context"
local CONTEXT_VALUE = "tutorial"
local MIN_COLUMNS = 40
local MIN_LINES = 12

local state = {
    buf = nil,
    win = nil,
}

local function valid_buf(buf)
    return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
    return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, {
        title = "Tuş Rehberi",
    })
end

local function read_tutorial()
    if vim.fn.filereadable(tutorial_path) == 0 then
        notify("Tuş rehberi bulunamadı:\n" .. tutorial_path, vim.log.levels.ERROR)
        return nil
    end

    local ok, lines = pcall(vim.fn.readfile, tutorial_path)

    if not ok or type(lines) ~= "table" then
        notify("Tuş rehberi okunamadı:\n" .. tostring(lines), vim.log.levels.ERROR)
        return nil
    end

    if #lines == 0 then
        lines = { "" }
    end

    return lines
end

local function geometry(line_count)
    local columns = math.max(1, vim.o.columns)
    local usable_lines = math.max(1, vim.o.lines - vim.o.cmdheight)

    if columns < MIN_COLUMNS or usable_lines < MIN_LINES then
        return nil
    end

    local max_width = math.max(1, columns - 4)
    local max_height = math.max(1, usable_lines - 4)

    local width = math.min(math.floor(columns * 0.85), 110, max_width)
    local desired_height = math.max((line_count or 0) + 2, 10)
    local height = math.min(math.floor(usable_lines * 0.85), desired_height, max_height)

    width = math.max(1, width)
    height = math.max(1, height)

    return {
        relative = "editor",
        width = width,
        height = height,
        row = math.max(0, math.floor((usable_lines - height) / 2)),
        col = math.max(0, math.floor((columns - width) / 2)),
        style = "minimal",
        border = "rounded",
        title = " Neovim Tuş Rehberi ",
        title_pos = "center",
    }
end

local function clear_state()
    if not valid_win(state.win) then
        state.win = nil
    end

    if not valid_buf(state.buf) then
        state.buf = nil
    end
end

local function close_tutorial()
    local win = state.win

    state.win = nil

    if valid_win(win) then
        pcall(vim.api.nvim_win_close, win, true)
    end

    clear_state()
end

local function configure_buffer(buf, lines)
    -- The statusline consumes this explicit semantic marker. The tutorial is
    -- a nofile scratch buffer, so filesystem-name based detection is not a
    -- reliable contract.
    vim.b[buf][CONTEXT_VAR] = CONTEXT_VALUE

    -- Give the scratch buffer a stable DemirVim namespace for inspection and
    -- compatibility without pretending that it is TUTORIAL.md itself.
    pcall(vim.api.nvim_buf_set_name, buf, string.format("demir://tutorial/keys/%d", buf))

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = true

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    vim.bo[buf].modified = false
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].modifiable = false
end

local function configure_window(win)
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].cursorline = true
end

local function setup_buffer_keymaps(buf)
    local opts = {
        buffer = buf,
        silent = true,
        nowait = true,
    }

    vim.keymap.set("n", "q", close_tutorial, vim.tbl_extend("force", opts, {
        desc = "Tuş rehberini kapat",
    }))

    vim.keymap.set("n", "<Esc>", close_tutorial, vim.tbl_extend("force", opts, {
        desc = "Tuş rehberini kapat",
    }))
end

local function focus_existing()
    clear_state()

    if valid_win(state.win) then
        vim.api.nvim_set_current_win(state.win)
        return true
    end

    return false
end

function M.open()
    if focus_existing() then
        return
    end

    local lines = read_tutorial()

    if not lines then
        return
    end

    local config = geometry(#lines)

    if not config then
        notify(
            string.format(
                "Tuş rehberi için arayüz çok küçük. En az %d sütun ve %d kullanılabilir satır gerekir.",
                MIN_COLUMNS,
                MIN_LINES
            ),
            vim.log.levels.WARN
        )
        return
    end

    local buf = vim.api.nvim_create_buf(false, true)

    local ok, err = xpcall(function()
        configure_buffer(buf, lines)

        local win = vim.api.nvim_open_win(buf, true, config)

        state.buf = buf
        state.win = win

        configure_window(win)
        setup_buffer_keymaps(buf)

        vim.api.nvim_create_autocmd("BufWipeout", {
            buffer = buf,
            once = true,
            callback = function()
                if state.buf == buf then
                    state.buf = nil
                    state.win = nil
                end
            end,
        })
    end, debug.traceback)

    if not ok then
        if valid_buf(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end

        state.buf = nil
        state.win = nil

        notify("Tuş rehberi açılamadı:\n" .. tostring(err), vim.log.levels.ERROR)
    end
end

function M.close()
    close_tutorial()
end

-- Keep the modal centered and inside the editor after terminal resizing.
local resize_group = vim.api.nvim_create_augroup("DemirTutorial", {
    clear = true,
})

vim.api.nvim_create_autocmd("VimResized", {
    group = resize_group,
    callback = function()
        clear_state()

        if not valid_win(state.win) or not valid_buf(state.buf) then
            return
        end

        local line_count = vim.api.nvim_buf_line_count(state.buf)
        local config = geometry(line_count)

        if not config then
            close_tutorial()
            notify("Tuş rehberi pencere boyutu nedeniyle kapatıldı.", vim.log.levels.WARN)
            return
        end

        pcall(vim.api.nvim_win_set_config, state.win, config)
    end,
})

pcall(vim.api.nvim_del_user_command, "Keys")

vim.api.nvim_create_user_command("Keys", function()
    M.open()
end, {
    desc = "Neovim tuş rehberini aç",
})

vim.keymap.set("n", "<leader>?", function()
    M.open()
end, {
    desc = "Tuş rehberini aç",
})

return M
