local M = {}

local trouble = require("trouble")
local deep_analysis = require("demir.analysis.clang_tidy")

local diagnostic = vim.diagnostic
local severity = diagnostic.severity

local ns = vim.api.nvim_create_namespace("DemirProblemsCenter")

local ROOT_MARKERS = {
	git = ".git",

	cmake_presets = {
		"CMakePresets.json",
		"CMakeUserPresets.json",
	},

	cmake = "CMakeLists.txt",
}

local REFRESH_DEBOUNCE_MS = 60

local MIN_COLUMNS = 84
local MIN_LINES = 24

local MAX_RENDERED_ENTRIES = 2000
local MAX_PREVIEW_FILE_BYTES = 8 * 1024 * 1024
local MAX_PREVIEW_NOTES = 200

local ANALYSIS_SUBSCRIPTION_KEY = "demir_problems_analysis_subscription"

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local state = {
	open = false,
	closing = false,
	generation = 0,
	refresh_serial = 0,

	filter = "all",
	query = "",

	root = nil,
	main_win = nil,
	main_tab = nil,

	entries = {},
	all_entries = {},
	line_map = {},

	preview_file = nil,
	preview_filetype = nil,
	preview_identity = nil,
	preview_lines = nil,

	deep_status = nil,
	deep_same_project = false,
	deep_visible = false,
	deep_visible_count = 0,

	rendered_entries = 0,
	truncated_entries = 0,

	bufs = {},
	wins = {},

	augroup = nil,
}

-- ─────────────────────────────────────────────────────────────
-- Basic Helpers
-- ─────────────────────────────────────────────────────────────

local function valid_win(win)
	return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
	return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function loaded_buf(buf)
	return valid_buf(buf) and vim.api.nvim_buf_is_loaded(buf)
end

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, {
		title = "Problems Center",
	})
end

local function normalize_path(path)
	if type(path) ~= "string" or path == "" then
		return ""
	end

	return vim.fs.normalize(path)
end

local function canonical_path(path)
	path = normalize_path(path)

	if path == "" then
		return ""
	end

	local real = vim.uv.fs_realpath(path)

	return normalize_path(real or path)
end

local function normal_file_buffer(buf)
	if type(buf) ~= "number" or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
		return false
	end

	if vim.bo[buf].buftype ~= "" then
		return false
	end

	return vim.api.nvim_buf_get_name(buf) ~= ""
end

local function source_context()
	local current_win = vim.api.nvim_get_current_win()
	local current_buf = vim.api.nvim_get_current_buf()

	if normal_file_buffer(current_buf) then
		return current_buf, current_win
	end

	local alternate = vim.fn.bufnr("#")

	if alternate >= 0 and normal_file_buffer(alternate) then
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if valid_win(win) and vim.api.nvim_win_get_buf(win) == alternate then
				return alternate, win
			end
		end

		return alternate, nil
	end

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if valid_win(win) then
			local buf = vim.api.nvim_win_get_buf(win)

			if normal_file_buffer(buf) then
				return buf, win
			end
		end
	end

	return nil, nil
end

local function root_from_source(source)
	local git = vim.fs.root(source, ROOT_MARKERS.git)

	if git then
		return canonical_path(git)
	end

	local presets = vim.fs.root(source, ROOT_MARKERS.cmake_presets)

	if presets then
		return canonical_path(presets)
	end

	local cmake = vim.fs.root(source, ROOT_MARKERS.cmake)

	if cmake then
		return canonical_path(cmake)
	end

	return canonical_path(vim.fn.getcwd())
end

local function project_root()
	local buf = source_context()

	if buf then
		return root_from_source(buf)
	end

	return root_from_source(vim.fn.getcwd())
end

local function same_project(a, b)
	a = canonical_path(a)
	b = canonical_path(b)

	return a ~= "" and b ~= "" and a == b
end

local function inside_project(file)
	file = canonical_path(file)

	if file == "" or not state.root then
		return false
	end

	return file == state.root or vim.fs.relpath(state.root, file) ~= nil
end

local function relative_file(file)
	file = canonical_path(file)

	if file == "" or not state.root then
		return file
	end

	local relative = vim.fs.relpath(state.root, file)

	if relative then
		return relative
	end

	return vim.fn.fnamemodify(file, ":~")
end

local function one_line(text_value)
	local value = tostring(text_value or ""):gsub("\r", " "):gsub("\n", " "):gsub("%s+", " ")

	return vim.trim(value)
end

local function truncate_display(value, max_width)
	value = tostring(value or "")

	if max_width <= 0 then
		return ""
	end

	if vim.fn.strdisplaywidth(value) <= max_width then
		return value
	end

	local ellipsis = "…"
	local target = math.max(0, max_width - vim.fn.strdisplaywidth(ellipsis))

	local low = 0
	local high = vim.fn.strchars(value)

	while low < high do
		local mid = math.floor((low + high + 1) / 2)
		local part = vim.fn.strcharpart(value, 0, mid)

		if vim.fn.strdisplaywidth(part) <= target then
			low = mid
		else
			high = mid - 1
		end
	end

	return vim.fn.strcharpart(value, 0, low) .. ellipsis
end

local function file_signature(path)
	local stat = path ~= "" and vim.uv.fs_stat(path) or nil

	if not stat or stat.type ~= "file" then
		return nil
	end

	local mtime = stat.mtime or {}

	return table.concat({
		tostring(stat.size or 0),
		tostring(mtime.sec or 0),
		tostring(mtime.nsec or 0),
	}, ":")
end

local function entry_key(entry)
	if not entry then
		return nil
	end

	return table.concat({
		entry.file or "",
		tostring(entry.lnum or -1),
		tostring(entry.col or -1),
		entry.code or "",
		entry.message or "",
	}, "\30")
end

local function is_clang_diagnostic(item)
	local source = tostring(item.source or ""):lower()

	return source:find("clang", 1, true) ~= nil
end

local function diagnostic_icon(level)
	if level == severity.ERROR then
		return "󰅚"
	elseif level == severity.WARN then
		return "󰀪"
	elseif level == severity.INFO then
		return "󰋽"
	end

	return "󰌶"
