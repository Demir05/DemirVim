local M = {}

local Snacks = require("snacks")

local ok_formatting, Formatting = pcall(require, "demir.editor.formatting")

if not ok_formatting or type(Formatting) ~= "table" then
	Formatting = nil
end

local ok_conform, Conform = pcall(require, "conform")

if not ok_conform or type(Conform) ~= "table" then
	Conform = nil
end

-- Right-click should act on the object under the mouse.
vim.opt.mousemodel = "popup_setpos"

local CALL_HIERARCHY_METHOD = "textDocument/prepareCallHierarchy"
local TYPE_HIERARCHY_METHOD = "textDocument/prepareTypeHierarchy"

-- This root is only a UI base for "Copy Relative Path". It does not own
-- analysis, CMake, or LSP workspace semantics. All markers have equal priority
-- so the nearest enclosing project boundary wins instead of a distant .git
-- repository unconditionally outranking a nested language/build project.
local RELATIVE_PATH_ROOT_MARKERS = {
	{
		".git",
		"CMakePresets.json",
		"CMakeUserPresets.json",
		"CMakeLists.txt",
		"pyproject.toml",
		"package.json",
		"Cargo.toml",
		"go.mod",
	},
}

-- ─────────────────────────────────────────────────────────────
-- Basic Helpers
-- ─────────────────────────────────────────────────────────────

local function valid_buf(buf)
	return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
	return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function loaded_buf(buf)
	return valid_buf(buf) and vim.api.nvim_buf_is_loaded(buf)
end

local function notify(message, level, title)
	vim.notify(message, level or vim.log.levels.INFO, {
		title = title or "Context Menu",
	})
end

local function report_internal_error(context, err)
	vim.schedule(function()
		vim.notify_once(
			string.format("%s: %s", context, tostring(err)),
			vim.log.levels.WARN,
			{ title = "Context Menu" }
		)
	end)
end

local function normalize_path(path)
	if type(path) ~= "string" or path == "" then
		return ""
	end

	return vim.fs.normalize(path)
end

local function normal_buffer(buf)
	return loaded_buf(buf) and vim.bo[buf].buftype == ""
end

local function normal_file_buffer(buf)
	return normal_buffer(buf) and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function current_file(buf)
	buf = buf or vim.api.nvim_get_current_buf()

	if not normal_file_buffer(buf) then
		return nil
	end

	local file = normalize_path(vim.api.nvim_buf_get_name(buf))

	if file == "" then
		return nil
	end

	return file
end

local function relative_path_root(file)
	file = normalize_path(file)

	if file == "" then
		return normalize_path(vim.fn.getcwd())
	end

	local root = vim.fs.root(file, RELATIVE_PATH_ROOT_MARKERS)

	return normalize_path(root or vim.fn.getcwd())
end

local function clipboard_text()
	local ok, value = pcall(vim.fn.getreg, "+")

	if not ok or type(value) ~= "string" then
		return ""
	end

	return value
end

local function set_clipboard(value)
	if type(value) ~= "string" then
		return false
	end

	local ok, err = pcall(vim.fn.setreg, "+", value)

	if not ok then
		notify("The system clipboard could not be updated: " .. tostring(err), vim.log.levels.ERROR, "Clipboard")
		return false
	end

	return true
end

-- ─────────────────────────────────────────────────────────────
-- LSP Helpers
-- ─────────────────────────────────────────────────────────────

local function lsp_supports(method, buf)
	buf = buf or vim.api.nvim_get_current_buf()

	if not loaded_buf(buf) then
		return false
	end

	local ok, clients = pcall(vim.lsp.get_clients, {
		bufnr = buf,
		method = method,
	})

	return ok and type(clients) == "table" and #clients > 0
end

local function with_lsp_method(method, callback)
	local buf = vim.api.nvim_get_current_buf()

	if not lsp_supports(method, buf) then
		notify(
			"This action is not supported by an LSP client attached to the current buffer.",
			vim.log.levels.WARN,
			"Code"
		)
		return false
	end

	local ok, err = xpcall(callback, debug.traceback)

	if not ok then
		report_internal_error("LSP context-menu action failed", err)
		return false
	end

	return true
