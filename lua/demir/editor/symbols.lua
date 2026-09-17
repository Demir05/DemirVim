local Snacks = require("snacks")
local workspace = require("demir.lsp.workspace")

local M = {}

local unpack_args = table.unpack or unpack
local pack_args = table.pack or function(...)
	return { n = select("#", ...), ... }
end

local ns = vim.api.nvim_create_namespace("DemirSymbolCenter")

-- ─────────────────────────────────────────────────────────────
-- Symbol Metadata
-- ─────────────────────────────────────────────────────────────
--
-- Burada yalnızca Neovim'in standart highlight gruplarını
-- kullanıyoruz.
--
-- Böylece Gruber Darker veya gelecekte başka bir colorscheme
-- kullansak bile tanımsız Tree-sitter capture adı yüzünden UI
-- bozulmaz.
-- ─────────────────────────────────────────────────────────────

local symbol_kinds = {
	[1] = {
		name = "File",
		icon = "󰈙",
		hl = "Directory",
		group = "other",
	},

	[2] = {
		name = "Module",
		icon = "󰏗",
		hl = "Identifier",
		group = "types",
	},

	[3] = {
		name = "Namespace",
		icon = "󰅩",
		hl = "Identifier",
		group = "types",
	},

	[4] = {
		name = "Package",
		icon = "󰏖",
		hl = "Directory",
		group = "types",
	},

	[5] = {
		name = "Class",
		icon = "󰠱",
		hl = "Type",
		group = "types",
	},

	[6] = {
		name = "Method",
		icon = "󰆧",
		hl = "Function",
		group = "callables",
	},

	[7] = {
		name = "Property",
		icon = "󰜢",
		hl = "Identifier",
		group = "data",
	},

	[8] = {
		name = "Field",
		icon = "󰜢",
		hl = "Identifier",
		group = "data",
	},

	[9] = {
		name = "Constructor",
		icon = "󰆧",
		hl = "Function",
		group = "callables",
	},

	[10] = {
		name = "Enum",
		icon = "󰦨",
		hl = "Type",
		group = "types",
	},

	[11] = {
		name = "Interface",
		icon = "󰜰",
		hl = "Type",
		group = "types",
	},

	[12] = {
		name = "Function",
		icon = "󰊕",
		hl = "Function",
		group = "callables",
	},

	[13] = {
		name = "Variable",
		icon = "󰀫",
		hl = "Identifier",
		group = "data",
	},

	[14] = {
		name = "Constant",
		icon = "󰏿",
		hl = "Constant",
		group = "data",
	},

	[15] = {
		name = "String",
		icon = "󰉾",
		hl = "String",
		group = "other",
	},

	[16] = {
		name = "Number",
		icon = "󰎠",
		hl = "Number",
		group = "other",
	},

	[17] = {
		name = "Boolean",
		icon = "󰨙",
		hl = "Boolean",
		group = "other",
	},

	[18] = {
		name = "Array",
		icon = "󰅪",
		hl = "Identifier",
		group = "data",
	},

	[19] = {
		name = "Object",
		icon = "󰅩",
		hl = "Type",
		group = "types",
	},

	[20] = {
		name = "Key",
		icon = "󰌆",
		hl = "Identifier",
		group = "data",
	},

	[21] = {
		name = "Null",
		icon = "󰟢",
		hl = "Constant",
		group = "other",
	},

	[22] = {
		name = "Enum Member",
		icon = "󰦨",
		hl = "Constant",
		group = "data",
	},

	[23] = {
		name = "Struct",
		icon = "󰙅",
		hl = "Type",
		group = "types",
	},

	[24] = {
		name = "Event",
		icon = "󱐋",
		hl = "Special",
		group = "other",
	},

	[25] = {
		name = "Operator",
		icon = "󰆕",
		hl = "Operator",
		group = "callables",
	},

	[26] = {
		name = "Type Parameter",
		icon = "󰗴",
		hl = "Type",
		group = "types",
	},
}

local fallback_kind = {
	name = "Symbol",
	icon = "󰘦",
	hl = "Identifier",
	group = "other",
}

local function kind_info(kind)
	return symbol_kinds[kind] or fallback_kind
end

-- ─────────────────────────────────────────────────────────────
-- Runtime State
-- ─────────────────────────────────────────────────────────────

local state = {
	open = false,
	closing = false,
	session_id = 0,

	mode = "document",
	kind_filter = "all",

	document_query = "",
	workspace_query = "",

	source_buf = nil,
	source_win = nil,
	source_file = nil,

	root = nil,
	roots = {},
	active_client_id = nil,

	document_nodes = {},
	workspace_nodes = {},

	visible = {},

	line_map = {},
	key_to_line = {},
	context_lines = {},

	collapsed = {},

	loading = false,

	pending_requests = {},
	request_generation = 0,

	initial_cursor = nil,
	initial_selection_done = false,

	preview_file = nil,
	preview_token = nil,

	bufs = {},
	wins = {},

	augroup = nil,
}

-- ─────────────────────────────────────────────────────────────
-- Basic Helpers
-- ─────────────────────────────────────────────────────────────

local function valid_buf(buf)
	return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

local function loaded_buf(buf)
	return valid_buf(buf) and vim.api.nvim_buf_is_loaded(buf)
end

