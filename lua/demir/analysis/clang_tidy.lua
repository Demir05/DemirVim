local M = {}

local project = require("demir.core.project")

local severity = vim.diagnostic.severity

local DEEP_CONFIG = vim.fs.normalize(vim.fn.expand("~/.config/clang-tidy/deep.yaml"))

local DEFAULT_MAX_DATABASES = 64
local DEFAULT_JOBS_FALLBACK = 4
local DEFAULT_TU_TIMEOUT_MS = 300000
local CONFIG_VERIFY_TIMEOUT_MS = 15000
local PROGRESS_EMIT_INTERVAL_MS = 100

local remembered_databases = {}

local listeners = {}
local next_listener_id = 0

local state = {
	generation = 0,
	active = nil,

	results = {},

	last = {
		root = nil,
		database = nil,
		started_at = nil,
		finished_at = nil,
		elapsed_ms = nil,

		total = 0,
		completed = 0,
		issues = 0,
		duplicates = 0,
		external_suppressed = 0,
		tool_failures = 0,
		timeouts = 0,

		stale = false,
		buffer_snapshots = {},
	},

	last_attempt = {
		ok = nil,
		reason = nil,
		detail = nil,
		root = nil,
		database = nil,
	},
}

-- ─────────────────────────────────────────────────────────────
-- Basic Helpers
-- ─────────────────────────────────────────────────────────────

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, {
		title = "Deep C++ Analysis",
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

local function path_is_file(path)
	local stat = path ~= "" and vim.uv.fs_stat(path) or nil

	return stat ~= nil and stat.type == "file"
end

local function path_is_directory(path)
	local stat = path ~= "" and vim.uv.fs_stat(path) or nil

	return stat ~= nil and stat.type == "directory"
end

local function file_signature(path)
	local stat = path ~= "" and vim.uv.fs_stat(path) or nil

	if not stat or stat.type ~= "file" then
		return nil
	end

	local mtime = stat.mtime or {}
	local ctime = stat.ctime or {}

	return table.concat({
		tostring(stat.size or 0),
		tostring(mtime.sec or 0),
		tostring(mtime.nsec or 0),
		tostring(ctime.sec or 0),
		tostring(ctime.nsec or 0),
	}, ":")
end

local function inside(root, file)
	root = canonical_path(root)
	file = canonical_path(file)

	if root == "" or file == "" then
		return false
	end

	return file == root or vim.fs.relpath(root, file) ~= nil
end

local function read_text_file(path)
	local handle, open_err = io.open(path, "rb")

	if not handle then
		return nil, open_err
	end

	local ok, content = pcall(handle.read, handle, "*a")

	handle:close()

	if not ok then
		return nil, content
	end

	return content
end

local function elapsed_ms(started_ns)
	if not started_ns then
		return nil
	end

	return math.floor((vim.uv.hrtime() - started_ns) / 1e6)
end

local function worker_count(requested)
	if type(requested) == "number" and requested >= 1 then
		return math.max(1, math.floor(requested))
	end

	local parallelism = DEFAULT_JOBS_FALLBACK
	local ok, value = pcall(vim.uv.available_parallelism)

	if ok and type(value) == "number" and value >= 1 then
		parallelism = value
	end

	-- Static analysis is both CPU- and memory-heavy. Half the available
	-- parallelism, capped at 6, keeps the editor responsive on modern systems.
	return math.max(1, math.min(6, math.floor(parallelism / 2)))
end

local function strip_ansi(text)
	return tostring(text or ""):gsub("\27%[[%d;]*m", "")
end

local function compact_output(text, max_chars)
	text = strip_ansi(text):gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")

	if #text <= max_chars then
		return text
	end

	return text:sub(1, max_chars) .. "\n…"
end

local LLVM_REGEX_META = {
	["\\"] = true,
	["."] = true,
	["^"] = true,
	["$"] = true,
	["|"] = true,
	["?"] = true,
	["*"] = true,
	["+"] = true,
	["("] = true,
	[")"] = true,
	["["] = true,
	["]"] = true,
	["{"] = true,
	["}"] = true,
}

local function escape_llvm_regex(text)
	-- Escape only actual regular-expression metacharacters. In particular,
	-- ordinary path characters such as "_" and "-" must remain untouched.
	return (
		text:gsub(".", function(char)
			if LLVM_REGEX_META[char] then
				return "\\" .. char
			end

			return char
		end)
	)
end

local function executable_or_nil(name)
	if vim.fn.executable(name) == 1 then
		return name
	end

	return nil
end

local function require_runtime_capabilities()
	if type(vim.system) ~= "function" then
		return false, "vim.system() is unavailable."
	end

	if
		not vim.fs
		or type(vim.fs.abspath) ~= "function"
		or type(vim.fs.relpath) ~= "function"
		or type(vim.fs.find) ~= "function"
	then
		return false, "Required vim.fs APIs are unavailable."
	end

	if not vim.uv or type(vim.uv.fs_stat) ~= "function" then
		return false, "Required libuv filesystem APIs are unavailable."
	end

	return true
end

-- ─────────────────────────────────────────────────────────────
-- Context / Project Root
-- ─────────────────────────────────────────────────────────────

local function normal_file_buffer(buf)
	if type(buf) ~= "number" or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
		return false
	end

	if vim.bo[buf].buftype ~= "" then
		return false
	end

	return vim.api.nvim_buf_get_name(buf) ~= ""
end

local function context_buffer()
	local current = vim.api.nvim_get_current_buf()

	if normal_file_buffer(current) then
		return current
	end

	-- Problems Center is a nofile buffer. The alternate buffer is commonly the
	-- source buffer from which the center was opened, so prefer it first.
	local alternate = vim.fn.bufnr("#")

	if alternate >= 0 and normal_file_buffer(alternate) then
		return alternate
	end

	-- Fall back to a normal file buffer visible in the current tabpage.
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)

			if normal_file_buffer(buf) then
				return buf
			end
		end
	end

	return nil
end

local function current_project_root()
	local buf = context_buffer()

	if buf then
		return project.analysis_root(buf)
	end

	return project.analysis_root(vim.fn.getcwd())