end

-- ─────────────────────────────────────────────────────────────
-- Formatting
-- ─────────────────────────────────────────────────────────────

local function can_format(buf)
	if not normal_buffer(buf) then
		return false
	end

	if Formatting and type(Formatting.can_format) == "function" then
		local ok, result = pcall(Formatting.can_format, buf)

		if ok then
			return result == true
		end
	end

	if Conform and type(Conform.list_formatters) == "function" then
		local ok, formatters = pcall(Conform.list_formatters, buf)

		if ok and type(formatters) == "table" and #formatters > 0 then
			return true
		end
	end

	return lsp_supports("textDocument/formatting", buf)
end

local function format_buffer(buf)
	if not normal_buffer(buf) then
		notify("The current buffer cannot be formatted.", vim.log.levels.WARN, "Formatting")
		return false
	end

	if Formatting and type(Formatting.format_buffer) == "function" then
		local ok, result = pcall(Formatting.format_buffer, buf)

		if not ok then
			report_internal_error("Formatting module failed", result)
			return false
		end

		return result ~= false
	end

	if Conform and type(Conform.format) == "function" then
		local ok, attempted = pcall(Conform.format, {
			bufnr = buf,
			async = true,
			lsp_format = "fallback",
		})

		if not ok then
			report_internal_error("Conform formatting failed", attempted)
			return false
		end

		if attempted ~= true then
			notify("No formatter is available for the current buffer.", vim.log.levels.WARN, "Formatting")
			return false
		end

		return true
	end

	if lsp_supports("textDocument/formatting", buf) then
		local ok, err = pcall(vim.lsp.buf.format, {
			bufnr = buf,
			async = true,
		})

		if not ok then
			report_internal_error("LSP formatting failed", err)
			return false
		end

		return true
	end

	notify("No formatter is available for the current buffer.", vim.log.levels.WARN, "Formatting")
	return false
end

-- ─────────────────────────────────────────────────────────────
-- Snacks Picker Discovery
-- ─────────────────────────────────────────────────────────────

local function active_pickers(source)
	if type(Snacks.picker) ~= "table" or type(Snacks.picker.get) ~= "function" then
		return {}
	end

	local opts = {
		tab = true,
	}

	if source then
		opts.source = source
	end

	local ok, pickers = pcall(Snacks.picker.get, opts)

	if not ok or type(pickers) ~= "table" then
		return {}
	end

	return pickers
end

-- Snacks documents both Snacks.picker.current and Snacks.picker.get().  Use
-- those public picker surfaces instead of reaching through picker.list.win.win.
-- The one-picker fallback only applies while actually inside a picker buffer;
-- it exists for compatibility with Snacks versions where `current` may be nil
-- during a MenuPopup callback.
local function current_picker(source)
	if type(Snacks.picker) ~= "table" then
		return nil
	end

	local active = active_pickers(source)
	local current = Snacks.picker.current

	if type(current) == "table" then
		for _, picker in ipairs(active) do
			if picker == current then
				return picker
			end
		end
	end

	local buf = vim.api.nvim_get_current_buf()
	local ft = valid_buf(buf) and vim.bo[buf].filetype or ""

	if ft == "snacks_picker_list" and #active == 1 then
		return active[1]
	end

	return nil
end

local function picker_current_item(picker)
	if type(picker) ~= "table" or type(picker.current) ~= "function" then
		return nil
	end

	local ok, item = pcall(picker.current, picker)

	if not ok then
		return nil
	end

	return item
end

local function picker_selected_count(picker)
	if type(picker) ~= "table" or type(picker.selected) ~= "function" then
		return 0
	end

	local ok, selected = pcall(picker.selected, picker)

	if not ok or type(selected) ~= "table" then
		return 0
	end

	return #selected
end