local function valid_win(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function normalize_path(path)
	if not path or path == "" then
		return ""
	end

	return vim.fs.normalize(path)
end

local function one_line(text)
	return tostring(text or ""):gsub("\r", " "):gsub("\n", " "):gsub("%s+", " ")
end

local function uri_to_file(uri)
	if type(uri) ~= "string" or not uri:match("^file:") then
		return nil
	end

	local ok, file = pcall(vim.uri_to_fname, uri)

	if not ok or not file or file == "" then
		return nil
	end

	return normalize_path(file)
end

local function relative_file(file)
	file = normalize_path(file)

	if file == "" then
		return ""
	end

	-- Fast path for the overwhelmingly common non-symlink case. Workspace
	-- roots are already normalized/canonicalized by demir.lsp.workspace.
	for _, root in ipairs(state.roots or {}) do
		local relative = vim.fs.relpath(root, file)

		if relative then
			return relative == "." and vim.fs.basename(file) or relative
		end
	end

	-- Resolve symlink aliases only when lexical containment failed.
	local relative = workspace.relative_path(state.roots, file)

	if relative then
		return relative == "." and vim.fs.basename(file) or relative
	end

	return vim.fs.basename(file)
end

local function inside_project(file)
	file = normalize_path(file)

	if file == "" then
		return false
	end

	for _, root in ipairs(state.roots or {}) do
		if file == root or vim.fs.relpath(root, file) ~= nil then
			return true
		end
	end

	-- Slow path handles a source/result path that reaches the same physical
	-- workspace through a different symlink spelling.
	for _, root in ipairs(state.roots or {}) do
		if workspace.path_in_root(root, file) then
			return true
		end
	end

	return false
end

local function report_internal_error(context, err)
	vim.schedule(function()
		vim.notify_once(
			string.format("%s: %s", context, tostring(err)),
			vim.log.levels.WARN,
			{ title = "Symbol Center" }
		)
	end)
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

local function set_lines(buf, lines)
	if not valid_buf(buf) then
		return
	end

	vim.bo[buf].modifiable = true

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	vim.bo[buf].modifiable = false
end

-- ─────────────────────────────────────────────────────────────
-- Safe Extmarks
-- ─────────────────────────────────────────────────────────────
--
-- UI decoration hiçbir durumda Symbol Center'ı çökertecek kadar
-- önemli değildir.
--
-- Bütün satır/kolon değerleri gerçek buffer sınırlarına clamp
-- edilir ve extmark strict=false kullanır.
-- ─────────────────────────────────────────────────────────────

local function safe_extmark(buf, row, col, opts)
	if not valid_buf(buf) then
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

	if opts.end_col ~= nil then
		if opts.end_col < 0 then
			opts.end_col = #text
		else
			opts.end_col = math.max(col, math.min(opts.end_col, #text))
		end
	end

	opts.strict = false

	local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, col, opts)

	if not ok then
		report_internal_error("Extmark oluşturulamadı", id)
		return nil
	end

	return id
end

local function highlight_literal(buf, row, text, needle, hl)
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

	safe_extmark(buf, row, start_col, {
		end_col = end_col,
		hl_group = hl,
	})
end

-- ─────────────────────────────────────────────────────────────
-- LSP Position Conversion
-- ─────────────────────────────────────────────────────────────
--
-- LSP Position.character client.offset_encoding kullanır.
-- Neovim cursor/extmark sütunları byte offset kullanır.
-- Range.end LSP'de exclusive'dir.
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

local function buffer_lsp_col(buf, position, encoding)
	if not loaded_buf(buf) or not position then
		return 0
	end

	local line_count = vim.api.nvim_buf_line_count(buf)
	local requested_line = math.max(0, position.line or 0)

	-- LSP range uçları EOF satırının hemen sonunu gösterebilir. Range
	-- karşılaştırmasında satırı son gerçek satıra clamp etmek semantiği
	-- değiştirirdi; böyle bir sanal EOF pozisyonunun byte sütunu 0'dır.
	if line_count <= 0 or requested_line >= line_count then
		return 0
	end

	local text = vim.api.nvim_buf_get_lines(buf, requested_line, requested_line + 1, false)[1] or ""
	return lsp_character_to_byte(text, position.character, encoding)
end

local function buffer_lsp_position(buf, position, encoding)
	if not loaded_buf(buf) or not position then
		return 0, 0
	end

	local line_count = vim.api.nvim_buf_line_count(buf)

	if line_count <= 0 then
		return 0, 0
	end

	local line = math.max(0, math.min(position.line or 0, line_count - 1))
	local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
	local col = lsp_character_to_byte(text, position.character, encoding)

	return line, col
end

local function position_before(a_line, a_col, b_line, b_col)
	if a_line ~= b_line then
		return a_line < b_line
	end

	return a_col < b_col
end

local function position_before_or_equal(a_line, a_col, b_line, b_col)
	return a_line == b_line and a_col == b_col or position_before(a_line, a_col, b_line, b_col)
end

local function node_contains_position(node, line, col)
	if not node or not node.range or not loaded_buf(state.source_buf) then
		return false
	end

	local start = node.range.start
	local finish = node.range["end"]

	if not start or not finish then
		return false
	end

	local start_col = buffer_lsp_col(state.source_buf, start, node.encoding)
	local finish_col = buffer_lsp_col(state.source_buf, finish, node.encoding)

	return position_before_or_equal(start.line or 0, start_col, line, col)
		and position_before(line, col, finish.line or 0, finish_col)
end

local function loaded_buffer_for_file(file, preferred_buf)
	file = normalize_path(file)

	if file == "" then
		return nil
	end

	if loaded_buf(preferred_buf) then
		local preferred_name = normalize_path(vim.api.nvim_buf_get_name(preferred_buf))

		if preferred_name == file
			or workspace.canonical_path(preferred_name) == workspace.canonical_path(file)
		then
			return preferred_buf
		end
	end

	local candidate = vim.fn.bufnr(file)

	if candidate > 0 and loaded_buf(candidate) then
		return candidate
	end

	local target = workspace.canonical_path(file)

	if target == "" then
		return nil
	end

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if loaded_buf(buf) then
			local name = normalize_path(vim.api.nvim_buf_get_name(buf))

			if name ~= "" and workspace.canonical_path(name) == target then
				return buf
			end
		end
	end

	return nil
end

local function source_descriptor(node)
	local file = normalize_path(node and node.file or "")

	if file == "" then
		return nil
	end

	local buf = loaded_buffer_for_file(file, node.buf)

	if buf then
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

local function read_source_lines(descriptor)
	if not descriptor then
		return nil
	end

	if loaded_buf(descriptor.buf) then
		return vim.api.nvim_buf_get_lines(descriptor.buf, 0, -1, false)
	end

	local ok, lines = pcall(vim.fn.readfile, descriptor.file)

	if not ok then
		report_internal_error("Preview dosyası okunamadı", lines)
		return nil
	end

	if #lines == 0 then
		return { "" }
	end

	return lines
end

-- ─────────────────────────────────────────────────────────────
-- LSP Client Helpers
-- ─────────────────────────────────────────────────────────────

local function preferred_client_for_buffer(buf, method)
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

local function preferred_client(method)
	if not state.source_buf then
		return nil
	end

	if state.active_client_id then
		local active = vim.lsp.get_client_by_id(state.active_client_id)

		if
			active
			and vim.lsp.buf_is_attached(state.source_buf, active.id)
			and active:supports_method(method, state.source_buf)
		then
			return active
		end
	end

	return preferred_client_for_buffer(state.source_buf, method)
end

local function set_project_roots(client)
	state.root, state.roots = workspace.collect_roots(client, state.source_file)
end

local function cancel_requests()
	for _, request in ipairs(state.pending_requests) do
		if request.client and request.id then
			pcall(request.client.cancel_request, request.client, request.id)
		end
	end

	state.pending_requests = {}
end

local function track_request(client, request_id)
	if client and request_id then
		table.insert(state.pending_requests, {
			client = client,
			id = request_id,
		})
	end
end

local function untrack_request(client, request_id)
	for index = #state.pending_requests, 1, -1 do
		local request = state.pending_requests[index]

		if request.client == client and request.id == request_id then
			table.remove(state.pending_requests, index)
			return
		end
	end
end

local function request_from_client(client, method, params, handler)
	if not client or not state.source_buf or not valid_buf(state.source_buf) then
		return false
	end

	if client.is_stopped and client:is_stopped() then
		return false
	end

	local completed = false
	local request_id = nil

	local function wrapped_handler(...)
		completed = true

		if request_id then
			untrack_request(client, request_id)
		end

		local args = pack_args(...)
		local ok, err = xpcall(function()
			handler(unpack_args(args, 1, args.n))
		end, debug.traceback)

		if not ok then
			report_internal_error("LSP symbol callback'i başarısız", err)
		end
	end

	local call_ok, status, id = pcall(
		client.request,
		client,
		method,
		params,
		wrapped_handler,
		state.source_buf
	)

	if not call_ok then
		report_internal_error("LSP symbol isteği gönderilirken hata oluştu", status)
		return false
	end

	request_id = id

	if status ~= true then
		return false
	end

	-- Normal RPC yanıtı asenkrondur. In-process/test client callback'i request()
	-- dönmeden çalıştırırsa tamamlanmış request'i pending listesine geri ekleme.
	if not completed then
		if not request_id then
			return false
		end

		track_request(client, request_id)
	end

	return true
end

-- ─────────────────────────────────────────────────────────────
-- Document Symbol Normalization
-- ─────────────────────────────────────────────────────────────

local function normalize_document_symbol(symbol, depth, key, parent_path, encoding)
	if type(symbol) ~= "table" then
		return nil
	end

	local location = type(symbol.location) == "table" and symbol.location or nil

	local file = state.source_file

	local range = symbol.range

	local selection_range = symbol.selectionRange

	if location then
		if location.uri then
			file = uri_to_file(location.uri) or file
		end

		if location.range then
			range = location.range

			selection_range = location.range
		end
	end

	range = range or selection_range

	selection_range = selection_range or range

	if not range or not selection_range then
		return nil
	end

	file = normalize_path(file)

	local path = {}

	for _, part in ipairs(parent_path or {}) do
		table.insert(path, part)
	end

	table.insert(path, symbol.name or "<anonymous>")

	local node_buf = nil

	if file == state.source_file then
		node_buf = state.source_buf
	end

	local node = {
		name = symbol.name or "<anonymous>",

		detail = one_line(symbol.detail or symbol.containerName or ""),

		kind = symbol.kind,

		file = file,

		buf = node_buf,

		encoding = encoding or "utf-16",

		range = range,

		selection_range = selection_range,

		depth = depth,

		key = key,

		path = path,

		children = {},
	}

	local children = type(symbol.children) == "table" and symbol.children or {}

	for index, child in ipairs(children) do
		local normalized = normalize_document_symbol(child, depth + 1, key .. "." .. index, path, encoding)

		if normalized then
			table.insert(node.children, normalized)
		end
	end

	return node
end

local function normalize_document_result(result, encoding)
	local nodes = {}

	local symbols = type(result) == "table" and result or {}

	for index, symbol in ipairs(symbols) do
		local node = normalize_document_symbol(symbol, 0, tostring(index), {}, encoding)

		if node then
			table.insert(nodes, node)
		end
	end

	return nodes
end

-- ─────────────────────────────────────────────────────────────
-- Workspace Symbol Normalization
-- ─────────────────────────────────────────────────────────────

local function workspace_node_from_symbol(symbol, index, encoding, seen)
	if type(symbol) ~= "table" then
		return nil
	end

	local location = type(symbol.location) == "table" and symbol.location or nil
	local uri = location and location.uri
	local range = location and location.range

	if not uri or not range or not range.start then
		return nil
	end

	local file = uri_to_file(uri)

	if not file or not inside_project(file) then
		return nil
	end

	local key = table.concat({
		file,
		tostring(range.start.line or 0),
		tostring(range.start.character or 0),
		tostring(symbol.kind),
		symbol.name or "",
	}, ":")

	if seen and seen[key] then
		return nil
	end

	if seen then
		seen[key] = true
	end

	local path = {}

	if symbol.containerName and symbol.containerName ~= "" then
		table.insert(path, symbol.containerName)
	end

	table.insert(path, symbol.name or "<anonymous>")

	return {
		name = symbol.name or "<anonymous>",
		detail = one_line(symbol.containerName or symbol.detail or ""),
		kind = symbol.kind,
		file = file,
		buf = file == state.source_file and state.source_buf or nil,
		encoding = encoding or "utf-16",
		range = range,
		selection_range = range,
		depth = 0,
		key = "workspace:" .. tostring(index) .. ":" .. key,
		path = path,
		children = {},
	}
end

local function sort_workspace_nodes(nodes)
	table.sort(nodes, function(a, b)
		if a.name ~= b.name then
			return a.name < b.name
		end

		if a.file ~= b.file then
			return a.file < b.file
		end

		return a.selection_range.start.line < b.selection_range.start.line
	end)
end

local function normalize_workspace_result(result, encoding)
	local nodes = {}
	local seen = {}

	local symbols = type(result) == "table" and result or {}

	for index, symbol in ipairs(symbols) do
		local node = workspace_node_from_symbol(symbol, index, encoding, seen)

		if node then
			table.insert(nodes, node)
		end
	end

	sort_workspace_nodes(nodes)

	return nodes
end

-- ─────────────────────────────────────────────────────────────
-- Forward Declaration
-- ─────────────────────────────────────────────────────────────

local refresh

-- ─────────────────────────────────────────────────────────────
-- Symbol Requests
-- ─────────────────────────────────────────────────────────────

local function finish_request_error(message, err)
	state.pending_requests = {}
	state.loading = false

	if refresh then
		refresh()
	end

	local text = message

	if err then
		text = string.format("%s: %s", message, one_line(type(err) == "table" and err.message or err))
	end

	vim.notify(text, vim.log.levels.WARN, {
		title = "Symbol Center",
	})
end

local function request_document_symbols()
	cancel_requests()

	state.mode = "document"
	state.loading = true
	state.request_generation = state.request_generation + 1

	local generation = state.request_generation
	local client = preferred_client("textDocument/documentSymbol")

	if not client then
		state.loading = false
		state.document_nodes = {}

		if refresh then
			refresh()
		end

		vim.notify("Bu buffer için documentSymbol destekleyen LSP bulunamadı.", vim.log.levels.WARN, {
			title = "Symbol Center",
		})

		return
	end

	state.active_client_id = client.id
	set_project_roots(client)

	local params = {
		textDocument = {
			uri = vim.uri_from_bufnr(state.source_buf),
		},
	}

	local ok = request_from_client(client, "textDocument/documentSymbol", params, function(err, result)
		if not state.open or generation ~= state.request_generation then
			return
		end

		if err then
			state.document_nodes = {}
			finish_request_error("Document symbols alınamadı", err)
			return
		end

		state.pending_requests = {}
		state.loading = false
		state.document_nodes = normalize_document_result(result or {}, client.offset_encoding or "utf-16")

		vim.schedule(function()
			if state.open and generation == state.request_generation and refresh then
				refresh()
			end
		end)
	end)

	if not ok then
		state.document_nodes = {}
		finish_request_error("Document symbols isteği gönderilemedi")
		return
	end

	if refresh then
		refresh()
	end
end

local function request_workspace_symbols(query)
	cancel_requests()

	state.mode = "workspace"
	state.workspace_query = query or ""
	state.loading = true
	state.request_generation = state.request_generation + 1

	local generation = state.request_generation
	local client = preferred_client("workspace/symbol")

	if not client then
		state.loading = false
		state.workspace_nodes = {}

		if refresh then
			refresh()
		end

		vim.notify("Bu proje için workspace/symbol destekleyen LSP bulunamadı.", vim.log.levels.WARN, {
			title = "Symbol Center",
		})

		return
	end

	state.active_client_id = client.id
	set_project_roots(client)

	local ok = request_from_client(client, "workspace/symbol", {
		query = query or "",
	}, function(err, result)
		if not state.open or generation ~= state.request_generation then
			return
		end

		if err then
			state.workspace_nodes = {}
			finish_request_error("Workspace symbols alınamadı", err)
			return
		end

		state.pending_requests = {}

		local encoding = client.offset_encoding or "utf-16"
		local nodes = {}
		local seen = {}
		local unresolved = {}

		local symbols = type(result) == "table" and result or {}

		for index, symbol in ipairs(symbols) do
			local location = type(symbol) == "table" and symbol.location or nil

			if location and location.uri and location.range then
				local node = workspace_node_from_symbol(symbol, index, encoding, seen)

				if node then
					table.insert(nodes, node)
				end
			elseif location and location.uri then
				local file = uri_to_file(location.uri)

				if file and inside_project(file) then
					table.insert(unresolved, {
						index = index,
						symbol = symbol,
					})
				end
			end
		end

		local provider = client.server_capabilities and client.server_capabilities.workspaceSymbolProvider
		local can_resolve = type(provider) == "table" and provider.resolveProvider == true

		local function finalize()
			if not state.open or generation ~= state.request_generation then
				return
			end

			state.pending_requests = {}
			sort_workspace_nodes(nodes)
			state.workspace_nodes = nodes
			state.loading = false

			vim.schedule(function()
				if state.open and generation == state.request_generation and refresh then
					refresh()
				end
			end)
		end

		if #unresolved == 0 or not can_resolve then
			finalize()
			return
		end

		local remaining = #unresolved

		local function resolved_one()
			remaining = remaining - 1

			if remaining == 0 then
				finalize()
			end
		end

		for _, item in ipairs(unresolved) do
			local symbol_to_resolve = item.symbol
			local symbol_index = item.index
			local sent = request_from_client(
				client,
				"workspaceSymbol/resolve",
				symbol_to_resolve,
				function(resolve_err, resolved)
					if not state.open or generation ~= state.request_generation then
						return
					end

					if not resolve_err and resolved then
						local node = workspace_node_from_symbol(resolved, symbol_index, encoding, seen)

						if node then
							table.insert(nodes, node)
						end
					end

					resolved_one()
				end
			)

			if not sent then
				resolved_one()
			end
		end
	end)

	if not ok then
		state.workspace_nodes = {}
		finish_request_error("Workspace symbol isteği gönderilemedi")
		return
	end

	if refresh then
		refresh()
	end
end

-- ─────────────────────────────────────────────────────────────
-- Filtering
-- ─────────────────────────────────────────────────────────────

local function matches_kind(node)
	if state.kind_filter == "all" then
		return true
	end

	return kind_info(node.kind).group == state.kind_filter
end

local function document_matches_query(node)
	local query = vim.trim(state.document_query):lower()

	if query == "" then
		return true
	end

	local haystack = table
		.concat({
			node.name,
			node.detail,
			table.concat(node.path, " "),
		}, " ")
		:lower()

	return haystack:find(query, 1, true) ~= nil
end

local function document_node_matches(node)
	return matches_kind(node) and document_matches_query(node)
end

local function subtree_matches(node)
	if document_node_matches(node) then
		return true
	end

	for _, child in ipairs(node.children or {}) do
		if subtree_matches(child) then
			return true
		end
	end

	return false
end

local function flatten_document(nodes, output)
	for _, node in ipairs(nodes) do
		if subtree_matches(node) then
			local direct_match = document_node_matches(node)

			table.insert(output, {
				node = node,
				context = not direct_match,
			})

			local collapsed = state.collapsed[node.key]

			-- Search aktifken eşleşen alt dalları gizleme.
			if not collapsed or state.document_query ~= "" then
				flatten_document(node.children, output)
			end
		end
	end
end

local function calculate_visible()
	local output = {}

	if state.mode == "document" then
		flatten_document(state.document_nodes, output)
	else
		for _, node in ipairs(state.workspace_nodes) do
			if matches_kind(node) then
				table.insert(output, {
					node = node,
					context = false,
				})
			end
		end
	end

	state.visible = output
end

-- ─────────────────────────────────────────────────────────────
-- Counts
-- ─────────────────────────────────────────────────────────────

local function count_nodes(nodes)
	local counts = {
		all = 0,
		types = 0,
		callables = 0,
		data = 0,
	}

	local function visit(node)
		counts.all = counts.all + 1

		local group = kind_info(node.kind).group

		if counts[group] ~= nil then
			counts[group] = counts[group] + 1
		end

		for _, child in ipairs(node.children or {}) do
			visit(child)
		end
	end

	for _, node in ipairs(nodes or {}) do
		visit(node)
	end

	return counts
end

local function current_counts()
	if state.mode == "document" then
		return count_nodes(state.document_nodes)
	end

	return count_nodes(state.workspace_nodes)
end

-- ─────────────────────────────────────────────────────────────
-- Geometry
-- ─────────────────────────────────────────────────────────────

local function geometry()
	local columns = math.max(1, vim.o.columns)
	local screen_lines = math.max(1, vim.o.lines - vim.o.cmdheight)

	if columns < 44 or screen_lines < 14 then
		return nil, string.format("Terminal çok küçük (%dx%d). En az 44x14 gerekir.", columns, screen_lines)
	end

	local margin_x = columns >= 70 and 2 or 1
	local margin_y = screen_lines >= 20 and 1 or 0

	-- frame_* bütün rounded border'lar dahil ekranda kaplanan zarfı ifade eder.
	-- nvim_open_win width/height ise yalnız içerik hücrelerini sayar.
	local max_frame_width = columns - (margin_x * 2)
	local max_frame_height = screen_lines - (margin_y * 2)
	local frame_width = math.min(max_frame_width, math.max(44, math.floor(columns * 0.94)))
	local frame_height = math.min(max_frame_height, math.max(14, math.floor(screen_lines * 0.86)))

	local horizontal_gap = frame_width >= 70 and 1 or 0
	local vertical_gap = frame_height >= 20 and 1 or 0
	local border_width = 2
	local border_height = 2

	local header_height = frame_height >= 18 and 3 or 2
	local footer_height = frame_height >= 17 and 2 or 1

	local reserved_height = header_height + footer_height + (border_height * 3) + (vertical_gap * 2)
	local body_height = frame_height - reserved_height

	if body_height < 1 then
		return nil, "Terminal yüksekliği Symbol Center yerleşimi için yetersiz."
	end

	local body_content_width = frame_width - horizontal_gap - (border_width * 2)

	if body_content_width < 2 then
		return nil, "Terminal genişliği Symbol Center yerleşimi için yetersiz."
	end

	local left_width = math.max(1, math.floor(body_content_width * 0.40))
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

local function float_config(row, col, width, height, title, focusable)
	return {
		relative = "editor",
		row = math.max(0, row),
		col = math.max(0, col),
		width = math.max(1, width),
		height = math.max(1, height),
		style = "minimal",
		border = "rounded",
		title = title,
		title_pos = "center",
		focusable = focusable ~= false,
		zindex = 60,
	}
end

-- ─────────────────────────────────────────────────────────────
-- Selected Symbol
-- ─────────────────────────────────────────────────────────────

local function selected_node()
	if not valid_win(state.wins.list) then
		return nil
	end

	local line = vim.api.nvim_win_get_cursor(state.wins.list)[1]

	if state.line_map[line] then
		return state.line_map[line]
	end

	for offset = 1, 30 do
		local down = state.line_map[line + offset]

		if down then
			return down
		end

		local up = state.line_map[line - offset]

		if up then
			return up
		end
	end

	return nil
end

local function selected_key()
	local node = selected_node()

	return node and node.key or nil
end

-- ─────────────────────────────────────────────────────────────
-- Header
-- ─────────────────────────────────────────────────────────────

local function render_header()
	if not valid_buf(state.bufs.header) then
		return
	end

	local counts = current_counts()

	local project = state.root and vim.fs.basename(state.root) or vim.fs.basename(state.source_file or "workspace")

	local method = state.mode == "document" and "textDocument/documentSymbol" or "workspace/symbol"

	local client = preferred_client(method)

	local client_name = client and client.name or "LSP"

	local first = string.format("  󰘦  SYMBOL CENTER     󰉋 %s     󰒋 %s", project, client_name)

	local second = string.format(
		"  [D] DOCUMENT   [P] PROJECT     [A] ALL %d   [T] TYPES %d   [F] CALLABLES %d   [V] DATA %d",
		counts.all,
		counts.types,
		counts.callables,
		counts.data
	)

	local third

	if state.loading then
		third = "  󰔟  Loading semantic symbols..."
	else
		local node = selected_node()

		if node then
			local info = kind_info(node.kind)

			local start = node.selection_range and node.selection_range.start or { line = 0 }
			local location = string.format("%s:%d", relative_file(node.file), (start.line or 0) + 1)

			local path = table.concat(node.path, "  ›  ")

			third = string.format("  %s  %s     %s     %s", info.icon, path, info.name, location)
		else
			third = "  No symbol selected"
		end
	end

	set_lines(state.bufs.header, {
		first,
		second,
		third,
	})

	vim.api.nvim_buf_clear_namespace(state.bufs.header, ns, 0, -1)

	highlight_literal(state.bufs.header, 0, first, "SYMBOL CENTER", "Title")

	highlight_literal(state.bufs.header, 0, first, client_name, "DiagnosticInfo")

	highlight_literal(state.bufs.header, 1, second, "[D] DOCUMENT", state.mode == "document" and "Visual" or "Comment")

	highlight_literal(state.bufs.header, 1, second, "[P] PROJECT", state.mode == "workspace" and "Visual" or "Comment")

	local filters = {
		{
			text = string.format("[A] ALL %d", counts.all),
			mode = "all",
			hl = "Identifier",
		},

		{
			text = string.format("[T] TYPES %d", counts.types),
			mode = "types",
			hl = "Type",
		},

		{
			text = string.format("[F] CALLABLES %d", counts.callables),
			mode = "callables",
			hl = "Function",
		},

		{
			text = string.format("[V] DATA %d", counts.data),
			mode = "data",
			hl = "Identifier",
		},
	}

	for _, filter in ipairs(filters) do
		highlight_literal(
			state.bufs.header,
			1,
			second,
			filter.text,
			state.kind_filter == filter.mode and "Visual" or filter.hl
		)
	end
end

-- ─────────────────────────────────────────────────────────────
-- List
-- ─────────────────────────────────────────────────────────────

local function render_list(preferred_key)
	if not valid_buf(state.bufs.list) then
		return
	end

	calculate_visible()

	state.line_map = {}
	state.key_to_line = {}
	state.context_lines = {}

	local lines = {}

	if state.loading then
		set_lines(state.bufs.list, {
			"",
			"   󰔟  Loading semantic symbols...",
		})

		return
	end

	if #state.visible == 0 then
		local message

		if state.mode == "workspace" and state.workspace_query == "" then
			message = "   󰘦  Press / to search project symbols"
		else
			message = "   󰄬  No matching symbols"
		end

		set_lines(state.bufs.list, {
			"",
			message,
			"",
			"   D  Document symbols",
			"   P  Project symbols",
			"   /  Search",
		})

		return
	end

	for _, view in ipairs(state.visible) do
		local node = view.node

		local info = kind_info(node.kind)

		if state.mode == "document" then
			local indent = string.rep("  ", node.depth)

			local branch = " "

			if #node.children > 0 then
				branch = state.collapsed[node.key] and "▸" or "▾"
			end

			local text = string.format("  %s%s %s  %s", indent, branch, info.icon, node.name)

			if node.detail ~= "" then
				text = text .. "  " .. node.detail
			end

			table.insert(lines, text)

			local line = #lines

			state.line_map[line] = node

			if not state.key_to_line[node.key] then
				state.key_to_line[node.key] = line
			end

			if view.context then
				state.context_lines[line] = true
			end
		else
			local text = string.format("  %s  %s", info.icon, node.name)

			table.insert(lines, text)

			local symbol_line = #lines

			state.line_map[symbol_line] = node

			state.key_to_line[node.key] = symbol_line

			local context = node.detail ~= "" and (node.detail .. "  ·  ") or ""

			local detail =
				string.format("      %s%s:%d", context, relative_file(node.file), node.selection_range.start.line + 1)

			table.insert(lines, detail)

			state.line_map[#lines] = node
		end
	end

	set_lines(state.bufs.list, lines)

	vim.api.nvim_buf_clear_namespace(state.bufs.list, ns, 0, -1)

	for line, node in pairs(state.line_map) do
		local info = kind_info(node.kind)

		local text = lines[line] or ""

		if state.context_lines[line] then
			safe_extmark(state.bufs.list, line - 1, 0, {
				end_col = #text,
				hl_group = "Comment",
			})
		end

		local icon_start = text:find(info.icon, 1, true)

		if icon_start then
			local start_col = icon_start - 1

			local end_col = math.min(start_col + #info.icon, #text)

			if end_col > start_col then
				safe_extmark(state.bufs.list, line - 1, start_col, {
					end_col = end_col,

					hl_group = info.hl,
				})
			end
		end
	end

	if not valid_win(state.wins.list) then
		return
	end

	if preferred_key and state.key_to_line[preferred_key] then
		pcall(vim.api.nvim_win_set_cursor, state.wins.list, {
			state.key_to_line[preferred_key],
			0,
		})

		return
	end

	for line = 1, #lines do
		if state.line_map[line] then
			pcall(vim.api.nvim_win_set_cursor, state.wins.list, {
				line,
				0,
			})

			break
		end
	end
end

-- ─────────────────────────────────────────────────────────────
-- Current Symbol Auto Selection
-- ─────────────────────────────────────────────────────────────

local function select_current_symbol()
	if
		state.initial_selection_done
		or state.mode ~= "document"
		or not state.initial_cursor
		or not valid_win(state.wins.list)
	then
		return
	end

	local source_line = state.initial_cursor[1] - 1

	local source_col = state.initial_cursor[2]

	local best_line = nil
	local best_depth = -1

	for line, node in pairs(state.line_map) do
		if node_contains_position(node, source_line, source_col) and node.depth > best_depth then
			best_line = line
			best_depth = node.depth
		end
	end

	if best_line then
		pcall(vim.api.nvim_win_set_cursor, state.wins.list, {
			best_line,
			0,
		})
	end

	state.initial_selection_done = true
end

-- ─────────────────────────────────────────────────────────────
-- Source Preview
-- ─────────────────────────────────────────────────────────────

local function render_preview()
	if not valid_buf(state.bufs.preview) then
		return
	end

	local node = selected_node()

	if not node then
		set_lines(state.bufs.preview, {
			"",
			"  Select a symbol to preview it.",
		})

		state.preview_file = nil
		state.preview_token = nil
		render_header()
		return
	end

	local descriptor = source_descriptor(node)

	if not descriptor then
		set_lines(state.bufs.preview, {
			"",
			"  Source preview is unavailable for this symbol.",
		})

		state.preview_file = nil
		state.preview_token = nil
		render_header()
		return
	end

	local needs_copy = state.preview_file ~= descriptor.file or state.preview_token ~= descriptor.token

	if needs_copy then
		local source_lines = read_source_lines(descriptor)

		if not source_lines then
			set_lines(state.bufs.preview, {
				"",
				"  Source preview could not be loaded.",
			})

			state.preview_file = nil
			state.preview_token = nil
			render_header()
			return
		end

		set_lines(state.bufs.preview, source_lines)

		local file_changed = state.preview_file ~= descriptor.file

		if file_changed then
			pcall(vim.treesitter.stop, state.bufs.preview)

			vim.bo[state.bufs.preview].filetype = descriptor.ft

			if descriptor.ft ~= "" then
				pcall(vim.treesitter.start, state.bufs.preview, descriptor.ft)
			end
		end

		state.preview_file = descriptor.file
		state.preview_token = descriptor.token
	end

	local position = node.selection_range and node.selection_range.start

	if not position then
		return
	end

	local line, col = buffer_lsp_position(state.bufs.preview, position, node.encoding)

	vim.api.nvim_buf_clear_namespace(state.bufs.preview, ns, 0, -1)

	local info = kind_info(node.kind)

	safe_extmark(state.bufs.preview, line, col, {
		line_hl_group = "CursorLine",
		virt_text = {
			{
				string.format(" %s %s ", info.icon, info.name),
				info.hl,
			},
		},
		virt_text_pos = "right_align",
	})

	if valid_win(state.wins.preview) then
		pcall(vim.api.nvim_win_set_cursor, state.wins.preview, {
			line + 1,
			col,
		})

		pcall(vim.api.nvim_win_call, state.wins.preview, function()
			vim.cmd("normal! zz")
		end)
	end

	render_header()
end

-- ─────────────────────────────────────────────────────────────
-- Footer
-- ─────────────────────────────────────────────────────────────

local function render_footer()
	if not valid_buf(state.bufs.footer) then
		return
	end

	local first = "  D Document   P Project   A All   T Types   F Callables   V Data   / Search   za Fold"

	local second = "  ↵ Open   R References   N Rename   K Hover   r Refresh   ? Help   q Close"

	set_lines(state.bufs.footer, {
		first,
		second,
	})

	vim.api.nvim_buf_clear_namespace(state.bufs.footer, ns, 0, -1)

	highlight_literal(state.bufs.footer, 0, first, "D Document", "DiagnosticInfo")

	highlight_literal(state.bufs.footer, 0, first, "P Project", "DiagnosticInfo")

	highlight_literal(state.bufs.footer, 0, first, "T Types", "Type")

	highlight_literal(state.bufs.footer, 0, first, "F Callables", "Function")

	highlight_literal(state.bufs.footer, 1, second, "R References", "DiagnosticInfo")

	highlight_literal(state.bufs.footer, 1, second, "N Rename", "DiagnosticWarn")
end

-- ─────────────────────────────────────────────────────────────
-- Full Refresh
-- ─────────────────────────────────────────────────────────────

refresh = function()
	if not state.open then
		return
	end

	local previous_key = selected_key()

	render_list(previous_key)

	select_current_symbol()

	render_preview()
	render_header()
	render_footer()
end

function M._refresh()
	refresh()
end

-- ─────────────────────────────────────────────────────────────
-- Search
-- ─────────────────────────────────────────────────────────────

local function search_symbols()
	if state.mode == "document" then
		vim.ui.input({
			prompt = "󰘦 Search document symbols: ",

			default = state.document_query,
		}, function(value)
			if value == nil then
				return
			end

			state.document_query = vim.trim(value)

			refresh()

			if valid_win(state.wins.list) then
				vim.api.nvim_set_current_win(state.wins.list)
			end
		end)

		return
	end

	vim.ui.input({
		prompt = "󰉋 Search project symbols: ",

		default = state.workspace_query,
	}, function(value)
		if value == nil then
			return
		end

		value = vim.trim(value)

		request_workspace_symbols(value)
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Document / Project Mode
-- ─────────────────────────────────────────────────────────────

local function document_mode()
	if state.mode == "document" then
		return
	end

	state.initial_selection_done = false

	request_document_symbols()
end

local function project_mode()
	if state.mode == "workspace" and state.workspace_query ~= "" then
		request_workspace_symbols(state.workspace_query)

		return
	end

	vim.ui.input({
		prompt = "󰉋 Find symbol in project: ",

		default = state.workspace_query,
	}, function(value)
		if value == nil then
			return
		end

		request_workspace_symbols(vim.trim(value))
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Kind Filters
-- ─────────────────────────────────────────────────────────────

local function set_kind_filter(filter)
	state.kind_filter = filter

	refresh()

	if valid_win(state.wins.list) then
		vim.api.nvim_set_current_win(state.wins.list)
	end
end

-- ─────────────────────────────────────────────────────────────
-- Tree Folding
-- ─────────────────────────────────────────────────────────────

local function toggle_fold()
	if state.mode ~= "document" then
		return
	end

	local node = selected_node()

	if not node or #node.children == 0 then
		return
	end

	state.collapsed[node.key] = not state.collapsed[node.key]

	refresh()
end

-- ─────────────────────────────────────────────────────────────
-- Close
-- ─────────────────────────────────────────────────────────────

local function cleanup_ui(wins, bufs)
	for _, win in pairs(wins or {}) do
		if valid_win(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end

	for _, buf in pairs(bufs or {}) do
		if valid_buf(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
end

local function clear_session_state()
	state.mode = "document"
	state.kind_filter = "all"
	state.document_query = ""
	state.workspace_query = ""

	state.source_buf = nil
	state.source_win = nil
	state.source_file = nil
	state.root = nil
	state.roots = {}
	state.active_client_id = nil

	state.document_nodes = {}
	state.workspace_nodes = {}
	state.visible = {}
	state.line_map = {}
	state.key_to_line = {}
	state.context_lines = {}
	state.collapsed = {}
	state.loading = false
	state.pending_requests = {}

	state.initial_cursor = nil
	state.initial_selection_done = false
	state.preview_file = nil
	state.preview_token = nil

	state.bufs = {}
	state.wins = {}
	state.augroup = nil
end

local function close_center()
	if state.closing or not state.open then
		return
	end

	state.closing = true
	state.open = false
	state.request_generation = state.request_generation + 1

	local source_win = state.source_win
	local wins = state.wins
	local bufs = state.bufs
	local augroup = state.augroup

	cancel_requests()

	if augroup then
		pcall(vim.api.nvim_del_augroup_by_id, augroup)
	end

	state.augroup = nil
	state.wins = {}
	state.bufs = {}

	cleanup_ui(wins, bufs)
	clear_session_state()

	if valid_win(source_win) then
		pcall(vim.api.nvim_set_current_win, source_win)
	end

	state.closing = false
end

-- ─────────────────────────────────────────────────────────────
-- Navigation
-- ─────────────────────────────────────────────────────────────

local function node_location(node)
	if not node or not node.selection_range then
		return nil
	end

	return {
		uri = vim.uri_from_fname(node.file),

		range = node.selection_range,
	}
end

local function jump_to_node(node)
	if not node then
		return false
	end

	local source_win = state.source_win

	local location = node_location(node)

	if not location then
		return false
	end

	local encoding = node.encoding or "utf-16"

	close_center()

	if valid_win(source_win) then
		pcall(vim.api.nvim_set_current_win, source_win)
	end

	local ok = vim.lsp.util.show_document(location, encoding, {
		focus = true,
		reuse_win = true,
	})

	if ok then
		pcall(vim.cmd, "normal! zz")

		return true
	end

	-- Fallback:
	-- show_document herhangi bir nedenle başarısız olursa
	-- dosyayı normal şekilde aç ve LSP sütununu byte offset'e çevir.
	local edit_ok = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(node.file))

	if not edit_ok then
		return false
	end

	local buf = vim.api.nvim_get_current_buf()
	local position = node.selection_range and node.selection_range.start

	if not position then
		return false
	end

	local line, col = buffer_lsp_position(buf, position, node.encoding)

	pcall(vim.api.nvim_win_set_cursor, 0, {
		line + 1,
		col,
	})

	pcall(vim.cmd, "normal! zz")

	return true
end

local function open_selected()
	jump_to_node(selected_node())
end

-- ─────────────────────────────────────────────────────────────
-- References
-- ─────────────────────────────────────────────────────────────

local function find_references()
	local node = selected_node()

	if not node then
		return
	end

	if not jump_to_node(node) then
		return
	end

	vim.schedule(function()
		Snacks.picker.lsp_references()
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Rename
-- ─────────────────────────────────────────────────────────────

local function rename_symbol()
	local node = selected_node()

	if not node then
		return
	end

	if not jump_to_node(node) then
		return
	end

	vim.schedule(function()
		vim.lsp.buf.rename()
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Hover
-- ─────────────────────────────────────────────────────────────

local function hover_symbol()
	local node = selected_node()

	if not node then
		return
	end

	if not jump_to_node(node) then
		return
	end

	vim.schedule(function()
		vim.lsp.buf.hover({
			border = "rounded",
		})
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Manual Refresh
-- ─────────────────────────────────────────────────────────────

local function manual_refresh()
	if state.mode == "document" then
		request_document_symbols()
	else
		request_workspace_symbols(state.workspace_query)
	end
end

-- ─────────────────────────────────────────────────────────────
-- Help
-- ─────────────────────────────────────────────────────────────

local function show_help()
	vim.notify(
		table.concat({
			"Symbol Center",
			"",
			"D    Document symbols",
			"P    Project-wide symbol search",
			"A    All symbol kinds",
			"T    Types / namespaces / classes / structs / enums",
			"F    Functions / methods / constructors",
			"V    Variables / fields / constants",
			"/    Search",
			"za   Collapse / expand subtree",
			"",
			"Enter    Open symbol",
			"R        Find references",
			"N        Rename",
			"K        Hover information",
			"r        Refresh from LSP",
			"q / Esc  Close",
		}, "\n"),
		vim.log.levels.INFO,
		{
			title = "Symbol Center",
		}
	)
end

-- ─────────────────────────────────────────────────────────────
-- Mouse
-- ─────────────────────────────────────────────────────────────

local function mouse_select()
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

	local g, err = geometry()

	if not g then
		close_center()
		vim.notify(err or "Terminal Symbol Center için çok küçük.", vim.log.levels.WARN, {
			title = "Symbol Center",
		})
		return
	end

	local configs = {
		header = float_config(g.row, g.col, g.header_width, g.header_height, " 󰘦  Symbol Center ", false),
		list = float_config(g.body_row, g.col, g.left_width, g.body_height, " 󰘦  Symbols ", true),
		preview = float_config(g.body_row, g.right_col, g.right_width, g.body_height, " 󰈙  Source Preview ", false),
		footer = float_config(g.footer_row, g.col, g.footer_width, g.footer_height, " Actions ", false),
	}

	for name, config in pairs(configs) do
		local win = state.wins[name]

		if valid_win(win) then
			local ok, config_err = pcall(vim.api.nvim_win_set_config, win, config)

			if not ok then
				report_internal_error("Float yeniden konumlandırılamadı", config_err)
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────
-- Local Keymaps
-- ─────────────────────────────────────────────────────────────

local function setup_keymaps()
	local opts = {
		buffer = state.bufs.list,

		silent = true,
		nowait = true,
	}

	vim.keymap.set("n", "q", close_center, opts)

	vim.keymap.set("n", "<Esc>", close_center, opts)

	vim.keymap.set("n", "D", document_mode, opts)

	vim.keymap.set("n", "P", project_mode, opts)

	vim.keymap.set("n", "A", function()
		set_kind_filter("all")
	end, opts)

	vim.keymap.set("n", "T", function()
		set_kind_filter("types")
	end, opts)

	vim.keymap.set("n", "F", function()
		set_kind_filter("callables")
	end, opts)

	vim.keymap.set("n", "V", function()
		set_kind_filter("data")
	end, opts)

	vim.keymap.set("n", "/", search_symbols, opts)

	vim.keymap.set("n", "za", toggle_fold, opts)

	vim.keymap.set("n", "<CR>", open_selected, opts)

	vim.keymap.set("n", "R", find_references, opts)

	vim.keymap.set("n", "N", rename_symbol, opts)

	vim.keymap.set("n", "K", hover_symbol, opts)

	vim.keymap.set("n", "r", manual_refresh, opts)

	vim.keymap.set("n", "?", show_help, opts)

	vim.keymap.set("n", "<LeftMouse>", mouse_select, opts)

	vim.keymap.set("n", "<2-LeftMouse>", function()
		mouse_select()
		open_selected()
	end, opts)
end

-- ─────────────────────────────────────────────────────────────
-- Open Symbol Center
-- ─────────────────────────────────────────────────────────────

local function configure_window_appearance()
	for _, win in pairs(state.wins) do
		if valid_win(win) then
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
		end
	end

	local list_opts = {
		cursorline = true,
		number = false,
		relativenumber = false,
		signcolumn = "no",
		wrap = false,
		scrolloff = 3,
	}

	for name, value in pairs(list_opts) do
		vim.api.nvim_set_option_value(name, value, { win = state.wins.list })
	end

	local preview_opts = {
		number = true,
		relativenumber = false,
		signcolumn = "yes",
		cursorline = true,
		wrap = false,
		scrolloff = 3,
		colorcolumn = "",
	}

	for name, value in pairs(preview_opts) do
		vim.api.nvim_set_option_value(name, value, { win = state.wins.preview })
	end
end

local function setup_runtime_events(session_id)
	state.augroup = vim.api.nvim_create_augroup("DemirSymbolCenterRuntime", {
		clear = true,
	})

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = state.augroup,
		buffer = state.bufs.list,
		callback = function()
			if state.open and state.session_id == session_id then
				render_preview()
			end
		end,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		group = state.augroup,
		callback = function()
			vim.schedule(function()
				if state.open and state.session_id == session_id then
					reposition()
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = state.augroup,
		callback = function(args)
			if not state.open or state.closing or state.session_id ~= session_id then
				return
			end

			local closed = tonumber(args.match)

			for _, win in pairs(state.wins) do
				if win == closed then
					vim.schedule(function()
						if state.open and not state.closing and state.session_id == session_id then
							close_center()
						end
					end)
					return
				end
			end
		end,
	})
end

local function open_center()
	if state.open then
		close_center()
		return
	end

	local source_buf = vim.api.nvim_get_current_buf()
	local source_win = vim.api.nvim_get_current_win()
	local source_file = normalize_path(vim.api.nvim_buf_get_name(source_buf))

	if source_file == "" then
		vim.notify("Symbol Center yalnızca dosyaya bağlı buffer'larda açılabilir.", vim.log.levels.WARN, {
			title = "Symbol Center",
		})
		return
	end

	local client = preferred_client_for_buffer(source_buf, "textDocument/documentSymbol")

	if not client then
		vim.notify("Bu buffer'a documentSymbol destekleyen LSP bağlı değil.", vim.log.levels.WARN, {
			title = "Symbol Center",
		})
		return
	end

	local g, geometry_err = geometry()

	if not g then
		vim.notify(geometry_err or "Terminal Symbol Center için çok küçük.", vim.log.levels.WARN, {
			title = "Symbol Center",
		})
		return
	end

	state.session_id = state.session_id + 1
	local session_id = state.session_id

	state.mode = "document"
	state.kind_filter = "all"
	state.document_query = ""
	state.workspace_query = ""
	state.source_buf = source_buf
	state.source_win = source_win
	state.source_file = source_file
	state.active_client_id = client.id
	set_project_roots(client)

	state.document_nodes = {}
	state.workspace_nodes = {}
	state.visible = {}
	state.line_map = {}
	state.key_to_line = {}
	state.context_lines = {}
	state.collapsed = {}
	state.loading = false
	state.pending_requests = {}
	state.initial_cursor = vim.api.nvim_win_get_cursor(source_win)
	state.initial_selection_done = false
	state.preview_file = nil
	state.preview_token = nil
	state.bufs = {}
	state.wins = {}
	state.augroup = nil

	local staged_bufs = {}
	local staged_wins = {}

	local ok, err = xpcall(function()
		local prefix = string.format("demir://symbols/%d/", session_id)

		staged_bufs.header = create_buffer(prefix .. "header")
		staged_bufs.list = create_buffer(prefix .. "list")
		staged_bufs.preview = create_buffer(prefix .. "preview")
		staged_bufs.footer = create_buffer(prefix .. "footer")

		staged_wins.header = vim.api.nvim_open_win(
			staged_bufs.header,
			false,
			float_config(g.row, g.col, g.header_width, g.header_height, " 󰘦  Symbol Center ", false)
		)

		staged_wins.list = vim.api.nvim_open_win(
			staged_bufs.list,
			true,
			float_config(g.body_row, g.col, g.left_width, g.body_height, " 󰘦  Symbols ", true)
		)

		staged_wins.preview = vim.api.nvim_open_win(
			staged_bufs.preview,
			false,
			float_config(g.body_row, g.right_col, g.right_width, g.body_height, " 󰈙  Source Preview ", false)
		)

		staged_wins.footer = vim.api.nvim_open_win(
			staged_bufs.footer,
			false,
			float_config(g.footer_row, g.col, g.footer_width, g.footer_height, " Actions ", false)
		)

		state.bufs = staged_bufs
		state.wins = staged_wins

		configure_window_appearance()
		setup_keymaps()
		setup_runtime_events(session_id)
		render_footer()
	end, debug.traceback)

	if not ok then
		if state.augroup then
			pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
		end

		cleanup_ui(staged_wins, staged_bufs)
		clear_session_state()

		if valid_win(source_win) then
			pcall(vim.api.nvim_set_current_win, source_win)
		end

		report_internal_error("Symbol Center transactional açılışı başarısız", err)
		return
	end

	state.open = true
	state.closing = false

	request_document_symbols()
end

-- ─────────────────────────────────────────────────────────────
-- Public Mapping
-- ─────────────────────────────────────────────────────────────

vim.keymap.set("n", "<leader>s", open_center, {
	desc = "Symbol Center",
})

return M