end

local function diagnostic_hl(level)
	if level == severity.ERROR then
		return "DiagnosticError"
	elseif level == severity.WARN then
		return "DiagnosticWarn"
	elseif level == severity.INFO then
		return "DiagnosticInfo"
	end

	return "DiagnosticHint"
end

-- ─────────────────────────────────────────────────────────────
-- Scratch Buffers
-- ─────────────────────────────────────────────────────────────

local function create_buffer(name)
	local buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_name(buf, name)

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false

	return buf
end

local function set_buffer_lines(buf, lines)
	if not loaded_buf(buf) then
		return false
	end

	local ok, err = pcall(function()
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end)

	if valid_buf(buf) then
		vim.bo[buf].modifiable = false
	end

	if not ok then
		notify("Failed to update an internal Problems Center buffer:\n" .. tostring(err), vim.log.levels.ERROR)
		return false
	end

	return true
end

-- ─────────────────────────────────────────────────────────────
-- Diagnostic Collection
-- ─────────────────────────────────────────────────────────────

local function collect_diagnostics()
	local entries = {}
	local seen = {}

	local analysis = deep_analysis.status()
	local analysis_root = canonical_path(analysis.root)

	state.deep_status = analysis
	state.deep_same_project = same_project(analysis_root, state.root)
	state.deep_visible = state.deep_same_project and analysis.stale ~= true
	state.deep_visible_count = 0

	local function add_entry(entry)
		local key = table.concat({
			entry.file or "",
			tostring(entry.lnum or -1),
			tostring(entry.col or -1),
			entry.code or "",
			entry.message or "",
		}, "\30")

		local existing = seen[key]

		if existing then
			-- A live LSP diagnostic is preferred because it can carry code
			-- actions. Deep Static Analyzer notes still enrich the live item.
			if existing.origin == "live" and type(entry.notes) == "table" and #entry.notes > 0 then
				existing.notes = existing.notes or {}

				local note_seen = {}

				for _, note in ipairs(existing.notes) do
					note_seen[table.concat({
						note.file or "",
						tostring(note.lnum or -1),
						tostring(note.col or -1),
						note.message or "",
					}, "\30")] =
						true
				end

				for _, note in ipairs(entry.notes) do
					local note_id = table.concat({
						note.file or "",
						tostring(note.lnum or -1),
						tostring(note.col or -1),
						note.message or "",
					}, "\30")

					if not note_seen[note_id] then
						note_seen[note_id] = true
						table.insert(existing.notes, note)
					end
				end
			end

			return
		end

		seen[key] = entry
		table.insert(entries, entry)
	end

	-- Live diagnostics currently known to Neovim. The Problems Center is
	-- intentionally C/C++-centric, so only clang-family diagnostics are
	-- admitted here.
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if valid_buf(buf) then
			local file = canonical_path(vim.api.nvim_buf_get_name(buf))

			if inside_project(file) then
				local items = diagnostic.get(buf, {
					severity = {
						min = severity.WARN,
					},
				})

				for _, item in ipairs(items) do
					if is_clang_diagnostic(item) then
						add_entry({
							buf = buf,
							file = file,

							lnum = item.lnum,
							col = item.col,
							end_lnum = item.end_lnum,
							end_col = item.end_col,

							message = one_line(item.message),
							source = item.source or "clang",
							code = item.code ~= nil and tostring(item.code) or "",
							severity = item.severity,

							diagnostic = item,
							origin = "live",
							notes = {},
						})
					end
				end
			end
		end
	end

	-- Deep results are intentionally hidden when stale or when they belong to a
	-- different project. Presenting old project-wide findings as current errors
	-- would be more dangerous than temporarily hiding them.
	if state.deep_visible then
		for _, item in ipairs(deep_analysis.peek_results()) do
			local file = canonical_path(item.file)

			if inside_project(file) then
				state.deep_visible_count = state.deep_visible_count + 1

				add_entry({
					buf = nil,
					file = file,

					lnum = item.lnum,
					col = item.col,

					message = one_line(item.message),
					source = item.source or "clang-tidy · deep",
					code = item.code or "",
					severity = item.severity or severity.WARN,

					diagnostic = nil,
					origin = "deep",

					-- Trusted read-only data from the analyzer. Do not deep-copy
					-- thousands of Static Analyzer path notes on every refresh.
					notes = item.notes or {},
				})
			end
		end
	end

	table.sort(entries, function(a, b)
		if a.severity ~= b.severity then
			return a.severity < b.severity
		end

		if a.file ~= b.file then
			return a.file < b.file
		end

		if a.lnum ~= b.lnum then
			return a.lnum < b.lnum
		end

		if a.col ~= b.col then
			return a.col < b.col
		end

		if a.code ~= b.code then
			return a.code < b.code
		end

		return a.message < b.message
	end)

	state.all_entries = entries
end

