local M = {}

local tutorial_path = vim.fn.stdpath("config") .. "/TUTORIAL.md"

function M.open()
    if vim.fn.filereadable(tutorial_path) == 0 then
        vim.notify(
            "Tuş rehberi bulunamadı: " .. tutorial_path,
            vim.log.levels.ERROR
        )

        return
    end

    local lines = vim.fn.readfile(tutorial_path)

    local width = math.min(
        math.floor(vim.o.columns * 0.85),
        110
    )

    local height = math.min(
        math.floor(vim.o.lines * 0.85),
        math.max(#lines + 2, 10)
    )

    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_lines(
        buf,
        0,
        -1,
        false,
        lines
    )

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = "markdown"

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Neovim Tuş Rehberi ",
        title_pos = "center",
    })

    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].cursorline = true

    local close = function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    vim.keymap.set("n", "q", close, {
        buffer = buf,
        silent = true,
        desc = "Tuş rehberini kapat",
    })

    vim.keymap.set("n", "<Esc>", close, {
        buffer = buf,
        silent = true,
        desc = "Tuş rehberini kapat",
    })
end

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
