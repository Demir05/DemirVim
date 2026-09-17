local M = {}

local workspace = require("demir.lsp.workspace")

-- ─────────────────────────────────────────────────────────────
-- Shared Symbol Metadata
-- ─────────────────────────────────────────────────────────────
--
-- Call Hierarchy and Type Hierarchy render the same LSP SymbolKind surface.
-- Keep this table in one place so icon/highlight drift cannot develop between
-- the two semantic tools.
-- ─────────────────────────────────────────────────────────────

local symbol_kinds = {
    [1] = { name = "File", icon = "󰈙", hl = "Directory" },
    [2] = { name = "Module", icon = "󰏗", hl = "Identifier" },
    [3] = { name = "Namespace", icon = "󰅩", hl = "Identifier" },
    [4] = { name = "Package", icon = "󰏖", hl = "Directory" },
    [5] = { name = "Class", icon = "󰠱", hl = "Type" },
    [6] = { name = "Method", icon = "󰆧", hl = "Function" },
    [7] = { name = "Property", icon = "󰜢", hl = "Identifier" },
    [8] = { name = "Field", icon = "󰜢", hl = "Identifier" },
    [9] = { name = "Constructor", icon = "󰆧", hl = "Function" },
    [10] = { name = "Enum", icon = "󰦨", hl = "Type" },
    [11] = { name = "Interface", icon = "󰜰", hl = "Type" },
    [12] = { name = "Function", icon = "󰊕", hl = "Function" },
    [13] = { name = "Variable", icon = "󰀫", hl = "Identifier" },
    [14] = { name = "Constant", icon = "󰏿", hl = "Constant" },
    [15] = { name = "String", icon = "󰉾", hl = "String" },
    [16] = { name = "Number", icon = "󰎠", hl = "Number" },
    [17] = { name = "Boolean", icon = "󰨙", hl = "Boolean" },
    [18] = { name = "Array", icon = "󰅪", hl = "Identifier" },
    [19] = { name = "Object", icon = "󰅩", hl = "Type" },
    [20] = { name = "Key", icon = "󰌆", hl = "Identifier" },
    [21] = { name = "Null", icon = "󰟢", hl = "Constant" },
    [22] = { name = "Enum Member", icon = "󰦨", hl = "Constant" },
    [23] = { name = "Struct", icon = "󰙅", hl = "Type" },
    [24] = { name = "Event", icon = "󱐋", hl = "Special" },
    [25] = { name = "Operator", icon = "󰆕", hl = "Operator" },
    [26] = { name = "Type Parameter", icon = "󰗴", hl = "Type" },
}

local fallback_kind = {
    name = "Symbol",
    icon = "󰘦",
    hl = "Identifier",
}

function M.kind_info(kind)
    return symbol_kinds[kind] or fallback_kind
end

-- ─────────────────────────────────────────────────────────────
-- Buffer / Path / Text Primitives
-- ─────────────────────────────────────────────────────────────

function M.valid_buf(buf)
    return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

function M.loaded_buf(buf)
    return M.valid_buf(buf) and vim.api.nvim_buf_is_loaded(buf)
end

function M.valid_win(win)
    return win ~= nil and vim.api.nvim_win_is_valid(win)
end

function M.normalize_path(path)
    if type(path) ~= "string" or path == "" then
        return ""
    end

    return vim.fs.normalize(path)
end