local function apply_filters()
	local filtered = {}
	local query = vim.trim(state.query):lower()

	for _, entry in ipairs(state.all_entries) do
		local severity_ok = state.filter == "all"
			or (state.filter == "error" and entry.severity == severity.ERROR)
			or (state.filter == "warn" and entry.severity == severity.WARN)

		local query_ok = true

		if query ~= "" then
			local note_text = {}

			for _, note in ipairs(entry.notes or {}) do
				table.insert(note_text, note.message or "")
			end

			local haystack = table
				.concat({
					relative_file(entry.file),
					entry.message,
					entry.source,
					entry.code,
					table.concat(note_text, " "),
				}, " ")
				:lower()

			query_ok = haystack:find(query, 1, true) ~= nil
		end

		if severity_ok and query_ok then
			table.insert(filtered, entry)
		end
	end

	state.entries = filtered

	state.rendered_entries = math.min(#state.entries, MAX_RENDERED_ENTRIES)

	state.truncated_entries = math.max(0, #state.entries - state.rendered_entries)
end

local function counts()
	local errors = 0
	local warnings = 0

	for _, entry in ipairs(state.all_entries) do
		if entry.severity == severity.ERROR then
			errors = errors + 1
		elseif entry.severity == severity.WARN then
			warnings = warnings + 1
		end
	end

	return errors, warnings
end

-- ─────────────────────────────────────────────────────────────
-- Geometry
-- ─────────────────────────────────────────────────────────────

local function geometry()
	local columns = vim.o.columns
	local usable_lines = vim.o.lines - vim.o.cmdheight

	if columns < MIN_COLUMNS or usable_lines < MIN_LINES then
		return nil
	end

	local outer_width = math.min(columns - 4, math.max(MIN_COLUMNS - 4, math.floor(columns * 0.92)))

	local outer_height = math.min(usable_lines - 4, math.max(MIN_LINES - 4, math.floor(usable_lines * 0.84)))

	local header_height = 2
	local footer_height = 1
	local body_height = outer_height - 9

	if body_height < 10 then
		return nil
	end

	local left_width = math.floor((outer_width - 5) * 0.42)
	local right_width = outer_width - left_width - 5

	if left_width < 24 or right_width < 32 then
		return nil
	end

	local col = math.floor((columns - outer_width) / 2)
	local row = math.floor((usable_lines - outer_height) / 2)

	return {
		row = row,
		col = col,

		outer_width = outer_width,
		outer_height = outer_height,

		header_height = header_height,
		footer_height = footer_height,
		body_height = body_height,

		left_width = left_width,
		right_width = right_width,

		body_row = row + header_height + 2,
		right_col = col + left_width + 3,
		footer_row = row + header_height + body_height + 4,
	}
end

local function float_config(row, col, width, height, title)
	return {
		relative = "editor",

		row = row,
		col = col,

		width = width,
		height = height,

		style = "minimal",
		border = "rounded",

		title = title,
		title_pos = "center",

		zindex = 60,
	}
end

-- ─────────────────────────────────────────────────────────────
-- Highlights
-- ─────────────────────────────────────────────────────────────

local function highlight_text(buf, line, text, needle, hl)
	if not loaded_buf(buf) or type(text) ~= "string" or type(needle) ~= "string" then
		return
	end

	local start_col, end_col = text:find(needle, 1, true)

	if not start_col then
		return
	end

	pcall(vim.api.nvim_buf_set_extmark, buf, ns, line, start_col - 1, {
		end_col = end_col,
		hl_group = hl,
	})
end

-- ─────────────────────────────────────────────────────────────
-- Header
-- ─────────────────────────────────────────────────────────────

local function deep_status_label()
	local analysis = state.deep_status or deep_analysis.status()
	local matching_count = state.deep_visible_count or 0

	if analysis.running then
		if not state.deep_same_project then
			return "deep busy elsewhere", "DiagnosticWarn"
		end

		local phase = analysis.phase or "running"

		if phase == "running" then
			return string.format(
				"deep %d/%d · %d pending",
				analysis.completed or 0,
				analysis.total or 0,
				analysis.current_issues or 0
			),
				"DiagnosticWarn"
		end

		local labels = {
			preparing = "deep preparing",
			awaiting_save = "deep awaiting save",
			discovering_database = "deep finding DB",
			selecting_database = "deep select DB",
			loading_database = "deep loading DB",
			verifying = "deep verifying",
		}

		return labels[phase] or ("deep " .. tostring(phase)), "DiagnosticWarn"
	end

	if not state.deep_same_project then
		return "deep idle", "Comment"
	end

	if analysis.stale and (analysis.committed_issues or 0) > 0 then
		return string.format("deep stale %d · hidden", analysis.committed_issues), "DiagnosticWarn"
	end

	local attempt = analysis.last_attempt

	if attempt and attempt.ok == false then
		local cancelled = attempt.reason == "Analysis cancelled."

		return string.format(cancelled and "deep cancelled · %d kept" or "deep failed · %d kept", matching_count),
			"DiagnosticWarn"
	end

	if attempt and attempt.ok == true then
		if matching_count == 0 then
			return "deep clean", "DiagnosticOk"
		end

		return string.format("deep %d", matching_count), "DiagnosticInfo"
	end

	if matching_count > 0 then
		return string.format("deep %d", matching_count), "DiagnosticInfo"
	end

	return "deep idle", "Comment"
end

local function render_header()
	if not loaded_buf(state.bufs.header) then
		return
	end

	local errors, warnings = counts()
	local root_name = vim.fn.fnamemodify(state.root, ":t")

	if root_name == "" then
		root_name = state.root
	end

	local deep_text, deep_hl = deep_status_label()

	local width = valid_win(state.wins.header) and vim.api.nvim_win_get_width(state.wins.header) or 80

	local left = "  󰒡  PROJECT PROBLEMS     󰉋 "
	local deep_prefix = "     󰖩 clangd · "

	local fixed_width = vim.fn.strdisplaywidth(left) + vim.fn.strdisplaywidth(deep_prefix)

	local variable_width = math.max(16, width - fixed_width - 1)

	local deep_budget = math.max(10, math.min(28, math.floor(variable_width * 0.60)))

	local root_budget = math.max(6, variable_width - deep_budget)

	local deep_display = truncate_display(deep_text, deep_budget)

	root_name = truncate_display(root_name, root_budget)

	local first = left .. root_name .. deep_prefix .. deep_display

	local base_second = string.format(
		"  [A] ALL %d     [E] ERRORS %d     [W] WARNINGS %d     [/] SEARCH",
		errors + warnings,
		errors,
		warnings
	)

	local status_suffix = ""

	if state.truncated_entries > 0 then
		status_suffix = string.format("     SHOWING %d/%d", state.rendered_entries, #state.entries)
	end

	local query_suffix = ""

	if state.query ~= "" then
		query_suffix = "     Query: " .. state.query
	end

	local second = truncate_display(base_second .. status_suffix .. query_suffix, width)

	if not set_buffer_lines(state.bufs.header, {
		first,
		second,
	}) then
		return
	end

	pcall(vim.api.nvim_buf_clear_namespace, state.bufs.header, ns, 0, -1)

	highlight_text(state.bufs.header, 0, first, "PROJECT PROBLEMS", "Title")

	highlight_text(state.bufs.header, 0, first, "clangd", "DiagnosticInfo")

	highlight_text(state.bufs.header, 0, first, deep_display, deep_hl)

	highlight_text(
		state.bufs.header,
		1,
		second,
		string.format("[A] ALL %d", errors + warnings),
		state.filter == "all" and "Visual" or "Normal"
	)

	highlight_text(
		state.bufs.header,
		1,
		second,
		string.format("[E] ERRORS %d", errors),
		state.filter == "error" and "Visual" or "DiagnosticError"
	)

	highlight_text(
		state.bufs.header,
		1,
		second,
		string.format("[W] WARNINGS %d", warnings),
		state.filter == "warn" and "Visual" or "DiagnosticWarn"
	)
end

-- ─────────────────────────────────────────────────────────────
-- Selection
-- ─────────────────────────────────────────────────────────────

local function selected_entry()
	if not valid_win(state.wins.list) then
		return nil
	end

	local cursor_line = vim.api.nvim_win_get_cursor(state.wins.list)[1]

	if state.line_map[cursor_line] then
		return state.line_map[cursor_line]
	end

	local line_count = loaded_buf(state.bufs.list) and vim.api.nvim_buf_line_count(state.bufs.list) or 0

	for offset = 1, line_count do
		local down = cursor_line + offset

		if down <= line_count and state.line_map[down] then
			return state.line_map[down]
		end

		local up = cursor_line - offset

		if up >= 1 and state.line_map[up] then
			return state.line_map[up]
		end
	end

	return nil
end

-- ─────────────────────────────────────────────────────────────
-- List
-- ─────────────────────────────────────────────────────────────

local function render_list(preferred_key)
	if not loaded_buf(state.bufs.list) then
		return
	end

	state.line_map = {}
	state.rendered_entries = 0
	state.truncated_entries = 0

	local lines = {}
	local highlights = {}
	local key_to_line = {}

	if #state.entries == 0 then
		lines = {
			"",
			"   󰄬  No matching project problems",
			"",
			"   A  Show all",
			"   E  Errors",
			"   W  Warnings",
			"   /  Search",
		}

		local analysis = state.deep_status or deep_analysis.status()

		if state.deep_same_project and analysis.stale and (analysis.committed_issues or 0) > 0 then
			table.insert(lines, "")
			table.insert(lines, "   Deep-analysis results are stale and hidden. Press D to rescan.")
		elseif analysis.running and state.deep_same_project then
			table.insert(lines, "")
			table.insert(lines, "   Deep scan is running; new findings commit atomically when complete.")
		end

		set_buffer_lines(state.bufs.list, lines)

		pcall(vim.api.nvim_buf_clear_namespace, state.bufs.list, ns, 0, -1)

		if valid_win(state.wins.list) then
			pcall(vim.api.nvim_win_set_cursor, state.wins.list, { 1, 0 })
		end

		return
	end

	local current_file = nil
	local limit = math.min(#state.entries, MAX_RENDERED_ENTRIES)

	for index = 1, limit do
		local entry = state.entries[index]
		local file = relative_file(entry.file)

		if file ~= current_file then
			current_file = file

			if #lines > 0 then
				table.insert(lines, "")
			end

			local file_line = "  ▾ " .. file

			table.insert(lines, file_line)

			table.insert(highlights, {
				line = #lines - 1,
				text = file_line,
				needle = file,
				hl = "Directory",
			})
		end

		local icon = diagnostic_icon(entry.severity)

		local message_line = string.format("    %s  %s", icon, entry.message)

		table.insert(lines, message_line)

		state.line_map[#lines] = entry
		key_to_line[entry_key(entry)] = #lines

		table.insert(highlights, {
			line = #lines - 1,
			text = message_line,
			needle = icon,
			hl = diagnostic_hl(entry.severity),
		})

		local detail = string.format(
			"       Ln %d:%d  ·  %s%s",
			entry.lnum + 1,
			entry.col + 1,
			entry.source,
			entry.code ~= "" and ("  ·  " .. entry.code) or ""
		)

		table.insert(lines, detail)
		state.line_map[#lines] = entry

		table.insert(highlights, {
			line = #lines - 1,
			text = detail,
			needle = detail,
			hl = "Comment",
		})
	end

	state.rendered_entries = limit
	state.truncated_entries = math.max(0, #state.entries - limit)

	if state.truncated_entries > 0 then
		table.insert(lines, "")
		table.insert(
			lines,
			string.format(
				"  … %d additional problems are hidden. Use / Search to narrow the result set.",
				state.truncated_entries
			)
		)

		table.insert(highlights, {
			line = #lines - 1,
			text = lines[#lines],
			needle = lines[#lines],
			hl = "Comment",
		})
	end

	if not set_buffer_lines(state.bufs.list, lines) then
		return
	end

	pcall(vim.api.nvim_buf_clear_namespace, state.bufs.list, ns, 0, -1)

	for _, item in ipairs(highlights) do
		highlight_text(state.bufs.list, item.line, item.text, item.needle, item.hl)
	end

	if valid_win(state.wins.list) then
		local target = preferred_key and key_to_line[preferred_key] or nil

		if not target then
			for line = 1, #lines do
				if state.line_map[line] then
					target = line
					break
				end
			end
		end

		if target then
			pcall(vim.api.nvim_win_set_cursor, state.wins.list, { target, 0 })
		end
	end
end

-- ─────────────────────────────────────────────────────────────
-- Preview
-- ─────────────────────────────────────────────────────────────

local function find_loaded_source_buffer(file, preferred)
	file = canonical_path(file)

	if loaded_buf(preferred) and canonical_path(vim.api.nvim_buf_get_name(preferred)) == file then
		return preferred
	end

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if loaded_buf(buf) and vim.bo[buf].buftype == "" and canonical_path(vim.api.nvim_buf_get_name(buf)) == file then
			return buf
		end
	end

	return nil
end

local function preview_source(entry)
	local file = canonical_path(entry.file)
	local source_buf = find_loaded_source_buffer(file, entry.buf)

	if source_buf then
		local identity = table.concat({
			"buffer",
			tostring(source_buf),
			tostring(vim.api.nvim_buf_get_changedtick(source_buf)),
		}, ":")

		if state.preview_identity == identity and state.preview_lines then
			return state.preview_lines, state.preview_filetype or "", identity
		end

		local lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)

		local ft = vim.bo[source_buf].filetype

		if ft == "" then
			ft = vim.filetype.match({
				filename = file,
			}) or ""
		end

		return lines, ft, identity
	end

	local stat = vim.uv.fs_stat(file)

	if not stat or stat.type ~= "file" then
		return nil, nil, nil, "The source file is not currently available for preview."
	end

	if stat.size and stat.size > MAX_PREVIEW_FILE_BYTES then
		return nil,
			nil,
			nil,
			string.format(
				"Source preview skipped because the file is larger than %d MiB.",
				math.floor(MAX_PREVIEW_FILE_BYTES / 1024 / 1024)
			)
	end

	local identity = "file:" .. file .. ":" .. (file_signature(file) or "unknown")

	if state.preview_identity == identity and state.preview_lines then
		return state.preview_lines, state.preview_filetype or "", identity
	end

	local ok, lines = pcall(vim.fn.readfile, file)

	if not ok or type(lines) ~= "table" then
		return nil, nil, nil, "The source file could not be read for preview."
	end

	local ft = vim.filetype.match({
		filename = file,
	}) or ""

	return lines, ft, identity
end

local function set_preview_title(title)
	if valid_win(state.wins.preview) then
		pcall(vim.api.nvim_win_set_config, state.wins.preview, {
			title = title,
		})
	end
end

local function reset_preview_language()
	if loaded_buf(state.bufs.preview) then
		pcall(vim.treesitter.stop, state.bufs.preview)

		vim.bo[state.bufs.preview].filetype = ""
	end

	state.preview_file = nil
	state.preview_filetype = nil
	state.preview_identity = nil
	state.preview_lines = nil
end

local function preview_placeholder(lines, title)
	reset_preview_language()

	set_buffer_lines(state.bufs.preview, lines)

	set_preview_title(title)
end

local function render_preview()
	if not state.open or not loaded_buf(state.bufs.preview) then
		return
	end

	local entry = selected_entry()

	pcall(vim.api.nvim_buf_clear_namespace, state.bufs.preview, ns, 0, -1)

	if not entry then
		preview_placeholder({
			"",
			"  Select a problem to preview it.",
		}, " 󰈙  Source Preview ")

		return
	end

	local source_lines, ft, identity, preview_error = preview_source(entry)

	if not source_lines then
		preview_placeholder({
			"",
			"  " .. (preview_error or "Source preview is unavailable."),
			"",
			"  " .. entry.file,
		}, " 󰈙  Source Unavailable ")

		return
	end

	if #source_lines == 0 then
		source_lines = { "" }
	end

	local content_changed = identity ~= state.preview_identity

	if content_changed then
		if not set_buffer_lines(state.bufs.preview, source_lines) then
			return
		end

		state.preview_identity = identity
		state.preview_lines = source_lines
	end

	if state.preview_filetype ~= ft then
		pcall(vim.treesitter.stop, state.bufs.preview)

		vim.bo[state.bufs.preview].filetype = ft

		if ft ~= "" then
			pcall(vim.treesitter.start, state.bufs.preview, ft)
		end

		state.preview_filetype = ft
	end

	state.preview_file = canonical_path(entry.file)

	local line = math.min(math.max(0, entry.lnum), #source_lines - 1)

	local line_text = source_lines[line + 1] or ""

	local col = math.min(math.max(0, entry.col), #line_text)

	local virt_lines = {}
	local notes = entry.notes or {}
	local note_limit = math.min(#notes, MAX_PREVIEW_NOTES)

	for index = 1, note_limit do
		local note = notes[index]
		local location = ""

		if note.file and note.file ~= "" then
			location =
				string.format("%s:%d:%d · ", relative_file(note.file), (note.lnum or 0) + 1, (note.col or 0) + 1)
		end

		table.insert(virt_lines, {
			{
				"   ↳ " .. location .. one_line(note.message),
				"Comment",
			},
		})
	end

	if #notes > note_limit then
		table.insert(virt_lines, {
			{
				string.format("   … %d additional analyzer notes hidden", #notes - note_limit),
				"Comment",
			},
		})
	end

	pcall(vim.api.nvim_buf_set_extmark, state.bufs.preview, ns, line, col, {
		line_hl_group = "CursorLine",

		virt_text = {
			{
				" " .. diagnostic_icon(entry.severity) .. " " .. entry.message,
				diagnostic_hl(entry.severity),
			},
		},

		virt_text_pos = "eol",

		virt_lines = #virt_lines > 0 and virt_lines or nil,

		virt_lines_overflow = "wrap",
	})

	if valid_win(state.wins.preview) then
		pcall(vim.api.nvim_win_set_cursor, state.wins.preview, {
			line + 1,
			col,
		})

		pcall(vim.api.nvim_win_call, state.wins.preview, function()
			vim.cmd("normal! zz")
		end)

		set_preview_title(
			" 󰈙  "
				.. truncate_display(
					relative_file(entry.file),
					math.max(12, vim.api.nvim_win_get_width(state.wins.preview) - 8)
				)
				.. " "
		)
	end
end

-- ─────────────────────────────────────────────────────────────
-- Footer
-- ─────────────────────────────────────────────────────────────

local function deep_action_label()
	local analysis = state.deep_status or deep_analysis.status()

	if analysis.running then
		if state.deep_same_project then
			return "D Cancel", "DiagnosticWarn"
		end

		return "D Busy", "DiagnosticWarn"
	end

	return "D Deep", "DiagnosticInfo"
end

local function render_footer()
	local deep_action, deep_hl = deep_action_label()

	local width = valid_win(state.wins.footer) and vim.api.nvim_win_get_width(state.wins.footer) or 80

	local verbose = string.format(
		"  A All   E Error   W Warn   / Search   %s   F Fix   ↵ Open   r Refresh   q Close  ",
		deep_action
	)

	local compact =
		string.format(" A All  E Err  W Warn  / Find  %s  F Fix  ↵ Open  r Refresh  q Close ", deep_action)

	local text_value = vim.fn.strdisplaywidth(verbose) <= width and verbose or compact

	text_value = truncate_display(text_value, width)

	if not set_buffer_lines(state.bufs.footer, { text_value }) then
		return
	end

	pcall(vim.api.nvim_buf_clear_namespace, state.bufs.footer, ns, 0, -1)

	highlight_text(
		state.bufs.footer,
		0,
		text_value,
		text_value:find("E Error", 1, true) and "E Error" or "E Err",
		"DiagnosticError"
	)

	highlight_text(state.bufs.footer, 0, text_value, "W Warn", "DiagnosticWarn")

	highlight_text(state.bufs.footer, 0, text_value, deep_action, deep_hl)

	highlight_text(state.bufs.footer, 0, text_value, "F Fix", "DiagnosticInfo")
end

-- ─────────────────────────────────────────────────────────────
-- Refresh
-- ─────────────────────────────────────────────────────────────

local function refresh()
	if not state.open then
		return
	end

	local selected = selected_entry()
	local preferred_key = entry_key(selected)
	local generation = state.generation

	collect_diagnostics()
	apply_filters()

	if not state.open or generation ~= state.generation then
		return
	end

	render_header()
	render_list(preferred_key)
	render_footer()

	vim.schedule(function()
		if state.open and generation == state.generation then
			render_preview()
		end
	end)
end

local function schedule_refresh(delay_ms)
	if not state.open then
		return
	end

	state.refresh_serial = state.refresh_serial + 1

	local serial = state.refresh_serial
	local generation = state.generation

	vim.defer_fn(function()
		if not state.open or generation ~= state.generation or serial ~= state.refresh_serial then
			return
		end

		refresh()
	end, delay_ms or REFRESH_DEBOUNCE_MS)
end

-- ─────────────────────────────────────────────────────────────
-- Filtering / Search
-- ─────────────────────────────────────────────────────────────

local function set_filter(filter)
	if not state.open then
		return
	end

	state.filter = filter
	refresh()

	if valid_win(state.wins.list) then
		pcall(vim.api.nvim_set_current_win, state.wins.list)
	end
end

local function search()
	if not state.open then
		return
	end

	local generation = state.generation

	vim.ui.input({
		prompt = " Search project problems: ",
		default = state.query,
	}, function(value)
		if not state.open or generation ~= state.generation or value == nil then
			return
		end

		state.query = vim.trim(value)
		refresh()

		if valid_win(state.wins.list) then
			pcall(vim.api.nvim_set_current_win, state.wins.list)
		end
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Cleanup / Close
-- ─────────────────────────────────────────────────────────────

local function reset_runtime_state()
	state.filter = "all"
	state.query = ""

	state.root = nil
	state.main_win = nil
	state.main_tab = nil

	state.entries = {}
	state.all_entries = {}
	state.line_map = {}

	state.preview_file = nil
	state.preview_filetype = nil
	state.preview_identity = nil
	state.preview_lines = nil

	state.deep_status = nil
	state.deep_same_project = false
	state.deep_visible = false
	state.deep_visible_count = 0

	state.rendered_entries = 0
	state.truncated_entries = 0

	state.bufs = {}
	state.wins = {}
	state.augroup = nil
end

local function close_center(opts)
	opts = opts or {}

	if not state.open and not state.closing then
		return
	end

	local restore_win = state.main_win
	local restore_tab = state.main_tab

	state.open = false
	state.closing = true
	state.generation = state.generation + 1
	state.refresh_serial = state.refresh_serial + 1

	if state.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
		state.augroup = nil
	end

	for _, win in pairs(state.wins) do
		if valid_win(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end

	for _, buf in pairs(state.bufs) do
		if valid_buf(buf) then
			pcall(vim.api.nvim_buf_delete, buf, {
				force = true,
			})
		end
	end

	reset_runtime_state()
	state.closing = false

	if opts.restore_focus == false then
		return
	end

	if valid_win(restore_win) then
		local ok, tab = pcall(vim.api.nvim_win_get_tabpage, restore_win)

		if ok and tab == restore_tab and tab == vim.api.nvim_get_current_tabpage() then
			pcall(vim.api.nvim_set_current_win, restore_win)
		end
	end
end

-- ─────────────────────────────────────────────────────────────
-- Open Selected Problem
-- ─────────────────────────────────────────────────────────────

local function open_selected()
	local entry = selected_entry()

	if not entry then
		return false
	end

	local file = canonical_path(entry.file)
	local line = entry.lnum
	local col = entry.col

	local target_win = state.main_win
	local target_tab = state.main_tab

	close_center({
		restore_focus = false,
	})

	if valid_win(target_win) then
		local ok, tab = pcall(vim.api.nvim_win_get_tabpage, target_win)

		if ok and tab == target_tab and vim.api.nvim_tabpage_is_valid(tab) then
			pcall(vim.api.nvim_set_current_tabpage, tab)

			pcall(vim.api.nvim_set_current_win, target_win)
		end
	elseif target_tab and vim.api.nvim_tabpage_is_valid(target_tab) then
		pcall(vim.api.nvim_set_current_tabpage, target_tab)
	end

	local ok, err = pcall(vim.api.nvim_cmd, {
		cmd = "edit",
		args = {
			file,
		},
	}, {})

	if not ok then
		notify("Failed to open the selected problem:\n" .. tostring(err), vim.log.levels.ERROR)

		return false
	end

	local current_buf = vim.api.nvim_get_current_buf()
	local line_count = vim.api.nvim_buf_line_count(current_buf)

	if line_count > 0 then
		local target_line = math.min(math.max(0, line), line_count - 1)

		local source_line = vim.api.nvim_buf_get_lines(current_buf, target_line, target_line + 1, false)[1] or ""

		local target_col = math.min(math.max(0, col), #source_line)

		pcall(vim.api.nvim_win_set_cursor, 0, {
			target_line + 1,
			target_col,
		})

		pcall(vim.cmd, "normal! zz")
	end

	return true
end

-- ─────────────────────────────────────────────────────────────
-- Quick Fix
-- ─────────────────────────────────────────────────────────────

local function quick_fix()
	local entry = selected_entry()

	if not entry then
		return
	end

	if entry.origin ~= "live" or not entry.diagnostic then
		notify(
			"This finding comes from the deep project analyzer and has no live LSP fix attached. Open it first, then use clangd code actions if the live analyzer reproduces the issue.",
			vim.log.levels.INFO
		)
		return
	end

	local diag = entry.diagnostic
	local lsp_diagnostics = nil

	if vim.lsp.diagnostic and type(vim.lsp.diagnostic.from) == "function" then
		local ok, converted = pcall(vim.lsp.diagnostic.from, {
			diag,
		})

		if ok and type(converted) == "table" and #converted > 0 then
			lsp_diagnostics = converted
		end
	end

	if not open_selected() then
		return
	end

	vim.schedule(function()
		local context = {
			only = {
				"quickfix",
			},
		}

		if lsp_diagnostics then
			context.diagnostics = lsp_diagnostics
		end

		vim.lsp.buf.code_action({
			context = context,
		})
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Mouse
-- ─────────────────────────────────────────────────────────────

local function mouse_select()
	if not state.open or not valid_win(state.wins.list) then
		return
	end

	local mouse = vim.fn.getmousepos()

	if mouse.winid ~= state.wins.list then
		return
	end

	pcall(vim.api.nvim_win_set_cursor, state.wins.list, {
		mouse.line,
		math.max(0, mouse.column - 1),
	})

	render_preview()
end

-- ─────────────────────────────────────────────────────────────
-- Resize
-- ─────────────────────────────────────────────────────────────

local function reposition()
	if not state.open then
		return
	end

	local g = geometry()

	if not g then
		close_center({
			restore_focus = false,
		})

		notify("Problems Center was closed because the current UI is too small.", vim.log.levels.WARN)

		return
	end

	if valid_win(state.wins.header) then
		pcall(
			vim.api.nvim_win_set_config,
			state.wins.header,
			float_config(g.row, g.col, g.outer_width - 2, g.header_height, " 󰒡  Problems Center ")
		)
	end

	if valid_win(state.wins.list) then
		pcall(
			vim.api.nvim_win_set_config,
			state.wins.list,
			float_config(g.body_row, g.col, g.left_width, g.body_height, " 󰖩  Project Findings ")
		)
	end

	if valid_win(state.wins.preview) then
		pcall(
			vim.api.nvim_win_set_config,
			state.wins.preview,
			float_config(g.body_row, g.right_col, g.right_width, g.body_height, " 󰈙  Source Preview ")
		)
	end

	if valid_win(state.wins.footer) then
		pcall(
			vim.api.nvim_win_set_config,
			state.wins.footer,
			float_config(g.footer_row, g.col, g.outer_width - 2, g.footer_height, " Actions ")
		)
	end
end

-- ─────────────────────────────────────────────────────────────
-- Keymaps
-- ─────────────────────────────────────────────────────────────

local function setup_center_keymaps()
	local opts = {
		buffer = state.bufs.list,
		silent = true,
		nowait = true,
	}

	vim.keymap.set("n", "q", function()
		close_center()
	end, opts)

	vim.keymap.set("n", "<Esc>", function()
		close_center()
	end, opts)

	vim.keymap.set("n", "A", function()
		set_filter("all")
	end, opts)

	vim.keymap.set("n", "E", function()
		set_filter("error")
	end, opts)

	vim.keymap.set("n", "W", function()
		set_filter("warn")
	end, opts)

	vim.keymap.set("n", "/", search, opts)

	vim.keymap.set("n", "D", function()
		local analysis = deep_analysis.status()
		local analysis_same_project = same_project(analysis.root, state.root)

		if analysis.running then
			if analysis_same_project then
				deep_analysis.cancel()
			else
				notify(
					"Deep analysis is busy in another project:\n"
						.. tostring(analysis.root or "unknown root")
						.. "\nUse :DemirCancelAnalysis if you intend to stop it.",
					vim.log.levels.WARN
				)
			end

			return
		end

		deep_analysis.run({
			root = state.root,
			prompt_save = true,
		})
	end, opts)

	vim.keymap.set("n", "r", refresh, opts)
	vim.keymap.set("n", "F", quick_fix, opts)
	vim.keymap.set("n", "<CR>", open_selected, opts)

	vim.keymap.set("n", "<LeftMouse>", mouse_select, opts)

	vim.keymap.set("n", "<2-LeftMouse>", function()
		mouse_select()
		open_selected()
	end, opts)
end

-- ─────────────────────────────────────────────────────────────
-- Runtime Events
-- ─────────────────────────────────────────────────────────────

local function buffer_inside_project(buf)
	if not valid_buf(buf) then
		return false
	end

	return inside_project(vim.api.nvim_buf_get_name(buf))
end

local function managed_window(win)
	for _, candidate in pairs(state.wins) do
		if candidate == win then
			return true
		end
	end

	return false
end

local function setup_runtime_events()
	state.augroup = vim.api.nvim_create_augroup("DemirProblemsCenterRuntime", {
		clear = true,
	})

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = state.augroup,
		buffer = state.bufs.list,

		callback = function()
			render_preview()
		end,
	})

	vim.api.nvim_create_autocmd("DiagnosticChanged", {
		group = state.augroup,

		callback = function(args)
			if state.open and buffer_inside_project(args.buf) then
				schedule_refresh(REFRESH_DEBOUNCE_MS)
			end
		end,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		group = state.augroup,

		callback = function()
			local generation = state.generation

			vim.schedule(function()
				if state.open and generation == state.generation then
					reposition()
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd("TabLeave", {
		group = state.augroup,

		callback = function()
			if state.open then
				close_center({
					restore_focus = false,
				})
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = state.augroup,
		pattern = "*",

		callback = function(args)
			if not state.open or state.closing then
				return
			end

			local closed = tonumber(args.match)

			if closed and managed_window(closed) then
				close_center({
					restore_focus = false,
				})
			end
		end,
	})
end

-- ─────────────────────────────────────────────────────────────
-- Window Options
-- ─────────────────────────────────────────────────────────────

local function configure_windows()
	for _, win in pairs(state.wins) do
		if valid_win(win) then
			vim.api.nvim_set_option_value("wrap", false, {
				win = win,
			})

			vim.api.nvim_set_option_value(
				"winhighlight",
				"Normal:NormalFloat," .. "FloatBorder:FloatBorder," .. "FloatTitle:Title," .. "CursorLine:Visual",
				{
					win = win,
				}
			)
		end
	end

	vim.api.nvim_set_option_value("cursorline", true, {
		win = state.wins.list,
	})

	vim.api.nvim_set_option_value("number", false, {
		win = state.wins.list,
	})

	vim.api.nvim_set_option_value("relativenumber", false, {
		win = state.wins.list,
	})

	vim.api.nvim_set_option_value("signcolumn", "no", {
		win = state.wins.list,
	})

	vim.api.nvim_set_option_value("wrap", false, {
		win = state.wins.list,
	})

	vim.api.nvim_set_option_value("number", true, {
		win = state.wins.preview,
	})

	vim.api.nvim_set_option_value("relativenumber", false, {
		win = state.wins.preview,
	})

	vim.api.nvim_set_option_value("signcolumn", "yes", {
		win = state.wins.preview,
	})

	vim.api.nvim_set_option_value("cursorline", true, {
		win = state.wins.preview,
	})

	vim.api.nvim_set_option_value("wrap", false, {
		win = state.wins.preview,
	})
end

-- ─────────────────────────────────────────────────────────────
-- Open Problems Center
-- ─────────────────────────────────────────────────────────────

local function open_center()
	if state.open then
		close_center()
		return
	end

	local g = geometry()

	if not g then
		notify(
			string.format("Problems Center requires at least %d columns and %d usable lines.", MIN_COLUMNS, MIN_LINES),
			vim.log.levels.WARN
		)

		return
	end

	state.generation = state.generation + 1
	state.refresh_serial = state.refresh_serial + 1
	state.open = true
	state.closing = false

	local _, source_win = source_context()

	state.main_win = valid_win(source_win) and source_win or vim.api.nvim_get_current_win()

	state.main_tab = vim.api.nvim_get_current_tabpage()

	state.root = project_root()
	state.filter = "all"
	state.query = ""

	local ok, err = xpcall(function()
		local suffix = "/" .. tostring(state.generation)

		state.bufs.header = create_buffer("demir://problems/header" .. suffix)

		state.bufs.list = create_buffer("demir://problems/list" .. suffix)

		state.bufs.preview = create_buffer("demir://problems/preview" .. suffix)

		state.bufs.footer = create_buffer("demir://problems/footer" .. suffix)

		state.wins.header = vim.api.nvim_open_win(
			state.bufs.header,
			false,
			float_config(g.row, g.col, g.outer_width - 2, g.header_height, " 󰒡  Problems Center ")
		)

		state.wins.list = vim.api.nvim_open_win(
			state.bufs.list,
			true,
			float_config(g.body_row, g.col, g.left_width, g.body_height, " 󰖩  Project Findings ")
		)

		state.wins.preview = vim.api.nvim_open_win(
			state.bufs.preview,
			false,
			float_config(g.body_row, g.right_col, g.right_width, g.body_height, " 󰈙  Source Preview ")
		)

		state.wins.footer = vim.api.nvim_open_win(
			state.bufs.footer,
			false,
			float_config(g.footer_row, g.col, g.outer_width - 2, g.footer_height, " Actions ")
		)

		configure_windows()
		setup_center_keymaps()
		setup_runtime_events()
		refresh()
	end, debug.traceback)

	if not ok then
		close_center({
			restore_focus = true,
		})

		notify("Problems Center failed to open:\n" .. tostring(err), vim.log.levels.ERROR)
	end
end

local previous_subscription = vim.g[ANALYSIS_SUBSCRIPTION_KEY]

if type(previous_subscription) == "number" then
	pcall(deep_analysis.unsubscribe, previous_subscription)
end

vim.g[ANALYSIS_SUBSCRIPTION_KEY] = deep_analysis.subscribe(function()
	if state.open then
		schedule_refresh(0)
	end
end)

M.open = open_center
M.close = close_center
M.refresh = refresh

-- ─────────────────────────────────────────────────────────────
-- Trouble Bottom Panel
-- ─────────────────────────────────────────────────────────────

trouble.setup({
	auto_close = false,
	auto_open = false,

	auto_refresh = true,
	auto_preview = true,

	focus = true,
	follow = true,
	restore = true,

	indent_guides = true,
	multiline = true,

	open_no_results = true,
	warn_no_results = false,

	modes = {
		buffer_problems = {
			mode = "diagnostics",
			desc = "Current File Diagnostics",

			filter = {
				buf = 0,
			},

			pinned = true,

			win = {
				type = "split",
				position = "bottom",
				size = 0.28,
			},

			preview = {
				type = "main",
				scratch = false,
			},
		},

		buffer_errors = {
			mode = "diagnostics",
			desc = "Current File Errors",

			filter = {
				buf = 0,
				severity = severity.ERROR,
			},

			pinned = true,

			win = {
				type = "split",
				position = "bottom",
				size = 0.28,
			},

			preview = {
				type = "main",
				scratch = false,
			},
		},
	},
})

-- ─────────────────────────────────────────────────────────────
-- Global Keymaps
-- ─────────────────────────────────────────────────────────────

local map = vim.keymap.set

map("n", "<leader>p", open_center, {
	desc = "Project Problems",
})

map("n", "<leader>pb", function()
	trouble.toggle({
		mode = "buffer_problems",
	})
end, {
	desc = "Current file diagnostics",
})

map("n", "<leader>pe", function()
	trouble.toggle({
		mode = "buffer_errors",
	})
end, {
	desc = "Current file errors",
})

return M