local function run_picker_action(picker, action, title)
	if type(picker) ~= "table" or type(picker.action) ~= "function" then
		notify("The active Snacks picker is no longer available.", vim.log.levels.WARN, title or "Picker")
		return false
	end

	local ok, err = xpcall(function()
		picker:action(action)
	end, debug.traceback)

	if not ok then
		report_internal_error("Snacks picker action failed", err)
		return false
	end

	return true
end

-- ─────────────────────────────────────────────────────────────
-- Source / LSP Actions
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

function M.call_hierarchy()
	with_lsp_method(CALL_HIERARCHY_METHOD, function()
		local hierarchy = require("demir.lsp.call_hierarchy")

		if type(hierarchy) ~= "table" or type(hierarchy.open) ~= "function" then
			error("demir.lsp.call_hierarchy does not expose open()")
		end

		hierarchy.open()
	end)
end

function M.type_hierarchy()
	with_lsp_method(TYPE_HIERARCHY_METHOD, function()
		local hierarchy = require("demir.lsp.type_hierarchy")

		if type(hierarchy) ~= "table" or type(hierarchy.open) ~= "function" then
			error("demir.lsp.type_hierarchy does not expose open()")
		end

		hierarchy.open()
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
	format_buffer(vim.api.nvim_get_current_buf())
end

-- ─────────────────────────────────────────────────────────────
-- Diagnostics
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
-- Search
-- ─────────────────────────────────────────────────────────────

function M.grep_word()
	Snacks.picker.grep_word()
end

function M.grep_selection()
	-- Snacks grep_word uses the Visual selection in Visual mode.
	Snacks.picker.grep_word()
end

-- ─────────────────────────────────────────────────────────────
-- File Actions
-- ─────────────────────────────────────────────────────────────

function M.reveal_file()
	local buf = vim.api.nvim_get_current_buf()
	local file = current_file(buf)

	if not file then
		notify("The current buffer is not associated with a file.", vim.log.levels.WARN, "File")
		return
	end

	local ok, err = xpcall(function()
		Snacks.explorer.reveal({
			buf = buf,
			file = file,
		})
	end, debug.traceback)

	if not ok then
		report_internal_error("Explorer reveal failed", err)
	end
end

function M.copy_absolute_path()
	local file = current_file()

	if not file then
		notify("The current buffer is not associated with a file.", vim.log.levels.WARN, "File")
		return
	end

	if set_clipboard(file) then
		notify("Absolute file path copied to the clipboard.", vim.log.levels.INFO, "File")
	end
end

function M.copy_relative_path()
	local file = current_file()

	if not file then
		notify("The current buffer is not associated with a file.", vim.log.levels.WARN, "File")
		return
	end

	local root = relative_path_root(file)
	local relative = vim.fs.relpath(root, file)

	if not relative then
		relative = vim.fn.fnamemodify(file, ":.")
	end

	if set_clipboard(relative) then
		notify("Relative file path copied to the clipboard.", vim.log.levels.INFO, "File")
	end
end

-- ─────────────────────────────────────────────────────────────
-- Explorer Actions
-- ─────────────────────────────────────────────────────────────

local function current_explorer_picker()
	return current_picker("explorer")
end

local function require_explorer_picker()
	local picker = current_explorer_picker()

	if not picker then
		notify("The Snacks Explorer list is no longer active.", vim.log.levels.WARN, "Explorer")
		return nil
	end

	return picker
end

function M.explorer_open()
	local picker = require_explorer_picker()

	if picker then
		run_picker_action(picker, "confirm", "Explorer")
	end
end

function M.explorer_open_split()
	local picker = require_explorer_picker()

	if picker then
		run_picker_action(picker, "edit_split", "Explorer")
	end
end

function M.explorer_open_vsplit()
	local picker = require_explorer_picker()

	if picker then
		run_picker_action(picker, "edit_vsplit", "Explorer")
	end
end

function M.explorer_add()
	local picker = require_explorer_picker()

	if picker then
		run_picker_action(picker, "explorer_add", "Explorer")
	end
end

function M.explorer_rename()
	local picker = require_explorer_picker()

	if picker then
		run_picker_action(picker, "explorer_rename", "Explorer")
	end
end

function M.explorer_copy()
	local picker = require_explorer_picker()

	if picker then
		run_picker_action(picker, "explorer_copy", "Explorer")
	end
end

function M.explorer_delete()
	local picker = require_explorer_picker()

	if picker then
		run_picker_action(picker, "explorer_del", "Explorer")
	end
end

function M.explorer_refresh()
	local picker = require_explorer_picker()

	if picker then
		run_picker_action(picker, "explorer_update", "Explorer")
	end
end

function M.explorer_copy_absolute_path()
	local picker = require_explorer_picker()

	if not picker then
		return
	end

	local item = picker_current_item(picker)
	local file = item and normalize_path(item.file) or ""

	if file == "" then
		notify("No filesystem item is selected.", vim.log.levels.INFO, "Explorer")
		return
	end

	if set_clipboard(file) then
		notify("Explorer path copied to the clipboard.", vim.log.levels.INFO, "Explorer")
	end
end

function M.explorer_copy_relative_path()
	local picker = require_explorer_picker()

	if not picker then
		return
	end

	local item = picker_current_item(picker)
	local file = item and normalize_path(item.file) or ""

	if file == "" then
		notify("No filesystem item is selected.", vim.log.levels.INFO, "Explorer")
		return
	end

	local ok, cwd = pcall(picker.cwd, picker)

	if not ok or type(cwd) ~= "string" or cwd == "" then
		cwd = vim.fn.getcwd()
	end

	cwd = normalize_path(cwd)
	local relative = vim.fs.relpath(cwd, file) or file

	if set_clipboard(relative) then
		notify("Explorer-relative path copied to the clipboard.", vim.log.levels.INFO, "Explorer")
	end
end

function M.explorer_terminal_here()
	local picker = require_explorer_picker()

	if not picker then
		return
	end

	local item = picker_current_item(picker)
	local file = item and normalize_path(item.file) or ""

	if file == "" then
		notify("No filesystem item is selected.", vim.log.levels.INFO, "Explorer")
		return
	end

	local is_dir = vim.fn.isdirectory(file) == 1
	local dir = is_dir and file or vim.fs.dirname(file)

	if type(dir) ~= "string" or dir == "" or vim.fn.isdirectory(dir) ~= 1 then
		notify("A valid directory could not be resolved for this item.", vim.log.levels.WARN, "Explorer")
		return
	end

	local ok, err = xpcall(function()
		Snacks.terminal.toggle(nil, {
			cwd = dir,
		})
	end, debug.traceback)

	if not ok then
		report_internal_error("Explorer terminal action failed", err)
	end
end

-- ─────────────────────────────────────────────────────────────
-- Generic Snacks Picker Actions
-- ─────────────────────────────────────────────────────────────

local function current_generic_picker()
	return current_picker(nil)
end

local function require_generic_picker()
	local picker = current_generic_picker()

	if not picker then
		notify("The Snacks picker is no longer active.", vim.log.levels.WARN, "Picker")
		return nil
	end

	return picker
end

function M.picker_open()
	local picker = require_generic_picker()

	if picker then
		run_picker_action(picker, "confirm", "Picker")
	end
end

function M.picker_open_split()
	local picker = require_generic_picker()

	if picker then
		run_picker_action(picker, "edit_split", "Picker")
	end
end

function M.picker_open_vsplit()
	local picker = require_generic_picker()

	if picker then
		run_picker_action(picker, "edit_vsplit", "Picker")
	end
end

function M.picker_close()
	local picker = require_generic_picker()

	if picker then
		run_picker_action(picker, "cancel", "Picker")
	end
end

-- ─────────────────────────────────────────────────────────────
-- Terminal Actions
-- ─────────────────────────────────────────────────────────────

function M.terminal_paste()
	local buf = vim.api.nvim_get_current_buf()

	if not loaded_buf(buf) or vim.bo[buf].buftype ~= "terminal" then
		notify("The current buffer is not a terminal.", vim.log.levels.WARN, "Terminal")
		return
	end

	local text = clipboard_text()

	if text == "" then
		notify("The system clipboard is empty.", vim.log.levels.INFO, "Terminal")
		return
	end

	local ok, result = pcall(vim.api.nvim_paste, text, false, -1)

	if not ok or result == false then
		notify("Clipboard text could not be pasted into the terminal.", vim.log.levels.ERROR, "Terminal")
	end
end

function M.terminal_hide()
	local buf = vim.api.nvim_get_current_buf()

	if not loaded_buf(buf) or vim.bo[buf].buftype ~= "terminal" then
		return
	end

	-- Hide the window without terminating the terminal job. This keeps the
	-- terminal reusable by Snacks.terminal.toggle().
	local ok, err = pcall(vim.cmd, "hide")

	if not ok then
		report_internal_error("Terminal could not be hidden", err)
	end
end

-- ─────────────────────────────────────────────────────────────
-- Context Detection
-- ─────────────────────────────────────────────────────────────

local function detect_context()
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	if not loaded_buf(buf) or not valid_win(win) then
		return {
			kind = "special",
			buf = buf,
			win = win,
		}
	end

	if vim.bo[buf].buftype == "terminal" then
		return {
			kind = "terminal",
			buf = buf,
			win = win,
		}
	end

	local explorer = current_picker("explorer")

	if explorer then
		return {
			kind = "explorer",
			buf = buf,
			win = win,
			picker = explorer,
			item = picker_current_item(explorer),
			selected_count = picker_selected_count(explorer),
		}
	end

	local picker = current_picker(nil)

	if picker then
		return {
			kind = "picker",
			buf = buf,
			win = win,
			picker = picker,
			item = picker_current_item(picker),
		}
	end

	if normal_buffer(buf) then
		local file = current_file(buf)

		return {
			kind = "source",
			buf = buf,
			win = win,
			file = file,
			has_file = file ~= nil,
		}
	end

	return {
		kind = "special",
		buf = buf,
		win = win,
		buftype = vim.bo[buf].buftype,
		filetype = vim.bo[buf].filetype,
	}
end

-- ─────────────────────────────────────────────────────────────
-- Menu Rendering
-- ─────────────────────────────────────────────────────────────

local menu_modes = {
	n = {
		define = "nnoremenu",
		remove = "nunmenu",
		state = "nmenu",
	},
	v = {
		define = "vnoremenu",
		remove = "vunmenu",
		state = "vmenu",
	},
	i = {
		define = "inoremenu",
		remove = "iunmenu",
		state = "imenu",
	},
	tl = {
		define = "tlnoremenu",
		remove = "tlunmenu",
		state = "tlmenu",
	},
}

local function escape_label(label)
	return label:gsub("\\", "\\\\"):gsub(" ", "\\ "):gsub("%.", "\\."):gsub("|", "\\|")
end

local function menu_path(label)
	return "PopUp." .. escape_label(label)
end

local function lua_action(function_name)
	return string.format('<Cmd>lua require("demir.ui.context_menu").%s()<CR>', function_name)
end

local function clear_popup(mode)
	local commands = menu_modes[mode]

	if not commands then
		return
	end

	pcall(vim.cmd, string.format("silent! %s PopUp", commands.remove))
end

local function set_menu_enabled(mode, label, enabled)
	local commands = menu_modes[mode]

	if not commands then
		return
	end

	pcall(
		vim.cmd,
		string.format("silent! %s %s %s", commands.state, enabled and "enable" or "disable", menu_path(label))
	)
end

local function define_menu_item(mode, priority, item)
	local commands = menu_modes[mode]

	if not commands then
		return
	end

	local ok, err = pcall(
		vim.cmd,
		string.format(
			"%s <silent> 1.%d %s %s",
			commands.define,
			priority,
			menu_path(item.label),
			item.action or "<Nop>"
		)
	)

	if not ok then
		report_internal_error("Popup item could not be created", err)
		return
	end

	if item.enabled == false then
		set_menu_enabled(mode, item.label, false)
	end
end

local function separator(name)
	return {
		separator = true,
		label = "-" .. name .. "-",
		action = "<Nop>",
	}
end

local function compact_items(items)
	local visible = {}

	for _, item in ipairs(items or {}) do
		if item.visible ~= false then
			if item.separator then
				if #visible > 0 and not visible[#visible].separator then
					table.insert(visible, item)
				end
			else
				table.insert(visible, item)
			end
		end
	end

	while #visible > 0 and visible[#visible].separator do
		table.remove(visible)
	end

	return visible
end

local function render_menu(mode, items)
	clear_popup(mode)

	local priority = 10

	for _, item in ipairs(compact_items(items)) do
		define_menu_item(mode, priority, item)
		priority = priority + 10
	end
end

-- ─────────────────────────────────────────────────────────────
-- Menu Specifications
-- ─────────────────────────────────────────────────────────────

local function source_normal_menu(ctx)
	local line = vim.api.nvim_win_get_cursor(ctx.win)[1] - 1
	local line_diagnostics = vim.diagnostic.get(ctx.buf, {
		lnum = line,
	})
	local buffer_diagnostics = vim.diagnostic.get(ctx.buf)
	local workspace_diagnostics = vim.diagnostic.get(nil)
	local cword = vim.fn.expand("<cword>")

	return {
		{
			label = "󰏫 Hover Documentation",
			action = lua_action("hover"),
			enabled = lsp_supports("textDocument/hover", ctx.buf),
		},
		{
			label = "󰌑 Go to Definition",
			action = lua_action("definition"),
			enabled = lsp_supports("textDocument/definition", ctx.buf),
		},
		{
			label = "󰈮 Go to Declaration",
			action = lua_action("declaration"),
			enabled = lsp_supports("textDocument/declaration", ctx.buf),
		},
		{
			label = "󰡱 Go to Implementation",
			action = lua_action("implementation"),
			enabled = lsp_supports("textDocument/implementation", ctx.buf),
		},
		{
			label = "󰙅 Go to Type Definition",
			action = lua_action("type_definition"),
			enabled = lsp_supports("textDocument/typeDefinition", ctx.buf),
		},
		{
			label = "󰈇 Find References",
			action = lua_action("references"),
			enabled = lsp_supports("textDocument/references", ctx.buf),
		},

		separator("semantic"),

		{
			label = "󰘦 Call Hierarchy",
			action = lua_action("call_hierarchy"),
			enabled = lsp_supports(CALL_HIERARCHY_METHOD, ctx.buf),
		},
		{
			label = "󰠱 Type Hierarchy",
			action = lua_action("type_hierarchy"),
			enabled = lsp_supports(TYPE_HIERARCHY_METHOD, ctx.buf),
		},

		separator("refactor"),

		{
			label = "󰑕 Rename Symbol",
			action = lua_action("rename"),
			enabled = lsp_supports("textDocument/rename", ctx.buf),
		},
		{
			label = "󰌵 Code Actions",
			action = lua_action("code_action"),
			enabled = lsp_supports("textDocument/codeAction", ctx.buf),
		},
		{
			label = "󰉼 Format Document",
			action = lua_action("format"),
			enabled = can_format(ctx.buf),
		},

		separator("problems"),

		{
			label = "󰅚 Problems on This Line",
			action = lua_action("diagnostic_here"),
			enabled = #line_diagnostics > 0,
		},
		{
			label = "󰈙 File Problems",
			action = lua_action("buffer_diagnostics"),
			enabled = #buffer_diagnostics > 0,
		},
		{
			label = "󰓦 Workspace Problems",
			action = lua_action("project_diagnostics"),
			enabled = #workspace_diagnostics > 0,
		},

		separator("file"),

		{
			label = "󰱼 Search Word in Project",
			action = lua_action("grep_word"),
			enabled = type(cword) == "string" and cword ~= "",
		},
		{
			label = "󰙅 Reveal in Explorer",
			action = lua_action("reveal_file"),
			visible = ctx.has_file,
		},
		{
			label = "󰅍 Copy Relative Path",
			action = lua_action("copy_relative_path"),
			visible = ctx.has_file,
		},
		{
			label = "󰅍 Copy Absolute Path",
			action = lua_action("copy_absolute_path"),
			visible = ctx.has_file,
		},

		separator("edit"),

		{
			label = "󰕌 Undo",
			action = "<Cmd>undo<CR>",
			enabled = vim.bo[ctx.buf].modifiable,
		},
		{
			label = "󰑎 Redo",
			action = "<Cmd>redo<CR>",
			enabled = vim.bo[ctx.buf].modifiable,
		},
		{
			label = " Cut Line",
			action = '"+dd',
			enabled = vim.bo[ctx.buf].modifiable,
		},
		{
			label = " Copy Line",
			action = '"+yy',
		},
		{
			label = "󰆴 Delete Line",
			action = '"_dd',
			enabled = vim.bo[ctx.buf].modifiable,
		},
		{
			label = " Paste",
			action = '"+gP',
			enabled = vim.bo[ctx.buf].modifiable and clipboard_text() ~= "",
		},
		{
			label = "󰒆 Select All",
			action = "ggVG",
		},
	}
end

local function source_visual_menu(ctx)
	return {
		{
			label = "󰌵 Code Actions",
			action = lua_action("code_action"),
			enabled = lsp_supports("textDocument/codeAction", ctx.buf),
		},
		{
			label = "󰈞 Search Selection in Project",
			action = lua_action("grep_selection"),
		},

		separator("selection"),

		{
			label = " Cut",
			action = '"+x',
			enabled = vim.bo[ctx.buf].modifiable,
		},
		{
			label = " Copy",
			action = '"+y',
		},
		{
			label = "󰆴 Delete",
			action = '"_x',
			enabled = vim.bo[ctx.buf].modifiable,
		},
		{
			label = " Paste",
			action = '"+P',
			enabled = vim.bo[ctx.buf].modifiable and clipboard_text() ~= "",
		},
		{
			label = "󰒆 Select All",
			action = "gg0oG$",
		},
	}
end

local function source_insert_menu(ctx)
	return {
		{
			label = " Paste",
			action = "<C-r>+",
			enabled = vim.bo[ctx.buf].modifiable and clipboard_text() ~= "",
		},
		separator("insert"),
		{
			label = "󰒆 Select All",
			action = "<Esc>ggVG",
		},
	}
end

local function explorer_normal_menu(ctx)
	local item = ctx.item
	local has_item = type(item) == "table" and type(item.file) == "string" and item.file ~= ""
	local is_directory = has_item and vim.fn.isdirectory(item.file) == 1
	local is_file = has_item and not is_directory
	local has_selection = ctx.selected_count > 0
	local selection_suffix = has_selection and string.format(" (%d Selected)", ctx.selected_count) or ""

	return {
		{
			label = is_directory and "󰉋 Open / Collapse Directory" or "󰈔 Open",
			action = lua_action("explorer_open"),
			enabled = has_item,
		},
		{
			label = "󰤼 Open in Horizontal Split",
			action = lua_action("explorer_open_split"),
			visible = is_file,
		},
		{
			label = "󰤻 Open in Vertical Split",
			action = lua_action("explorer_open_vsplit"),
			visible = is_file,
		},

		separator("explorer-edit"),

		{
			label = "󰝒 New File or Directory",
			action = lua_action("explorer_add"),
		},
		{
			label = "󰑕 Rename",
			action = lua_action("explorer_rename"),
			enabled = has_item and not has_selection,
		},
		{
			label = "󰆏 Copy" .. selection_suffix,
			action = lua_action("explorer_copy"),
			enabled = has_item or has_selection,
		},
		{
			label = "󰆴 Delete / Trash" .. selection_suffix,
			action = lua_action("explorer_delete"),
			enabled = has_item or has_selection,
		},

		separator("explorer-path"),

		{
			label = "󰅍 Copy Relative Path",
			action = lua_action("explorer_copy_relative_path"),
			enabled = has_item,
		},
		{
			label = "󰅍 Copy Absolute Path",
			action = lua_action("explorer_copy_absolute_path"),
			enabled = has_item,
		},
		{
			label = "󰆍 Open Terminal Here",
			action = lua_action("explorer_terminal_here"),
			enabled = has_item,
		},

		separator("explorer-view"),

		{
			label = "󰑐 Refresh Explorer",
			action = lua_action("explorer_refresh"),
		},
	}
end

local function picker_normal_menu(ctx)
	local has_item = ctx.item ~= nil

	return {
		{
			label = "󰈔 Open Selected",
			action = lua_action("picker_open"),
			enabled = has_item,
		},
		{
			label = "󰤼 Open in Horizontal Split",
			action = lua_action("picker_open_split"),
			enabled = has_item,
		},
		{
			label = "󰤻 Open in Vertical Split",
			action = lua_action("picker_open_vsplit"),
			enabled = has_item,
		},
		separator("picker"),
		{
			label = "󰅖 Close Picker",
			action = lua_action("picker_close"),
		},
	}
end

local function terminal_normal_menu()
	return {
		{
			label = " Paste",
			action = lua_action("terminal_paste"),
			enabled = clipboard_text() ~= "",
		},
		separator("terminal"),
		{
			label = "󰅖 Hide Terminal",
			action = lua_action("terminal_hide"),
		},
	}
end

local function terminal_visual_menu()
	return {
		{
			label = " Copy",
			action = '"+y',
		},
		separator("terminal-selection"),
		{
			label = "󰅖 Hide Terminal",
			action = lua_action("terminal_hide"),
		},
	}
end

local function special_normal_menu()
	return {
		{
			label = "󰒆 Select All",
			action = "ggVG",
		},
	}
end

local function special_visual_menu()
	return {
		{
			label = " Copy",
			action = '"+y',
		},
		{
			label = "󰒆 Select All",
			action = "gg0oG$",
		},
	}
end

local function menu_for(mode, ctx)
	if ctx.kind == "terminal" then
		if mode == "v" then
			return terminal_visual_menu()
		end

		if mode == "n" or mode == "tl" then
			return terminal_normal_menu()
		end
	end

	if ctx.kind == "explorer" and mode == "n" then
		return explorer_normal_menu(ctx)
	end

	if ctx.kind == "picker" and mode == "n" then
		return picker_normal_menu(ctx)
	end

	if ctx.kind == "source" then
		if mode == "n" then
			return source_normal_menu(ctx)
		elseif mode == "v" then
			return source_visual_menu(ctx)
		elseif mode == "i" then
			return source_insert_menu(ctx)
		end
	end

	if mode == "v" then
		return special_visual_menu()
	elseif mode == "n" then
		return special_normal_menu()
	elseif mode == "i" then
		return {
			{
				label = " Paste",
				action = "<C-r>+",
				enabled = clipboard_text() ~= "",
			},
		}
	end

	return {}
end

-- ─────────────────────────────────────────────────────────────
-- Popup Lifecycle
-- ─────────────────────────────────────────────────────────────

-- This module intentionally owns the PopUp menu tree.
-- Neovim's built-in popup-menu autocmd must be removed so that it cannot
-- re-enable or reconfigure the default right-click entries after our router.
pcall(vim.cmd, "silent! aunmenu PopUp")
pcall(vim.cmd, "silent! tlunmenu PopUp")
-- Neovim documents `autocmd! nvim.popupmenu` as the supported way to disable
-- the built-in context-menu updater.  Do not delete Neovim's augroup object.
pcall(vim.cmd, "silent! autocmd! nvim.popupmenu")

local group = vim.api.nvim_create_augroup("DemirContextMenu", {
	clear = true,
})

vim.api.nvim_create_autocmd("MenuPopup", {
	group = group,
	pattern = "*",

	callback = function(args)
		local mode = args.match

		if not menu_modes[mode] then
			return
		end

		local ok, err = xpcall(function()
			local ctx = detect_context()
			render_menu(mode, menu_for(mode, ctx))
		end, debug.traceback)

		if not ok then
			clear_popup(mode)
			report_internal_error("Context-menu rebuild failed", err)
		end
	end,
})

return M