end

-- ─────────────────────────────────────────────────────────────
-- Events
-- ─────────────────────────────────────────────────────────────

local function status_snapshot()
	local active = state.active

	if active then
		return {
			running = true,
			phase = active.phase,
			cancelled = active.cancelled,

			root = active.root,
			database = active.database,
			database_dir = active.database_dir,

			total = active.total or 0,
			completed = active.completed or 0,
			running_workers = active.running or 0,
			jobs = active.jobs,

			current_issues = active.results and #active.results or 0,
			duplicates = active.duplicates or 0,
			external_suppressed = active.external_suppressed or 0,
			tool_failures = active.tool_failures or 0,
			timeouts = active.timeouts or 0,

			elapsed_ms = elapsed_ms(active.started_ns),

			committed_root = state.last.root,
			committed_database = state.last.database,
			committed_issues = #state.results,
			stale = state.last.stale == true,

			last_attempt = vim.deepcopy(state.last_attempt),
		}
	end

	return {
		running = false,
		phase = "idle",

		root = state.last.root,
		database = state.last.database,

		total = state.last.total,
		completed = state.last.completed,
		current_issues = state.last.issues,
		duplicates = state.last.duplicates,
		external_suppressed = state.last.external_suppressed,
		tool_failures = state.last.tool_failures,
		timeouts = state.last.timeouts,
		elapsed_ms = state.last.elapsed_ms,

		committed_root = state.last.root,
		committed_database = state.last.database,
		committed_issues = #state.results,
		stale = state.last.stale == true,

		last_attempt = vim.deepcopy(state.last_attempt),
	}
end

local function emit(event)
	local snapshot = status_snapshot()

	for _, callback in pairs(listeners) do
		local ok, err = pcall(callback, event, snapshot)

		if not ok then
			local message = "Deep-analysis listener failed: " .. tostring(err)

			vim.schedule(function()
				vim.notify_once(message, vim.log.levels.WARN, {
					title = "Deep C++ Analysis",
				})
			end)
		end
	end
end

local function emit_progress(run, force)
	local now = vim.uv.hrtime()
	local interval_ns = PROGRESS_EMIT_INTERVAL_MS * 1000000

	if force or not run.last_progress_emit_ns or (now - run.last_progress_emit_ns) >= interval_ns then
		run.last_progress_emit_ns = now
		emit("progress")
	end
end

function M.subscribe(callback)
	if type(callback) ~= "function" then
		error("Deep-analysis subscriber must be a function.")
	end

	next_listener_id = next_listener_id + 1
	listeners[next_listener_id] = callback

	return next_listener_id
end

function M.unsubscribe(id)
	listeners[id] = nil
end

-- ─────────────────────────────────────────────────────────────
-- Compilation Database Discovery
-- ─────────────────────────────────────────────────────────────

local function database_score(root, database)
	database = canonical_path(database)

	local relative = vim.fs.relpath(root, database) or database

	if relative == "compile_commands.json" then
		return 0
	end

	if relative == "build/compile_commands.json" then
		return 1
	end

	if relative:match("^build/") then
		return 10 + select(2, relative:gsub("/", ""))
	end

	if relative:match("^out/") then
		return 20 + select(2, relative:gsub("/", ""))
	end

	if relative:match("^cmake%-build[^/]*/") then
		return 30 + select(2, relative:gsub("/", ""))
	end

	return 100 + select(2, relative:gsub("/", ""))
end

local function normalize_database_option(path, root)
	if type(path) ~= "string" or path == "" then
		return nil
	end

	path = vim.fs.abspath(path, {
		cwd = root,
	})
	path = canonical_path(path)

	if path_is_directory(path) then
		path = canonical_path(vim.fs.joinpath(path, "compile_commands.json"))
	end

	if not path_is_file(path) then
		return nil
	end

	if vim.fs.basename(path) ~= "compile_commands.json" then
		return nil
	end

	return path
end

local function discover_databases(root)
	local found = {}
	local seen = {}

	local function add(path)
		path = canonical_path(path)

		if path ~= "" and path_is_file(path) and not seen[path] then
			seen[path] = true
			table.insert(found, path)
		end
	end

	add(vim.fs.joinpath(root, "compile_commands.json"))
	add(vim.fs.joinpath(root, "build", "compile_commands.json"))

	local recursive, errors = vim.fs.find("compile_commands.json", {
		path = root,
		type = "file",
		limit = DEFAULT_MAX_DATABASES,
	})

	for _, path in ipairs(recursive or {}) do
		add(path)
	end

	table.sort(found, function(a, b)
		local sa = database_score(root, a)
		local sb = database_score(root, b)

		if sa ~= sb then
			return sa < sb
		end

		return a < b
	end)

	if #found == 0 then
		local suffix = ""

		if type(errors) == "table" and #errors > 0 then
			suffix = "\nFilesystem search: " .. table.concat(errors, "; ")
		end

		return nil, "No compile_commands.json was found below:\n" .. root .. suffix
	end

	return found
end

local function database_label(root, path, index)
	local relative = vim.fs.relpath(root, path) or path
	local score = database_score(root, path)

	if index == 1 and score <= 1 then
		return relative .. "  (recommended)"
	end

	return relative
end

local function resolve_database(run, opts, callback)
	local explicit = opts.database

	if
		explicit == nil
		and type(vim.g.demir_clang_tidy_database) == "string"
		and vim.g.demir_clang_tidy_database ~= ""
	then
		explicit = vim.g.demir_clang_tidy_database
	end

	if explicit then
		local database = normalize_database_option(explicit, run.root)

		if not database then
			callback(nil, "Configured compilation database is invalid:\n" .. tostring(explicit))
			return
		end

		remembered_databases[run.root] = database
		callback(database)
		return
	end

	local remembered = remembered_databases[run.root]

	if remembered and path_is_file(remembered) then
		callback(remembered)
		return
	end

	local databases, err = discover_databases(run.root)

	if not databases then
		callback(nil, err)
		return
	end

	if #databases == 1 then
		remembered_databases[run.root] = databases[1]
		callback(databases[1])
		return
	end

	run.phase = "selecting_database"
	emit("phase")

	local generation = run.generation

	vim.ui.select(databases, {
		prompt = "Select compilation database:",
		kind = "demir-clang-tidy-database",

		format_item = function(item)
			for index, path in ipairs(databases) do
				if path == item then
					return database_label(run.root, path, index)
				end
			end

			return item
		end,
	}, function(choice)
		if
			state.active ~= run
			or run.generation ~= state.generation
			or generation ~= state.generation
			or run.cancelled
		then
			return
		end

		if not choice then
			callback(nil, "Compilation database selection was cancelled.", true)
			return
		end

		remembered_databases[run.root] = choice
		callback(choice)
	end)
