local cmake = require("cmake-tools")
local buildsentry = require("buildsentry")
local project = require("demir.core.project")

-- ─────────────────────────────────────────────────────────────
-- CMake Tools
-- ─────────────────────────────────────────────────────────────

cmake.setup({
	cmake_command = "cmake",
	ctest_command = "ctest",

	-- Compiler, build type, generator and build directory are owned by
	-- CMakePresets.json / CMakeUserPresets.json.
	cmake_use_preset = true,

	-- Configure operations remain explicit and user-driven.
	cmake_regenerate_on_save = false,

	cmake_generate_options = {},
	cmake_build_options = {},

	-- ─────────────────────────────────────────────────────────
	-- Debug
	-- ─────────────────────────────────────────────────────────

	cmake_dap_configuration = {
		name = "C++ Debug",
		type = "gdb",
		request = "launch",

		stopAtBeginningOfMainSubprogram = false,
		stopOnEntry = false,
	},

	-- DemirVim owns the source-root compile_commands.json link.
	--
	-- cmake-tools' built-in soft-link mode is intentionally not used here:
	-- DemirVim refuses to overwrite a user-owned regular file and performs
	-- the link replacement only after a successful configure.
	cmake_compile_commands_options = {
		action = "none",
	},

	cmake_always_use_terminal = false,
})

-- ─────────────────────────────────────────────────────────────
-- BuildSentry
-- ─────────────────────────────────────────────────────────────

buildsentry.setup({
	attach_cmake_tools = true,
})

require("demir.build.buildsentry_time").setup()

-- ─────────────────────────────────────────────────────────────
-- Basic Helpers
-- ─────────────────────────────────────────────────────────────

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, {
		title = "CMake",
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

local function normal_file_buffer(buf)
	return type(buf) == "number"
		and vim.api.nvim_buf_is_valid(buf)
		and vim.api.nvim_buf_is_loaded(buf)
		and vim.bo[buf].buftype == ""
		and vim.api.nvim_buf_get_name(buf) ~= ""
end

-- Save only real, named file buffers. Plugin-owned nofile buffers, terminals,
-- help buffers, and other virtual surfaces must never participate in a build
-- save barrier.
local function save_all()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if normal_file_buffer(buf) and vim.bo[buf].modified then
			local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
				vim.cmd("silent keepalt write")
			end)

			if not ok then
				notify("Dosyalar kaydedilemedi:\n" .. tostring(err), vim.log.levels.ERROR)
				return false
			end
		end
	end

	return true
end

-- ─────────────────────────────────────────────────────────────
-- CMake Project Context
-- ─────────────────────────────────────────────────────────────

-- cmake-tools owns the CMake source directory in config.cwd. This is
-- deliberately different from DemirVim's analysis/repository root.
--
-- In particular, :CMakeSelectCwd can change config.cwd without changing
-- Neovim's process cwd, so vim.fn.getcwd() is not authoritative here.
local function cmake_source_root()
	local ok, config = pcall(cmake.get_config)

	if not ok or type(config) ~= "table" then
		notify("CMake proje durumu okunamadı.", vim.log.levels.ERROR)
		return nil
	end

	local root = canonical_path(config.cwd)

	if root == "" then
		notify("Aktif CMake kaynak dizini bulunamadı.", vim.log.levels.ERROR)
		return nil
	end

	local cmakelists = vim.fs.joinpath(root, "CMakeLists.txt")

	if not path_is_file(cmakelists) then
		notify("Aktif CMake kaynak dizininde CMakeLists.txt bulunamadı:\n" .. root, vim.log.levels.ERROR)
		return nil
	end

	return root
end

-- cmake-tools currently returns a Plenary Path object, but older/plugin-local
-- revisions may expose a string. Keep the adapter deliberately narrow.
local function get_build_directory_string()
	local ok, build_path = pcall(cmake.get_build_directory)

	if not ok or not build_path then
		return nil
	end

	if type(build_path) == "string" then
		return build_path
	end

	if type(build_path) == "table" then
		if type(build_path.filename) == "string" then
			return build_path.filename
		end

		if type(build_path.absolute) == "function" then
			local absolute_ok, absolute = pcall(build_path.absolute, build_path)

			if absolute_ok and type(absolute) == "string" then
				return absolute
			end
		end
	end

	return nil
end

local function active_build_directory(root, quiet)
	local build_dir = get_build_directory_string()

	if not build_dir or build_dir == "" then
		if not quiet then
			notify("Aktif CMake build dizini bulunamadı.", vim.log.levels.ERROR)
		end

		return nil
	end

	build_dir = vim.fs.abspath(build_dir, {
		cwd = root,
	})

	return canonical_path(build_dir)
end

-- ─────────────────────────────────────────────────────────────
-- Compilation Database
-- ─────────────────────────────────────────────────────────────

