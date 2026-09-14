local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

local group = augroup("DemirCore", {
    clear = true,
})

-- Highlight copied text.
autocmd("TextYankPost", {
    group = group,

    callback = function()
        vim.hl.on_yank({
            timeout = 150,
        })
    end,
})

-- Return to the last cursor position when reopening a file.
autocmd("BufReadPost", {
    group = group,

    callback = function(args)
        local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
        local line_count = vim.api.nvim_buf_line_count(args.buf)

        if mark[1] > 0 and mark[1] <= line_count then
            pcall(
                vim.api.nvim_win_set_cursor,
                0,
                mark
            )
        end
    end,
})

-- Resize splits automatically when the terminal window changes size.
autocmd("VimResized", {
    group = group,

    callback = function()
        vim.cmd("tabdo wincmd =")
    end,
})