end

local function load_database(root, database)
	local content, read_err = read_text_file(database)

	if not content then
		return nil, "Could not read compilation database:\n" .. tostring(read_err)
	end

	local ok, decoded = pcall(vim.json.decode, content)

	if not ok or type(decoded) ~= "table" then
		return nil, "compile_commands.json is not valid JSON:\n" .. tostring(decoded)
	end

	local units = {}
	local seen = {}

	for _, command in ipairs(decoded) do
		if type(command) == "table" and type(command.file) == "string" and command.file ~= "" then
			local directory = type(command.directory) == "string" and command.directory ~= "" and command.directory
				or root

			directory = canonical_path(vim.fs.abspath(directory, {
				cwd = root,
			}))

			local file = canonical_path(vim.fs.abspath(command.file, {
				cwd = directory ~= "" and directory or root,
			}))

			-- Follow LLVM's run-clang-tidy model and trust the compilation
			-- database to define translation units instead of guessing from file
			-- extensions. This supports modules and uncommon C/C++ suffixes.
			if
				inside(root, file)
				and not file:find("/CMakeFiles/", 1, true)
				and not file:find("/CMakeTmp/", 1, true)
				and not file:find("/CompilerIdC/", 1, true)
				and not file:find("/CompilerIdCXX/", 1, true)
				and not seen[file]
			then
				seen[file] = true

				table.insert(units, {
					file = file,
					directory = directory ~= "" and directory or root,
				})
			end
		end
	end

	table.sort(units, function(a, b)
		return a.file < b.file
	end)

	if #units == 0 then
		return nil, "The compilation database does not contain any translation units inside the project root."
	end

	return units
end

-- ─────────────────────────────────────────────────────────────
-- Unsaved Project Files
-- ─────────────────────────────────────────────────────────────

local function modified_project_buffers(root)
	local buffers = {}

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_valid(buf)
			and vim.api.nvim_buf_is_loaded(buf)
			and vim.bo[buf].buftype == ""
			and vim.bo[buf].modified
		then
			local file = canonical_path(vim.api.nvim_buf_get_name(buf))

			if inside(root, file) then
				table.insert(buffers, buf)
			end
		end
	end

	return buffers
end

local function save_buffers(buffers)
	for _, buf in ipairs(buffers) do
		local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
			vim.cmd("silent keepalt write")
		end)

		if not ok then
			return false, err
		end
	end

	return true
end