local function symlink_destination(path)
	local link = vim.uv.fs_readlink(path)

	if type(link) ~= "string" or link == "" then
		return nil
	end

	link = vim.fs.abspath(link, {
		cwd = vim.fs.dirname(path),
	})

	return canonical_path(link)
end

local function create_or_replace_symlink(source, target)
	source = canonical_path(source)
	target = normalize_path(target)

	if source == "" or target == "" then
		return false, false
	end

	-- An in-source build can legitimately place compile_commands.json directly
	-- at the CMake source root. No link is needed in that case.
	if normalize_path(source) == normalize_path(target) then
		return true, false
	end

	local target_stat = vim.uv.fs_lstat(target)

	if target_stat then
		if target_stat.type == "link" then
			if symlink_destination(target) == source then
				return true, false
			end
		else
			-- Never destroy a real file owned by the user or another tool.
			notify(
				"Proje kökündeki compile_commands.json normal bir dosya.\n"
					.. "DemirVim bu dosyanın üzerine yazmayacak:\n"
					.. target,
				vim.log.levels.ERROR
			)

			return false, false
		end
	end

	-- Replace links atomically: create the new link beside the destination,
	-- then rename it over the previous link. Readers see either the old valid
	-- link or the new valid link, never a missing half-updated path.
	local temp = string.format("%s.demirvim-tmp-%d-%s", target, vim.fn.getpid(), tostring(vim.uv.hrtime()))

	pcall(vim.uv.fs_unlink, temp)

	local linked, link_err = vim.uv.fs_symlink(source, temp)

	if not linked then
		notify(
			"Geçici compile_commands.json bağlantısı oluşturulamadı:\n" .. tostring(link_err),
			vim.log.levels.ERROR
		)

		return false, false
	end

	local renamed, rename_err = vim.uv.fs_rename(temp, target)

	if not renamed then
		pcall(vim.uv.fs_unlink, temp)

		notify(
			"compile_commands.json bağlantısı etkinleştirilemedi:\n" .. tostring(rename_err),
			vim.log.levels.ERROR
		)

		return false, false
	end

	return true, true
end

-- Synchronize the source-root compile_commands.json link with the build
-- directory selected by cmake-tools.
--
-- Returns:
--   ok      whether synchronization succeeded
--   changed whether the source-root link changed target
local function refresh_compile_commands()
	local root = cmake_source_root()

	if not root then
		return false, false, nil
	end

	local build_dir = active_build_directory(root)

	if not build_dir then
		return false, false, nil
	end

	local source = canonical_path(vim.fs.joinpath(build_dir, "compile_commands.json"))

	if not path_is_file(source) then
		notify("compile_commands.json bulunamadı:\n" .. source, vim.log.levels.ERROR)
		return false, false, nil
	end

	local target = vim.fs.joinpath(root, "compile_commands.json")
	local ok, changed = create_or_replace_symlink(source, target)

	if not ok then
		return false, false, nil
	end

	return true,
		changed,
		{
			cmake_root = root,
			analysis_root = project.analysis_root(root),
			build_dir = build_dir,
			database = source,
			target = normalize_path(target),
			signature = file_signature(source),
		}
end

local function current_compilation_model()
	local root = cmake_source_root()

	if not root then
		return nil
	end

	-- Observation must be side-effect free. It is valid for a project to have
	-- no selected/generated build directory yet; callers may be about to create
	-- one through generate/build.
	local build_dir = active_build_directory(root, true)

	if not build_dir then
		return nil
	end

	local database = canonical_path(vim.fs.joinpath(build_dir, "compile_commands.json"))

	if not path_is_file(database) then
		return {
			cmake_root = root,
			analysis_root = project.analysis_root(root),
			build_dir = build_dir,
			database = database,
			signature = nil,
		}
	end

	return {
		cmake_root = root,
		analysis_root = project.analysis_root(root),
		build_dir = build_dir,
		database = database,
		signature = file_signature(database),
	}
end

local function same_compilation_model(a, b)
	if not a or not b then
		return a == b
	end

	return a.analysis_root == b.analysis_root
		and a.cmake_root == b.cmake_root
		and a.database == b.database
		and a.signature == b.signature
end

local function emit_compilation_model_changed(model, reason)
	if not model or not model.analysis_root or model.analysis_root == "" then
		return
	end

	vim.api.nvim_exec_autocmds("User", {
		pattern = "DemirCompilationModelChanged",
		modeline = false,
		data = {
			analysis_root = model.analysis_root,
			cmake_root = model.cmake_root,
			build_dir = model.build_dir,
			database = model.database,
			reason = reason or "cmake",
		},
	})
end

local function restart_clangd()
	local clients = vim.lsp.get_clients({
		name = "clangd",
	})

	if #clients == 0 then
		return true
	end

	local ok, err = pcall(vim.cmd, "lsp restart clangd")

	if not ok then
		notify("clangd yeniden başlatılamadı:\n" .. tostring(err), vim.log.levels.WARN)
		return false
	end

	return true