function M.one_line(value)
    if value == nil or value == vim.NIL then
        return ""
    end

    local ok, text = pcall(tostring, value)

    if not ok then
        return ""
    end

    return text:gsub("%c", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.safe_table(value)
    return type(value) == "table" and value or {}
end

function M.uri_to_file(uri)
    if type(uri) ~= "string" or not uri:match("^file:") then
        return nil
    end

    local ok, file = pcall(vim.uri_to_fname, uri)

    if not ok or type(file) ~= "string" or file == "" then
        return nil
    end

    return M.normalize_path(file)
end

local function relative_file_from_uri(roots, uri)
    local file = M.uri_to_file(uri)

    if not file then
        return M.one_line(uri or "<non-file URI>")
    end

    -- Root ownership remains centralized in demir.lsp.workspace. This helper
    -- only formats a path relative to the already-resolved semantic workspace.
    local relative = workspace.relative_path(roots, file)

    if relative then
        if relative == "." then
            return M.one_line(vim.fs.basename(file))
        end

        return M.one_line(relative)
    end

    return M.one_line(vim.fs.basename(file))
end

function M.item_location_text(roots, item)
    if type(item) ~= "table" then
        return ""
    end

    local range = item.selectionRange or item.range
    local line = type(range) == "table" and type(range.start) == "table" and range.start.line or nil
    local file = relative_file_from_uri(roots, item.uri)

    if line == nil then
        return file
    end

    return string.format("%s:%d", file, line + 1)
end

-- ─────────────────────────────────────────────────────────────
-- Scratch Buffers / Extmarks
-- ─────────────────────────────────────────────────────────────

function M.create_buffer(name)
    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_name(buf, name)

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false

    return buf
end

function M.set_lines(buf, lines)
    if not M.valid_buf(buf) then
        -- Match the hierarchy modules' historical no-op behavior for a buffer
        -- that disappeared before a scheduled render reached it.
        return true
    end

    local ok, err = pcall(function()
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end)

    if M.valid_buf(buf) then
        pcall(function()
            vim.bo[buf].modifiable = false
        end)
    end

    return ok, err
end

function M.safe_extmark(namespace, report_error, buf, row, col, opts)
    if not M.valid_buf(buf) then
        return nil
    end

    local line_count = vim.api.nvim_buf_line_count(buf)

    if line_count <= 0 then
        return nil
    end

    row = math.max(0, math.min(row or 0, line_count - 1))

    local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    col = math.max(0, math.min(col or 0, #text))

    opts = vim.deepcopy(opts or {})

    if opts.end_row ~= nil then
        opts.end_row = math.max(row, math.min(opts.end_row, line_count - 1))
    end

    if opts.end_col ~= nil then
        local end_row = opts.end_row or row
        local end_text = vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1] or ""
        local min_col = end_row == row and col or 0
        opts.end_col = math.max(min_col, math.min(opts.end_col, #end_text))
    end

    opts.strict = false

    local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, namespace, row, col, opts)

    if not ok then
        if type(report_error) == "function" then
            report_error("Extmark oluşturulamadı", id)
        end
        return nil
    end

    return id
end

function M.highlight_literal(namespace, report_error, buf, row, text, needle, hl)
    if not needle or needle == "" then
        return
    end

    local start_col = text:find(needle, 1, true)

    if not start_col then
        return
    end

    start_col = start_col - 1
    local end_col = math.min(start_col + #needle, #text)

    if end_col <= start_col then
        return
    end

    M.safe_extmark(namespace, report_error, buf, row, start_col, {
        end_col = end_col,
        hl_group = hl,
    })
end

-- ─────────────────────────────────────────────────────────────
-- LSP Positions / Shared Item Validation
-- ─────────────────────────────────────────────────────────────

local function lsp_character_to_byte(text, character, encoding)
    text = text or ""
    character = math.max(0, character or 0)

    local ok, byte_col = pcall(vim.str_byteindex, text, encoding or "utf-16", character, false)

    if not ok or byte_col == nil then
        return math.min(character, #text)
    end

    return math.max(0, math.min(byte_col, #text))
end

function M.clamp_position_in_lines(lines, position, encoding)
    lines = M.safe_table(lines)

    if #lines == 0 then
        return 0, 0
    end

    local row = math.max(0, math.min(position and position.line or 0, #lines - 1))
    local text = lines[row + 1] or ""
    local col = lsp_character_to_byte(text, position and position.character or 0, encoding)

    return row, col
end

local function nonnegative_integer(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

local function valid_position(position)
    return type(position) == "table"
        and nonnegative_integer(position.line)
        and nonnegative_integer(position.character)
end

local function position_before_or_equal(a, b)
    if a.line ~= b.line then
        return a.line < b.line
    end

    return a.character <= b.character
end

function M.valid_range(range)
    return type(range) == "table"
        and valid_position(range.start)
        and valid_position(range["end"])
        and position_before_or_equal(range.start, range["end"])
end

local function range_contains(outer, inner)
    return M.valid_range(outer)
        and M.valid_range(inner)
        and position_before_or_equal(outer.start, inner.start)
        and position_before_or_equal(inner["end"], outer["end"])
end

-- CallHierarchyItem and TypeHierarchyItem intentionally share the structural
-- fields validated here in LSP: name, kind, uri, range and selectionRange.
-- Protocol-specific relation payloads and opaque data remain owned by the
-- individual hierarchy modules.
function M.valid_item(item)
    return type(item) == "table"
        and type(item.name) == "string"
        and item.name ~= ""
        and nonnegative_integer(item.kind)
        and item.kind >= 1
        and type(item.uri) == "string"
        and item.uri ~= ""
        and M.valid_range(item.range)
        and M.valid_range(item.selectionRange)
        and range_contains(item.range, item.selectionRange)
end

function M.item_signature(item)
    if not M.valid_item(item) then
        return "<invalid>"
    end

    local start = item.selectionRange.start
    local finish = item.selectionRange["end"]

    return table.concat({
        item.uri,
        item.name,
        tostring(item.kind or 0),
        tostring(start.line),
        tostring(start.character),
        tostring(finish.line),
        tostring(finish.character),
    }, "\31")
end

-- ─────────────────────────────────────────────────────────────
-- Source Preview
-- ─────────────────────────────────────────────────────────────

function M.loaded_buffer_for_file(file)
    file = M.normalize_path(file)

    if file == "" then
        return nil
    end

    local candidate = vim.fn.bufnr(file)

    if candidate > 0 and M.loaded_buf(candidate) then
        return candidate
    end

    if type(vim.api.nvim_list_bufs) ~= "function" then
        return nil
    end

    -- URI spelling and buffer spelling can differ through symlinks. Only
    -- inspect already-loaded buffers; never create/load a source buffer here.
    local target_real = vim.uv.fs_realpath(file)
    target_real = target_real and M.normalize_path(target_real) or nil

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if M.loaded_buf(buf) then
            local name = M.normalize_path(vim.api.nvim_buf_get_name(buf))

            if name ~= "" then
                if name == file then
                    return buf
                end

                if target_real then
                    local name_real = vim.uv.fs_realpath(name)
                    name_real = name_real and M.normalize_path(name_real) or nil

                    if name_real == target_real then
                        return buf
                    end
                end
            end
        end
    end

    return nil
end

function M.source_descriptor(uri, mark_relevant_buffer)
    local file = M.uri_to_file(uri)

    if not file then
        return nil
    end

    local buf = M.loaded_buffer_for_file(file)

    if buf then
        if type(mark_relevant_buffer) == "function" then
            mark_relevant_buffer(buf)
        end

        local tick = vim.api.nvim_buf_get_changedtick(buf)
        local ft = vim.bo[buf].filetype

        if ft == "" then
            ft = vim.filetype.match({ filename = file }) or ""
        end

        return {
            buf = buf,
            file = file,
            ft = ft,
            token = string.format("buf:%d:%d:%s", buf, tick, ft),
        }
    end

    local stat = vim.uv.fs_stat(file)

    if not stat or stat.type ~= "file" then
        return nil
    end

    local mtime = stat.mtime or {}
    local ft = vim.filetype.match({ filename = file }) or ""
    local token = string.format(
        "disk:%s:%s:%s:%s",
        tostring(stat.size or 0),
        tostring(mtime.sec or 0),
        tostring(mtime.nsec or 0),
        ft
    )

    return {
        buf = nil,
        file = file,
        ft = ft,
        token = token,
    }
end

function M.read_source_lines(descriptor, report_error)
    if not descriptor then
        return nil
    end

    if M.loaded_buf(descriptor.buf) then
        return vim.api.nvim_buf_get_lines(descriptor.buf, 0, -1, false)
    end

    local ok, lines = pcall(vim.fn.readfile, descriptor.file)

    if not ok then
        if type(report_error) == "function" then
            report_error("Preview dosyası okunamadı", lines)
        end
        return nil
    end

    if #lines == 0 then
        return { "" }
    end

    return lines
end

-- ─────────────────────────────────────────────────────────────
-- LSP Client Discovery
-- ─────────────────────────────────────────────────────────────

function M.preferred_client_for_buffer(buf, method)
    if not buf then
        return nil
    end

    local clients = vim.lsp.get_clients({
        bufnr = buf,
        method = method,
    })

    if #clients == 0 then
        return nil
    end

    for _, client in ipairs(clients) do
        if client.name == "clangd" then
            return client
        end
    end

    return clients[1]
end

-- ─────────────────────────────────────────────────────────────
-- Shared Tree / Window Mechanics
-- ─────────────────────────────────────────────────────────────

function M.flatten_tree(node, output)
    if not node then
        return
    end

    table.insert(output, node)

    if not node.expanded then
        return
    end

    for _, child in ipairs(node.children or {}) do
        M.flatten_tree(child, output)
    end
end

function M.geometry(kind_name)
    local columns = math.max(1, vim.o.columns)
    local screen_lines = math.max(1, vim.o.lines - vim.o.cmdheight)

    if columns < 50 or screen_lines < 15 then
        return nil, string.format("Terminal çok küçük (%dx%d). En az 50x15 gerekir.", columns, screen_lines)
    end

    local margin_x = columns >= 78 and 2 or 1
    local margin_y = screen_lines >= 20 and 1 or 0

    local max_frame_width = columns - (margin_x * 2)
    local max_frame_height = screen_lines - (margin_y * 2)
    local frame_width = math.min(max_frame_width, math.max(50, math.floor(columns * 0.94)))
    local frame_height = math.min(max_frame_height, math.max(15, math.floor(screen_lines * 0.86)))

    local horizontal_gap = frame_width >= 76 and 1 or 0
    local vertical_gap = frame_height >= 20 and 1 or 0
    local border_width = 2
    local border_height = 2

    local header_height = frame_height >= 18 and 3 or 2
    local footer_height = frame_height >= 17 and 2 or 1

    local reserved_height = header_height + footer_height + (border_height * 3) + (vertical_gap * 2)
    local body_height = frame_height - reserved_height

    if body_height < 1 then
        return nil, string.format("Terminal yüksekliği %s yerleşimi için yetersiz.", kind_name or "Hierarchy")
    end

    local body_content_width = frame_width - horizontal_gap - (border_width * 2)

    if body_content_width < 2 then
        return nil, string.format("Terminal genişliği %s yerleşimi için yetersiz.", kind_name or "Hierarchy")
    end

    local left_width = math.max(1, math.floor(body_content_width * 0.43))
    local right_width = body_content_width - left_width

    if right_width < 1 then
        return nil, "Terminal genişliği Source Preview için yetersiz."
    end

    local col = math.max(0, math.floor((columns - frame_width) / 2))
    local row = math.max(0, math.floor((screen_lines - frame_height) / 2))
    local header_width = frame_width - border_width
    local footer_width = header_width
    local body_row = row + header_height + border_height + vertical_gap
    local right_col = col + left_width + border_width + horizontal_gap
    local footer_row = body_row + body_height + border_height + vertical_gap

    return {
        row = row,
        col = col,
        frame_width = frame_width,
        frame_height = frame_height,
        header_width = header_width,
        footer_width = footer_width,
        header_height = header_height,
        footer_height = footer_height,
        body_height = body_height,
        left_width = left_width,
        right_width = right_width,
        body_row = body_row,
        right_col = right_col,
        footer_row = footer_row,
    }
end

function M.float_config(row, col, width, height, title, focusable)
    return {
        relative = "editor",
        row = row,
        col = col,
        width = math.max(1, width),
        height = math.max(1, height),
        style = "minimal",
        border = "rounded",
        title = title,
        title_pos = "center",
        focusable = focusable ~= false,
        zindex = 65,
    }
end

function M.truncate_display(text, max_width)
    text = tostring(text or "")
    max_width = math.max(1, max_width or 1)

    if vim.fn.strdisplaywidth(text) <= max_width then
        return text
    end

    if max_width <= 1 then
        return "…"
    end

    local chars = vim.fn.strchars(text)
    local low = 0
    local high = chars
    local target = max_width - 1

    while low < high do
        local mid = math.ceil((low + high) / 2)
        local candidate = vim.fn.strcharpart(text, 0, mid)

        if vim.fn.strdisplaywidth(candidate) <= target then
            low = mid
        else
            high = mid - 1
        end
    end

    return vim.fn.strcharpart(text, 0, low) .. "…"
end

function M.selected_node(state)
    if type(state) ~= "table" or not M.valid_win(state.wins and state.wins.list) then
        return nil
    end

    local line = vim.api.nvim_win_get_cursor(state.wins.list)[1]

    if state.line_map and state.line_map[line] then
        return state.line_map[line]
    end

    for offset = 1, 30 do
        local down = state.line_map and state.line_map[line + offset]

        if down then
            return down
        end

        local up = state.line_map and state.line_map[line - offset]

        if up then
            return up
        end
    end

    return nil
end

function M.selected_key(state)
    local node = M.selected_node(state)
    return node and node.key or nil
end

function M.cleanup_ui(wins, bufs)
    for _, win in pairs(wins or {}) do
        if M.valid_win(win) then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end

    for _, buf in pairs(bufs or {}) do
        if M.valid_buf(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
end

function M.configure_window_appearance(wins)
    for _, win in pairs(wins or {}) do
        if M.valid_win(win) then
            vim.api.nvim_set_option_value(
                "winhighlight",
                "Normal:NormalFloat,"
                    .. "NormalNC:NormalFloat,"
                    .. "FloatBorder:FloatBorder,"
                    .. "FloatTitle:Title,"
                    .. "CursorLine:Visual,"
                    .. "EndOfBuffer:NormalFloat",
                { win = win }
            )

            vim.api.nvim_set_option_value("winblend", 0, { win = win })
            vim.api.nvim_set_option_value("wrap", false, { win = win })
        end
    end

    if M.valid_win(wins and wins.list) then
        vim.api.nvim_set_option_value("cursorline", true, { win = wins.list })
        vim.api.nvim_set_option_value("number", false, { win = wins.list })
        vim.api.nvim_set_option_value("relativenumber", false, { win = wins.list })
        vim.api.nvim_set_option_value("signcolumn", "no", { win = wins.list })
        vim.api.nvim_set_option_value("wrap", false, { win = wins.list })
        vim.api.nvim_set_option_value("scrolloff", 3, { win = wins.list })
    end

    if M.valid_win(wins and wins.preview) then
        vim.api.nvim_set_option_value("number", true, { win = wins.preview })
        vim.api.nvim_set_option_value("relativenumber", false, { win = wins.preview })
        vim.api.nvim_set_option_value("signcolumn", "yes", { win = wins.preview })
        vim.api.nvim_set_option_value("cursorline", true, { win = wins.preview })
        vim.api.nvim_set_option_value("wrap", false, { win = wins.preview })
        vim.api.nvim_set_option_value("scrolloff", 3, { win = wins.preview })
        vim.api.nvim_set_option_value("colorcolumn", "", { win = wins.preview })
    end
end

return M