local function prepare_modified_buffers(run, opts, callback)
	local modified = modified_project_buffers(run.root)

	if #modified == 0 then
		callback(true)
		return
	end

	if opts.save == true then
		local saved, save_err = save_buffers(modified)

		if not saved then
			callback(false, "Project files could not be saved before analysis:\n" .. tostring(save_err))
			return
		end

		callback(true)
		return
	end

	if opts.prompt_save == false then
		callback(false, string.format("%d modified project buffer(s) must be saved before deep analysis.", #modified))
		return
	end

	run.phase = "awaiting_save"
	emit("phase")

	local generation = run.generation

	vim.ui.select({
		"Save project files and analyze",
		"Cancel",
	}, {
		prompt = string.format(
			"%d modified project buffer(s) must be saved for an accurate disk-based analysis.",
			#modified
		),
		kind = "demir-clang-tidy-save",
	}, function(choice)
		if
			state.active ~= run
			or run.generation ~= state.generation
			or generation ~= state.generation
			or run.cancelled
		then
			return
		end

		if choice ~= "Save project files and analyze" then
			callback(false, "Analysis cancelled.", true)
			return
		end

		local saved, save_err = save_buffers(modified)

		if not saved then
			callback(false, "Project files could not be saved before analysis:\n" .. tostring(save_err))
			return
		end

		callback(true)
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Diagnostic Parsing
-- ─────────────────────────────────────────────────────────────

local function diagnostic_key(item)
	return table.concat({
		item.file,
		tostring(item.lnum),
		tostring(item.col),
		tostring(item.severity),
		item.code,
		item.message,
	}, "\30")
end

local function note_key(note)
	return table.concat({
		note.file or "",
		tostring(note.lnum or -1),
		tostring(note.col or -1),
		note.message or "",
	}, "\30")
end

local function resolve_diagnostic_path(run, unit, path)
	path = normalize_path(path)

	if path == "" then
		return ""
	end

	-- vim.fs.abspath() leaves an already-absolute path unchanged, so the same
	-- resolution path handles both absolute and relative clang diagnostics.
	local candidates = {
		vim.fs.abspath(path, {
			cwd = unit.directory,
		}),
		vim.fs.abspath(path, {
			cwd = run.root,
		}),
		vim.fs.abspath(path, {
			cwd = run.database_dir,
		}),
	}

	for _, candidate in ipairs(candidates) do
		if path_is_file(candidate) then
			return canonical_path(candidate)
		end
	end

	return canonical_path(candidates[1])
end

local function parse_process_output(run, unit, stdout, stderr)
	local output = strip_ansi((stdout or "") .. "\n" .. (stderr or ""))

	local diagnostics = {}
	local last_primary = nil
	local external_suppressed = 0

	for line in output:gmatch("[^\n]+") do
		local file, lnum, col, level, message = line:match("^(.-):(%d+):(%d+):%s*([%a ]+):%s*(.+)$")

		if file and lnum and col and message then
			level = vim.trim(level:lower())

			if level == "warning" or level == "error" or level == "fatal error" or level == "note" then
				file = resolve_diagnostic_path(run, unit, file)

				local clean_message, check = message:match("^(.-)%s+%[([^%]]+)%]%s*$")

				if not clean_message then
					clean_message = message
					check = ""
				end

				local parsed = {
					file = file,
					lnum = math.max(0, tonumber(lnum) - 1),
					col = math.max(0, tonumber(col) - 1),
					message = clean_message,
					code = check,
				}

				if level == "note" then
					if last_primary then
						last_primary.notes = last_primary.notes or {}
						table.insert(last_primary.notes, parsed)
					end
				elseif inside(run.root, file) then
					parsed.severity = (level == "error" or level == "fatal error") and severity.ERROR or severity.WARN
					parsed.source = "clang-tidy · deep"
					parsed.origin = "deep"
					parsed.notes = {}

					table.insert(diagnostics, parsed)
					last_primary = parsed
				else
					external_suppressed = external_suppressed + 1
					last_primary = nil
				end
			end
		end
	end

	return diagnostics, external_suppressed
end

local function merge_diagnostic(run, item)
	local key = diagnostic_key(item)
	local existing = run.seen[key]

	if not existing then
		run.seen[key] = item
		table.insert(run.results, item)
		return
	end

	run.duplicates = run.duplicates + 1

	if type(item.notes) ~= "table" or #item.notes == 0 then
		return
	end

	existing.notes = existing.notes or {}

	local seen_notes = {}

	for _, note in ipairs(existing.notes) do
		seen_notes[note_key(note)] = true
	end

	for _, note in ipairs(item.notes) do
		local key_note = note_key(note)

		if not seen_notes[key_note] then
			seen_notes[key_note] = true
			table.insert(existing.notes, note)
		end
	end
end

local function sort_results(results)
	table.sort(results, function(a, b)
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
end

-- ─────────────────────────────────────────────────────────────
-- Scan Integrity
-- ─────────────────────────────────────────────────────────────

local function snapshot_translation_units(units)
	local signatures = {}

	for _, unit in ipairs(units) do
		signatures[unit.file] = file_signature(unit.file)
	end

	return signatures
end

local function translation_units_changed(run)
	for _, unit in ipairs(run.units) do
		if file_signature(unit.file) ~= run.unit_signatures[unit.file] then
			return true, unit.file
		end
	end

	return false
end

local ANALYSIS_INPUT_EXTENSIONS = {
	[".c"] = true,
	[".cc"] = true,
	[".cpp"] = true,
	[".cxx"] = true,
	[".c++"] = true,
	[".h"] = true,
	[".hh"] = true,
	[".hpp"] = true,
	[".hxx"] = true,
	[".h++"] = true,
	[".inc"] = true,
	[".inl"] = true,
	[".ipp"] = true,
	[".tpp"] = true,
	[".def"] = true,
	[".m"] = true,
	[".mm"] = true,
	[".ixx"] = true,
	[".cppm"] = true,
	[".ccm"] = true,
	[".cxxm"] = true,
	[".mpp"] = true,
	[".cu"] = true,
	[".cuh"] = true,
}

local INTEGRITY_SKIP_DIRECTORIES = {
	[".git"] = true,
	[".hg"] = true,
	[".svn"] = true,
}

local function analysis_input_candidate(path)
	local basename = vim.fs.basename(path):lower()
	local extension = basename:match("(%.[^./]+)$")

	return extension ~= nil and ANALYSIS_INPUT_EXTENSIONS[extension] == true
end

-- Snapshot the project-local C/C++ semantic-input surface rather than the
-- entire repository. This deliberately includes generated headers/sources in
-- build directories while ignoring object files, caches, documentation, VCS
-- metadata, and other files that cannot directly participate in a clang-tidy
-- translation unit. The snapshot is stat-only, so the cost stays small next to
-- the clang-tidy scan itself.
local function snapshot_analysis_inputs(root)
	root = canonical_path(root)

	if root == "" or not path_is_directory(root) then
		return nil, "Analysis root is not a readable directory."
	end

	local snapshots = {}
	local stack = { root }
	local seen_directories = {}

	while #stack > 0 do
		local directory = table.remove(stack)
		local canonical_directory = canonical_path(directory)

		if canonical_directory ~= "" and not seen_directories[canonical_directory] then
			seen_directories[canonical_directory] = true

			local scanner, scan_err = vim.uv.fs_scandir(directory)

			if not scanner then
				return nil, string.format("Could not inspect analysis-input directory:\n%s\n%s", directory, tostring(scan_err))
			end

			while true do
				local name, kind = vim.uv.fs_scandir_next(scanner)

				if not name then
					break
				end

				local path = vim.fs.joinpath(directory, name)

				if kind == "directory" then
					if not INTEGRITY_SKIP_DIRECTORIES[name] then
						table.insert(stack, path)
					end
				elseif kind == "file" then
					if analysis_input_candidate(path) then
						local file = canonical_path(path)

						if file ~= "" then
							snapshots[file] = file_signature(file)
						end
					end
				elseif kind == "link" and analysis_input_candidate(path) then
					-- Follow file symlinks but not directory symlinks. This tracks a
					-- project header/source symlink without recursively walking an
					-- arbitrary external tree or risking symlink-directory cycles.
					local file = canonical_path(path)

					if file ~= "" and path_is_file(file) then
						snapshots[file] = file_signature(file)
					end
				end
			end
		end
	end

	return snapshots
end

local function analysis_inputs_changed(run)
	local current, snapshot_err = snapshot_analysis_inputs(run.root)

	if not current then
		return true, nil, snapshot_err
	end

	for file, signature in pairs(run.input_signatures or {}) do
		if current[file] ~= signature then
			return true, file
		end
	end

	for file in pairs(current) do
		if (run.input_signatures or {})[file] == nil then
			return true, file
		end
	end

	return false
end

local function snapshot_project_buffers(root)
	local snapshots = {}

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_valid(buf)
			and vim.api.nvim_buf_is_loaded(buf)
			and vim.bo[buf].buftype == ""
		then
			local file = canonical_path(vim.api.nvim_buf_get_name(buf))

			if file ~= "" and inside(root, file) then
				snapshots[buf] = {
					file = file,
					changedtick = vim.api.nvim_buf_get_changedtick(buf),
				}
			end
		end
	end

	return snapshots
end

local function buffer_changed_since(snapshots, buf, file)
	local baseline = snapshots and snapshots[buf] or nil

	if not baseline or baseline.file ~= file then
		return true
	end

	return vim.api.nvim_buf_get_changedtick(buf) ~= baseline.changedtick
end

local function project_buffers_changed(run)
	for buf, baseline in pairs(run.buffer_snapshots or {}) do
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
			local file = canonical_path(vim.api.nvim_buf_get_name(buf))

			if file ~= baseline.file then
				return true, file ~= "" and file or baseline.file
			end

			if vim.api.nvim_buf_get_changedtick(buf) ~= baseline.changedtick then
				return true, file
			end

			if vim.bo[buf].modified then
				return true, file
			end
		end
	end

	-- Also catch a project buffer that was opened after the scan snapshot and
	-- currently contains unsaved edits. TextChanged normally catches this case,
	-- but this finish-time check keeps the integrity decision independent of
	-- autocmd delivery timing.
	local modified = modified_project_buffers(run.root)

	if #modified > 0 then
		local buf = modified[1]
		return true, canonical_path(vim.api.nvim_buf_get_name(buf))
	end

	return false
end

-- ─────────────────────────────────────────────────────────────
-- Process Management
-- ─────────────────────────────────────────────────────────────

local function analysis_command(run, unit)
	local header_filter = "^" .. escape_llvm_regex(run.root) .. "/"

	return {
		run.clang_tidy,
		unit.file,
		"-p=" .. run.database_dir,
		"--config-file=" .. DEEP_CONFIG,
		"--header-filter=" .. header_filter,
		"--use-color=false",
		"--quiet",
	}
end

local function remember_failure(run, unit, result, kind)
	if run.first_failure then
		return
	end

	local detail = compact_output((result.stderr or "") .. "\n" .. (result.stdout or ""), 2000)

	run.first_failure = {
		file = unit and unit.file or nil,
		code = result.code,
		signal = result.signal,
		kind = kind or "clang-tidy",
		detail = detail,
	}
end

local function terminate_session(run)
	if state.active == run then
		state.active = nil
	end

	for process in pairs(run.children or {}) do
		local ok, closing = pcall(process.is_closing, process)

		if not ok or not closing then
			pcall(process.kill, process, "sigterm")
		end
	end

	run.children = {}
end

local function fail_run(run, reason, detail, cancelled)
	if state.active ~= run then
		return
	end

	terminate_session(run)

	state.last_attempt = {
		ok = false,
		reason = reason,
		detail = detail,
		root = run.root,
		database = run.database,
	}

	if cancelled then
		emit("cancelled")
		return
	end

	emit("failed")

	local message = reason

	if detail and detail ~= "" then
		message = message .. "\n\n" .. detail
	end

	notify(message, vim.log.levels.ERROR)
end

local function finish_run(run)
	if state.active ~= run or run.generation ~= state.generation or run.cancelled then
		return
	end

	local compilation_model_changed = run.compilation_model_changed == true
	local database_changed = file_signature(run.database) ~= run.database_signature
	local config_changed = file_signature(DEEP_CONFIG) ~= run.config_signature
	local buffers_changed, changed_buffer = project_buffers_changed(run)
	local units_changed, changed_unit = translation_units_changed(run)
	local inputs_changed, changed_input, input_check_error = analysis_inputs_changed(run)
	local project_changed = run.dirty or buffers_changed

	if compilation_model_changed or project_changed or database_changed or config_changed or units_changed or inputs_changed then
		local reason
		local changed_file

		if compilation_model_changed then
			reason = "the active CMake compilation model changed while the scan was running"
			changed_file = run.compilation_model_database
		elseif project_changed then
			reason = "project buffers changed while the scan was running"
			changed_file = run.dirty_file or changed_buffer
		elseif database_changed then
			reason = "compile_commands.json changed while the scan was running"
			changed_file = run.database
		elseif config_changed then
			reason = "the deep-analysis configuration changed while the scan was running"
			changed_file = DEEP_CONFIG
		elseif units_changed then
			reason = "a translation unit changed outside Neovim while the scan was running"
			changed_file = changed_unit
		else
			reason = input_check_error
				and ("the project analysis-input surface could not be revalidated: " .. input_check_error)
				or "a project C/C++ analysis input changed outside Neovim while the scan was running"
			changed_file = changed_input
		end

		terminate_session(run)

		state.last_attempt = {
			ok = false,
			reason = "Analysis results were discarded.",
			detail = changed_file and (reason .. ":\n" .. changed_file) or reason,
			root = run.root,
			database = run.database,
		}

		emit("discarded")

		notify(
			"Deep analysis finished, but its results were discarded because "
				.. reason
				.. ". Previous committed results were kept.",
			vim.log.levels.WARN
		)

		return
	end

	-- A non-zero clang-tidy exit means the scan was not complete. LLVM itself
	-- treats such invocations as failed in run-clang-tidy. Never replace a
	-- known-good committed result set with a partial result set.
	if run.tool_failures > 0 then
		local failure = run.first_failure or {}
		local detail = ""

		if failure.file then
			detail = "Translation unit: " .. failure.file
		end

		if failure.kind then
			detail = detail .. (detail ~= "" and "\n" or "") .. "Failure: " .. failure.kind
		end

		if failure.code ~= nil then
			detail = detail .. (detail ~= "" and "\n" or "") .. "Exit code: " .. tostring(failure.code)
		end

		if failure.detail and failure.detail ~= "" then
			detail = detail .. (detail ~= "" and "\n\n" or "") .. failure.detail
		end

		terminate_session(run)

		state.last_attempt = {
			ok = false,
			reason = string.format(
				"Deep analysis was incomplete: %d clang-tidy invocation(s) failed.",
				run.tool_failures
			),
			detail = detail,
			root = run.root,
			database = run.database,
		}

		emit("failed")

		notify(
			state.last_attempt.reason
				.. "\nPrevious committed results were kept."
				.. (detail ~= "" and ("\n\n" .. detail) or ""),
			vim.log.levels.ERROR
		)

		return
	end

	sort_results(run.results)

	state.results = run.results

	local finished_ns = vim.uv.hrtime()
	local elapsed = math.floor((finished_ns - run.started_ns) / 1e6)

	state.last = {
		root = run.root,
		database = run.database,
		started_at = run.started_ns,
		finished_at = finished_ns,
		elapsed_ms = elapsed,

		total = run.total,
		completed = run.completed,
		issues = #run.results,
		duplicates = run.duplicates,
		external_suppressed = run.external_suppressed,
		tool_failures = 0,
		timeouts = 0,

		stale = false,
		buffer_snapshots = snapshot_project_buffers(run.root),
	}

	state.last_attempt = {
		ok = true,
		reason = nil,
		detail = nil,
		root = run.root,
		database = run.database,
	}

	terminate_session(run)

	emit("completed")

	notify(
		string.format(
			"Deep analysis complete: %d issues across %d translation units in %.1fs.",
			#state.results,
			run.total,
			elapsed / 1000
		)
	)
end

local function pump(run)
	if state.active ~= run or run.generation ~= state.generation or run.cancelled or run.phase ~= "running" then
		return
	end

	while run.running < run.jobs and run.next_index <= run.total do
		local unit = run.units[run.next_index]

		run.next_index = run.next_index + 1
		run.running = run.running + 1

		local command = analysis_command(run, unit)
		local process = nil

		local ok, process_or_err = pcall(vim.system, command, {
			cwd = path_is_directory(unit.directory) and unit.directory or run.root,
			text = true,
			timeout = run.timeout_ms,

			env = {
				NO_COLOR = "1",
			},
		}, function(result)
			vim.schedule(function()
				if process then
					run.children[process] = nil
				end

				if state.active ~= run or run.generation ~= state.generation or run.cancelled then
					return
				end

				run.running = math.max(0, run.running - 1)
				run.completed = run.completed + 1

				if result.code ~= 0 then
					run.tool_failures = run.tool_failures + 1

					if result.code == 124 then
						run.timeouts = run.timeouts + 1
						remember_failure(run, unit, result, "timeout")
					else
						remember_failure(run, unit, result, "clang-tidy")
					end
				end

				local parsed, external_suppressed = parse_process_output(run, unit, result.stdout, result.stderr)

				run.external_suppressed = run.external_suppressed + external_suppressed

				for _, item in ipairs(parsed) do
					merge_diagnostic(run, item)
				end

				emit_progress(run, run.completed >= run.total)

				if run.completed >= run.total and run.running == 0 then
					finish_run(run)
				else
					pump(run)
				end
			end)
		end)

		if ok then
			process = process_or_err
			run.children[process] = true
		else
			run.running = math.max(0, run.running - 1)
			run.completed = run.completed + 1
			run.tool_failures = run.tool_failures + 1

			remember_failure(run, unit, {
				code = nil,
				signal = nil,
				stdout = "",
				stderr = tostring(process_or_err),
			}, "spawn")

			emit_progress(run, run.completed >= run.total)

			if run.completed >= run.total and run.running == 0 then
				finish_run(run)
				return
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────
-- Configuration Verification
-- ─────────────────────────────────────────────────────────────

local function verify_configuration(run, callback)
	run.phase = "verifying"
	emit("phase")

	local sample = run.units[1]
	local config_signature = file_signature(DEEP_CONFIG)

	if not config_signature then
		callback(false, "Deep-analysis configuration disappeared before verification.")
		return
	end

	local command = {
		run.clang_tidy,
		sample.file,
		"-p=" .. run.database_dir,
		"--config-file=" .. DEEP_CONFIG,
		"--verify-config",
		"--use-color=false",
	}

	local process = nil

	local ok, process_or_err = pcall(vim.system, command, {
		cwd = sample.directory,
		text = true,
		timeout = CONFIG_VERIFY_TIMEOUT_MS,

		env = {
			NO_COLOR = "1",
		},
	}, function(result)
		vim.schedule(function()
			if process then
				run.children[process] = nil
			end

			if state.active ~= run or run.generation ~= state.generation or run.cancelled then
				return
			end

			if file_signature(DEEP_CONFIG) ~= config_signature then
				callback(false, "Deep-analysis configuration changed while it was being verified.")
				return
			end

			if result.code ~= 0 then
				local detail = compact_output((result.stderr or "") .. "\n" .. (result.stdout or ""), 3000)

				callback(false, "Deep-analysis configuration verification failed.", detail)
				return
			end

			run.config_signature = config_signature
			callback(true)
		end)
	end)

	if ok then
		process = process_or_err
		run.children[process] = true
	else
		callback(false, "clang-tidy configuration verification could not be started.", tostring(process_or_err))
	end
end

-- ─────────────────────────────────────────────────────────────
-- Analysis Preparation
-- ─────────────────────────────────────────────────────────────

local function begin_scan(run)
	run.phase = "running"

	run.results = {}
	run.seen = {}
	run.duplicates = 0
	run.external_suppressed = 0
	run.tool_failures = 0
	run.timeouts = 0
	run.first_failure = nil

	run.next_index = 1
	run.completed = 0
	run.running = 0

	-- Capture editor and filesystem state at the exact boundary where the
	-- disk-based scan becomes authoritative. Delayed TextChanged events from
	-- edits that happened before this point are ignored unless changedtick has
	-- actually advanced beyond this snapshot.
	run.buffer_snapshots = snapshot_project_buffers(run.root)
	run.unit_signatures = snapshot_translation_units(run.units)

	local input_signatures, input_snapshot_err = snapshot_analysis_inputs(run.root)

	if not input_signatures then
		fail_run(run, "Project analysis inputs could not be snapshotted before deep analysis.", input_snapshot_err)
		return
	end

	run.input_signatures = input_signatures
	run.started_ns = vim.uv.hrtime()
	run.dirty = false
	run.dirty_file = nil
	run.compilation_model_changed = false
	run.compilation_model_database = nil

	state.last_attempt = {
		ok = nil,
		reason = nil,
		detail = nil,
		root = run.root,
		database = run.database,
	}

	emit("started")

	notify(
		string.format(
			"Deep analysis started: %d translation units, %d worker(s).\nCompilation database: %s",
			run.total,
			run.jobs,
			run.database
		)
	)

	pump(run)
end

local function finalize_preparation(run, opts)
	run.phase = "finalizing"
	emit("phase")

	-- Database discovery and config verification are asynchronous. Re-check
	-- project buffers immediately before the scan so an edit made during those
	-- phases cannot slip through the initial save barrier.
	prepare_modified_buffers(run, opts, function(ok, err, cancelled)
		if state.active ~= run or run.generation ~= state.generation or run.cancelled then
			return
		end

		if not ok then
			fail_run(run, err or "Final analysis preparation failed.", nil, cancelled)
			return
		end

		local remaining_modified = modified_project_buffers(run.root)

		if #remaining_modified > 0 then
			local file = canonical_path(vim.api.nvim_buf_get_name(remaining_modified[1]))

			fail_run(
				run,
				"Project files changed while deep analysis was being prepared.",
				file ~= "" and file or nil
			)
			return
		end

		if file_signature(run.database) ~= run.database_signature then
			fail_run(
				run,
				"Compilation database changed while deep analysis was being prepared.",
				run.database
			)
			return
		end

		if file_signature(DEEP_CONFIG) ~= run.config_signature then
			fail_run(
				run,
				"Deep-analysis configuration changed while the scan was being prepared.",
				DEEP_CONFIG
			)
			return
		end

		begin_scan(run)
	end)
end

local function prepare_database(run, opts)
	run.phase = "discovering_database"
	emit("phase")

	resolve_database(run, opts, function(database, err, cancelled)
		if state.active ~= run or run.generation ~= state.generation or run.cancelled then
			return
		end

		if not database then
			fail_run(run, err or "Compilation database could not be resolved.", nil, cancelled)
			return
		end

		run.database = canonical_path(database)
		run.database_dir = canonical_path(vim.fs.dirname(run.database))

		run.phase = "loading_database"
		emit("phase")

		local database_signature_before = file_signature(run.database)

		if not database_signature_before then
			fail_run(run, "Compilation database disappeared before it could be loaded.", run.database)
			return
		end

		local units, load_err = load_database(run.root, run.database)

		if not units then
			fail_run(run, load_err)
			return
		end

		local database_signature_after = file_signature(run.database)

		if database_signature_after ~= database_signature_before then
			fail_run(run, "Compilation database changed while it was being loaded.", run.database)
			return
		end

		run.database_signature = database_signature_after
		run.units = units
		run.total = #units

		verify_configuration(run, function(ok, verify_err, detail)
			if state.active ~= run or run.generation ~= state.generation or run.cancelled then
				return
			end

			if not ok then
				fail_run(run, verify_err, detail)
				return
			end

			finalize_preparation(run, opts)
		end)
	end)
end

local function start_analysis(opts)
	opts = opts or {}

	if state.active then
		notify(
			"A deep analysis request is already active. Cancel it before starting another scan.",
			vim.log.levels.WARN
		)
		return false
	end

	local runtime_ok, runtime_err = require_runtime_capabilities()

	if not runtime_ok then
		notify("Deep analysis cannot start:\n" .. runtime_err, vim.log.levels.ERROR)
		return false
	end

	local clang_tidy = executable_or_nil("clang-tidy")

	if not clang_tidy then
		notify("clang-tidy is not available in PATH.", vim.log.levels.ERROR)
		return false
	end

	if not path_is_file(DEEP_CONFIG) then
		notify("Deep-analysis configuration was not found:\n" .. DEEP_CONFIG, vim.log.levels.ERROR)
		return false
	end

	if opts.jobs ~= nil then
		if type(opts.jobs) ~= "number" or opts.jobs < 1 or opts.jobs % 1 ~= 0 then
			notify("Worker count must be a positive integer.", vim.log.levels.ERROR)
			return false
		end
	end

	local timeout_ms = opts.timeout_ms or DEFAULT_TU_TIMEOUT_MS

	if type(timeout_ms) ~= "number" or timeout_ms < 1000 or timeout_ms % 1 ~= 0 then
		notify("Per-translation-unit timeout must be an integer of at least 1000 ms.", vim.log.levels.ERROR)
		return false
	end

	state.generation = state.generation + 1

	local run = {
		generation = state.generation,
		phase = "preparing",
		cancelled = false,

		root = opts.root and canonical_path(vim.fs.abspath(opts.root, {
			cwd = vim.fn.getcwd(),
		})) or current_project_root(),

		clang_tidy = clang_tidy,

		jobs = worker_count(opts.jobs),
		timeout_ms = timeout_ms,

		children = {},
		last_progress_emit_ns = nil,
	}

	state.active = run

	emit("preparing")

	prepare_modified_buffers(run, opts, function(ok, err, cancelled)
		if state.active ~= run or run.generation ~= state.generation or run.cancelled then
			return
		end

		if not ok then
			fail_run(run, err or "Analysis preparation failed.", nil, cancelled)
			return
		end

		prepare_database(run, opts)
	end)

	return true
end

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

function M.is_running()
	return state.active ~= nil
end

function M.results()
	return vim.deepcopy(state.results)
end

-- Internal read-only fast path for trusted Demir UI modules. Callers must not
-- mutate the returned table.
function M.peek_results()
	return state.results
end

function M.status()
	return status_snapshot()
end

---Invalidate cached compilation-model state for one analysis root.
---
---This is intentionally separate from source freshness. A CMake profile or
---configure change can alter compiler flags and the selected compilation
---database without modifying any source buffer.
---@param root string
---@param database? string
---@param reason? string
---@return boolean
function M.invalidate_compilation_model(root, database, reason)
	root = canonical_path(root)

	if root == "" then
		return false
	end

	-- If CMake supplied a valid active database, make it the next automatic
	-- deep-analysis choice. This both invalidates the old remembered profile and
	-- follows DemirVim's source-root compile_commands.json ownership model. An
	-- explicit vim.g.demir_clang_tidy_database still takes precedence later.
	local normalized_database = normalize_database_option(database, root)
	remembered_databases[root] = normalized_database

	database = normalized_database or canonical_path(database)
	reason = type(reason) == "string" and reason ~= "" and reason or "CMake compilation model changed"

	local active = state.active

	if active and canonical_path(active.root) == root then
		if active.phase == "running" then
			active.compilation_model_changed = true
			active.compilation_model_database = database ~= "" and database or nil
		else
			fail_run(
				active,
				"Deep analysis was invalidated by a CMake compilation-model change.",
				reason .. (database ~= "" and ("\nCompilation database: " .. database) or "")
			)
		end
	end

	if state.last.root and canonical_path(state.last.root) == root and not state.last.stale then
		state.last.stale = true
		emit("stale")
	end

	return true
end

function M.clear()
	if state.active then
		notify("Deep-analysis results cannot be cleared while an analysis request is active.", vim.log.levels.WARN)
		return false
	end

	state.results = {}

	state.last = {
		root = nil,
		database = nil,
		started_at = nil,
		finished_at = nil,
		elapsed_ms = nil,

		total = 0,
		completed = 0,
		issues = 0,
		duplicates = 0,
		external_suppressed = 0,
		tool_failures = 0,
		timeouts = 0,

		stale = false,
		buffer_snapshots = {},
	}

	state.last_attempt = {
		ok = nil,
		reason = nil,
		detail = nil,
		root = nil,
		database = nil,
	}

	emit("cleared")
	notify("Deep-analysis results cleared.")

	return true
end

function M.cancel()
	local run = state.active

	if not run then
		notify("No deep analysis request is currently active.", vim.log.levels.INFO)
		return false
	end

	run.cancelled = true
	state.generation = state.generation + 1

	local completed = run.completed or 0
	local total = run.total or 0

	terminate_session(run)

	state.last_attempt = {
		ok = false,
		reason = "Analysis cancelled.",
		detail = nil,
		root = run.root,
		database = run.database,
	}

	emit("cancelled")

	notify(
		string.format(
			"Deep analysis cancelled at phase '%s'%s. Previous committed results were kept.",
			run.phase,
			total > 0 and string.format(" after %d/%d translation units", completed, total) or ""
		),
		vim.log.levels.WARN
	)

	return true
end

function M.run(opts)
	return start_analysis(opts)
end

-- ─────────────────────────────────────────────────────────────
-- Result Freshness
-- ─────────────────────────────────────────────────────────────

local freshness_group = vim.api.nvim_create_augroup("DemirDeepAnalysisFreshness", {
	clear = true,
})

local function mark_project_changed(buf)
	-- TextChanged* also fires for plugin-owned scratch buffers. Deep-analysis
	-- freshness only tracks normal file buffers; treating a nofile URI such as
	-- demir://problems/list/... as a filesystem path can create a false
	-- project mutation and discard an otherwise valid scan.
	if not normal_file_buffer(buf) then
		return
	end

	local file = canonical_path(vim.api.nvim_buf_get_name(buf))

	if file == "" then
		return
	end

	local active = state.active

	if active and active.phase == "running" and inside(active.root, file) then
		if buffer_changed_since(active.buffer_snapshots, buf, file) then
			active.dirty = true
			active.dirty_file = active.dirty_file or file
		end
	end

	if state.last.root and not state.last.stale and inside(state.last.root, file) then
		if buffer_changed_since(state.last.buffer_snapshots, buf, file) then
			state.last.stale = true
			emit("stale")
		end
	end
end

vim.api.nvim_create_autocmd({
	"TextChanged",
	"TextChangedI",
	"BufWritePost",
}, {
	group = freshness_group,
	pattern = "*",

	callback = function(args)
		mark_project_changed(args.buf)
	end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
	group = freshness_group,
	pattern = vim.fn.fnamemodify(DEEP_CONFIG, ":t"),

	callback = function(args)
		local file = canonical_path(vim.api.nvim_buf_get_name(args.buf))

		if file ~= canonical_path(DEEP_CONFIG) then
			return
		end

		-- Active-scan config integrity is checked by filesystem signature at
		-- commit time. Do not collapse a config change into the generic
		-- project-buffer mutation flag, otherwise the discard reason is wrong.
		if state.last.root and not state.last.stale then
			state.last.stale = true
			emit("stale")
		end
	end,
})

-- CMake integration is event-based so the build subsystem does not need to
-- require the analyzer directly. User events are the supported Neovim
-- mechanism for plugin-defined integration signals, and nvim_exec_autocmds()
-- can attach structured data to the callback.
vim.api.nvim_create_autocmd("User", {
	group = freshness_group,
	pattern = "DemirCompilationModelChanged",

	callback = function(args)
		local data = type(args.data) == "table" and args.data or {}
		local root = data.analysis_root

		if type(root) ~= "string" or root == "" then
			return
		end

		M.invalidate_compilation_model(root, data.database, data.reason)
	end,
})

-- ─────────────────────────────────────────────────────────────
-- User Commands
-- ─────────────────────────────────────────────────────────────

vim.api.nvim_create_user_command("DemirAnalyzeProject", function(args)
	local jobs = nil

	if args.args ~= "" then
		jobs = tonumber(args.args)

		if not jobs or jobs < 1 or jobs % 1 ~= 0 then
			notify("Worker count must be a positive integer.", vim.log.levels.ERROR)
			return
		end
	end

	M.run({
		jobs = jobs,
		save = args.bang,
		prompt_save = not args.bang,
	})
end, {
	nargs = "?",
	bang = true,
	desc = "Run deep clang-tidy analysis for the current C/C++ project",
})

vim.api.nvim_create_user_command("DemirCancelAnalysis", function()
	M.cancel()
end, {
	desc = "Cancel the active deep C++ analysis request",
})

vim.api.nvim_create_user_command("DemirClearAnalysis", function()
	M.clear()
end, {
	desc = "Clear committed deep-analysis results",
})

vim.api.nvim_create_user_command("DemirAnalysisStatus", function()
	vim.print(M.status())
end, {
	desc = "Show deep C++ analysis status",
})

return M