end

-- Explicit configure operations are synchronization barriers. Even when the
-- link target did not change, CMake may have rewritten the database contents,
-- so clangd is restarted to make the newly configured model visible
-- immediately and deterministically.
local function synchronize_after_configure(before_model, reason)
	local ok, _, model = refresh_compile_commands()

	if not ok then
		return false
	end

	if not restart_clangd() then
		return false
	end

	if not same_compilation_model(before_model, model) then
		emit_compilation_model_changed(model, reason or "configure")
	end

	return true
end

local function preset_name()
	local preset = cmake.get_build_preset()

	if type(preset) == "string" then
		return preset
	end

	if type(preset) == "table" then
		return preset.name or preset.displayName or "Bilinmeyen"
	end

	return "Bilinmeyen"
end

-- ─────────────────────────────────────────────────────────────
-- Configure Orchestration
-- ─────────────────────────────────────────────────────────────

local function generate_and_sync(reason, on_success, before_model)
	if before_model == nil then
		before_model = current_compilation_model()
	end

	cmake.generate({
		bang = false,
		fargs = {},
	}, function(result)
		if not result:is_ok() then
			notify("CMake yapılandırması başarısız.", vim.log.levels.ERROR)
			return
		end

		if not synchronize_after_configure(before_model, reason) then
			return
		end

		if type(on_success) == "function" then
			on_success()
		end
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Build Profile
-- ─────────────────────────────────────────────────────────────

local function select_profile()
	if not save_all() then
		return
	end

	-- Capture the old model before the preset mutates cmake-tools state. If the
	-- target profile already has an existing database, observing only after the
	-- selection would lose the profile transition entirely.
	local before_model = current_compilation_model()

	cmake.select_build_preset(function(result)
		if not result:is_ok() then
			return
		end

		-- cmake-tools associates the selected build preset with its configure
		-- preset. Generate through the shared synchronization path so profile
		-- changes and manual configure have identical postconditions.
		generate_and_sync("CMake build profile changed", function()
			notify("Aktif derleme profili: " .. preset_name(), vim.log.levels.INFO)
		end, before_model)
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Configure
-- ─────────────────────────────────────────────────────────────

local function configure_project()
	if not save_all() then
		return
	end

	generate_and_sync("CMake configure changed the compilation model")
end

-- ─────────────────────────────────────────────────────────────
-- Build
-- ─────────────────────────────────────────────────────────────

local function build_project()
	if not save_all() then
		return
	end

	local before_model = current_compilation_model()

	cmake.build({
		bang = false,
		fargs = {},
	}, function(result)
		if not result:is_ok() then
			return
		end

		-- cmake.build() may configure automatically when no valid build model
		-- exists. Re-read the database after the build and publish a model-change
		-- event only when its identity actually changed.
		local ok, link_changed, model = refresh_compile_commands()

		if not ok then
			return
		end

		local model_changed = not same_compilation_model(before_model, model)

		if link_changed or model_changed then
			restart_clangd()
		end

		if model_changed then
			emit_compilation_model_changed(model, "CMake build changed the compilation model")
		end
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Run
-- ─────────────────────────────────────────────────────────────

local function run_project()
	if not save_all() then
		return
	end

	local before_model = current_compilation_model()

	-- If a valid database already exists, synchronize the source-root link
	-- before launch. cmake.run() may still configure/build internally; the
	-- completion callback performs a second synchronization for that path.
	if before_model and before_model.signature then
		local ok, link_changed = refresh_compile_commands()

		if ok and link_changed then
			restart_clangd()
		end
	end

	cmake.run({
		fargs = {},
	}, function()
		-- The runner callback may represent program exit rather than merely build
		-- completion, but it is still the first reliable public callback after
		-- cmake.run()'s optional configure/build chain. Reconcile the compilation
		-- model regardless of the executable's exit status.
		local ok, link_changed, model = refresh_compile_commands()

		if not ok then
			return
		end

		local model_changed = not same_compilation_model(before_model, model)

		if link_changed or model_changed then
			restart_clangd()
		end

		if model_changed then
			emit_compilation_model_changed(model, "CMake run changed the compilation model")
		end
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Keymaps
-- ─────────────────────────────────────────────────────────────

local map = vim.keymap.set

map("n", "<leader>b", function()
	buildsentry.open()
end, {
	desc = "Derleme merkezi",
})

map("n", "<leader>c", select_profile, {
	desc = "Derleme profili",
})

map({ "n", "i", "x" }, "<F6>", configure_project, {
	desc = "CMake yapılandır",
})

map({ "n", "i", "x" }, "<F7>", build_project, {
	desc = "Projeyi derle",
})

map({ "n", "i", "x" }, "<C-F5>", run_project, {
	desc = "Derle ve çalıştır",
})

map("n", "<leader>R", run_project, {
	desc = "Derle ve çalıştır",
})
