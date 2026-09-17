local M = {}

local workspace = require("demir.lsp.workspace")
local common = require("demir.lsp.hierarchy_common")

local ns = vim.api.nvim_create_namespace("DemirTypeHierarchy")

local PREPARE_METHOD = "textDocument/prepareTypeHierarchy"
local SUPERTYPES_METHOD = "typeHierarchy/supertypes"
local SUBTYPES_METHOD = "typeHierarchy/subtypes"

local MAX_DEPTH = 64
local unpack_args = table.unpack or unpack
local pack_args = table.pack or function(...)
	return { n = select("#", ...), ... }
end

-- ─────────────────────────────────────────────────────────────
-- Shared Hierarchy Primitives
-- ─────────────────────────────────────────────────────────────
--
-- Stateless mechanics shared by Call Hierarchy and Type Hierarchy live in
-- demir.lsp.hierarchy_common. Protocol semantics and per-session state remain
-- local to this module.
-- ─────────────────────────────────────────────────────────────

local kind_info = common.kind_info

-- ─────────────────────────────────────────────────────────────
-- Runtime State
-- ─────────────────────────────────────────────────────────────

local state = {
	open = false,
	closing = false,
	preparing = false,
	session_id = 0,
	launch_generation = 0,
	request_generation = {
		supertypes = 0,
		subtypes = 0,
	},

	direction = "subtypes",

	source_buf = nil,
	source_win = nil,
	source_file = nil,
	source_tick = nil,
	active_client_id = nil,
	encoding = "utf-16",
	project_root = nil,
	root_item = nil,
	roots = {},
	relevant_buffers = {},

	trees = {
		supertypes = nil,
		subtypes = nil,
	},

	visible = {},
	line_map = {},
	key_to_line = {},

	pending_requests = {},
	prepare_request = nil,

	preview_file = nil,
	preview_token = nil,
	preview_ft = nil,

	bufs = {},
	wins = {},
	augroup = nil,
}

-- ─────────────────────────────────────────────────────────────
-- Basic Helpers
-- ─────────────────────────────────────────────────────────────

local valid_buf = common.valid_buf
local loaded_buf = common.loaded_buf
local valid_win = common.valid_win
local normalize_path = common.normalize_path
local one_line = common.one_line
local uri_to_file = common.uri_to_file
local safe_table = common.safe_table

local function report_internal_error(context, err)
	vim.schedule(function()
		vim.notify_once(
			string.format("%s: %s", context, tostring(err)),
			vim.log.levels.WARN,
			{ title = "Type Hierarchy" }
		)
	end)
end

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, {
		title = "Type Hierarchy",
	})
end

local function mark_relevant_buffer(buf)
	if loaded_buf(buf) then
		state.relevant_buffers[buf] = true
	end
end

local function item_location_text(item)
	return common.item_location_text(state.roots, item)
end

-- ─────────────────────────────────────────────────────────────
-- Scratch Buffers
-- ─────────────────────────────────────────────────────────────

local create_buffer = common.create_buffer

local function set_lines(buf, lines)
	local ok, err = common.set_lines(buf, lines)

	if not ok then
		report_internal_error("Hierarchy buffer içeriği güncellenemedi", err)
	end
end

-- ─────────────────────────────────────────────────────────────
-- Safe Extmarks
-- ─────────────────────────────────────────────────────────────

local function safe_extmark(buf, row, col, opts)
	return common.safe_extmark(ns, report_internal_error, buf, row, col, opts)
end

local function highlight_literal(buf, row, text, needle, hl)
	common.highlight_literal(ns, report_internal_error, buf, row, text, needle, hl)
end

-- ─────────────────────────────────────────────────────────────
-- LSP Position Conversion
-- ─────────────────────────────────────────────────────────────

local clamp_position_in_lines = common.clamp_position_in_lines

-- ─────────────────────────────────────────────────────────────
-- Source Preview
-- ─────────────────────────────────────────────────────────────

local loaded_buffer_for_file = common.loaded_buffer_for_file

local function source_descriptor(uri)
	return common.source_descriptor(uri, mark_relevant_buffer)
end

local function read_source_lines(descriptor)
	return common.read_source_lines(descriptor, report_internal_error)
end

local function invalidate_preview_cache(clear_syntax)
	state.preview_file = nil
	state.preview_token = nil
	state.preview_ft = nil

	if clear_syntax and valid_buf(state.bufs.preview) then
		pcall(vim.treesitter.stop, state.bufs.preview)

		local ok = pcall(function()
			vim.bo[state.bufs.preview].filetype = ""
		end)

		if not ok then
			-- Preview cache invalidation must never make the UI unusable.
		end
	end
end

local function show_preview_message(lines)
	if not valid_buf(state.bufs.preview) then
		return
	end

	invalidate_preview_cache(true)
	set_lines(state.bufs.preview, lines)
	vim.api.nvim_buf_clear_namespace(state.bufs.preview, ns, 0, -1)
end

-- ─────────────────────────────────────────────────────────────
-- LSP Client Helpers
-- ─────────────────────────────────────────────────────────────

local preferred_client_for_buffer = common.preferred_client_for_buffer

local function active_client()
	if not state.active_client_id then
		return nil
	end

	return vim.lsp.get_client_by_id(state.active_client_id)
end

local function client_attached_to_buffer(client, buf)
	return client ~= nil and loaded_buf(buf) and vim.lsp.buf_is_attached(buf, client.id)
end

local function request_buffer_for_item(client, item)
	local file = type(item) == "table" and uri_to_file(item.uri) or nil
	local item_buf = file and loaded_buffer_for_file(file) or nil

	if item_buf and client_attached_to_buffer(client, item_buf) then
		mark_relevant_buffer(item_buf)
		return item_buf
	end

	if client_attached_to_buffer(client, state.source_buf) then
		mark_relevant_buffer(state.source_buf)
		return state.source_buf
	end

	return state.source_buf
end

local function cancel_prepare_request()
	local request = state.prepare_request

	-- İptal edilen prepare callback'i sunucudan yarış halinde daha sonra
	-- dönebilir. Generation'ı burada artırarak böyle bir callback'in yeni
	-- bir UI oturumu açmasını kesin olarak engelliyoruz.
	state.launch_generation = state.launch_generation + 1
	state.prepare_request = nil
	state.preparing = false

	if request and request.client and request.id then
		pcall(request.client.cancel_request, request.client, request.id)
	end
end

local function cancel_requests(direction)
	for index = #state.pending_requests, 1, -1 do
		local request = state.pending_requests[index]

		if direction == nil or request.direction == direction then
			table.remove(state.pending_requests, index)

			if request.on_cancel then
				local ok, err = pcall(request.on_cancel)

				if not ok then
					report_internal_error("İptal cleanup'i başarısız", err)
				end
			end

			if request.client and request.id then
				pcall(request.client.cancel_request, request.client, request.id)
			end
		end
	end
end

local function track_request(client, request_id, opts)
	opts = opts or {}

	if not client or not request_id then
		return nil
	end

	local request = {
		client = client,
		id = request_id,
		direction = opts.direction,
		on_cancel = opts.on_cancel,
	}

	table.insert(state.pending_requests, request)
	return request
end

local function untrack_request(client, request_id)
	for index = #state.pending_requests, 1, -1 do
		local request = state.pending_requests[index]

		if request.client == client and request.id == request_id then
			table.remove(state.pending_requests, index)
			return request
		end
	end

	return nil
end

local function request_from_client(client, method, params, handler, opts)
	opts = opts or {}

	local bufnr = opts.bufnr or state.source_buf

	if not client or not bufnr or not valid_buf(bufnr) then
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
			report_internal_error("LSP Type Hierarchy callback'i başarısız", err)
		end
	end

	local call_ok, status, id = pcall(client.request, client, method, params, wrapped_handler, bufnr)

	if not call_ok then
		report_internal_error("LSP isteği gönderilirken hata oluştu", status)
		return false
	end

	request_id = id

	if status ~= true then
		return false
	end

	-- Neovim'in in-process LSP test sunucuları callback'i request() dönmeden
	-- tamamlayabilir. Böyle bir isteği pending listesine yeniden eklemiyoruz.
	if not completed then
		if not request_id then
			return false
		end

		track_request(client, request_id, opts)
	end

	return true
end

-- ─────────────────────────────────────────────────────────────
-- Type Hierarchy Model
-- ─────────────────────────────────────────────────────────────

local valid_range = common.valid_range
local valid_item = common.valid_item
local item_signature = common.item_signature

local function ancestry_contains(node, signature)
	local cursor = node

	while cursor do
		if cursor.signature == signature then
			return true
		end

		cursor = cursor.parent
	end

	return false
end

local function root_node(item, direction)
	local signature = item_signature(item)

	return {
		key = string.format("%s:root:%s", direction, signature),
		signature = signature,
		item = item,
		direction = direction,
		depth = 0,
		parent = nil,
		children = {},
		expanded = true,
		loaded = false,
		loading = false,
		load_error = nil,
		cycle = false,
		depth_limited = false,
	}
end

local function child_node(parent, item, ordinal)
	local signature = item_signature(item)
	local depth = parent.depth + 1
	local cycle = ancestry_contains(parent, signature)
	local depth_limited = depth >= MAX_DEPTH

	-- Sonuç başka bir açık dosyaya işaret ediyorsa onu da oturumun
	-- semantik girdilerinden biri say. Böylece hiyerarşi açıkken o dosya
	-- değişirse eski range'lerle devam etmek yerine UI güvenli biçimde kapanır.
	local file = uri_to_file(item.uri)
	local item_buf = file and loaded_buffer_for_file(file) or nil

	if item_buf then
		mark_relevant_buffer(item_buf)
	end

	return {
		-- LSP TypeHierarchyItem.data opaktır. Aynı görünür konumu paylaşan iki
		-- öğenin data alanlarının eşdeğer olduğunu varsayamayız. Bu nedenle
		-- kardeş öğeleri signature ile birleştirmiyor, key'e server sırasını da
		-- katıyoruz. `signature` yalnız ancestry-cycle algılaması içindir.
		key = string.format("%s\30%d\30%s", parent.key, ordinal or 0, signature),
		signature = signature,
		ordinal = ordinal or 0,
		item = item,
		direction = parent.direction,
		depth = depth,
		parent = parent,
		children = {},
		expanded = false,
		loaded = false,
		loading = false,
		load_error = nil,
		cycle = cycle,
		depth_limited = depth_limited,
	}
end

local function normalize_type_children(parent, result)
	local output = {}

	-- LSP spesifikasyonu supertypes/subtypes sonucunu TypeHierarchyItem[]
	-- olarak tanımlar fakat duplicate öğelerin semantik olarak birleştirilebilir
	-- olduğunu garanti etmez. Özellikle `data` server'a ait opaque continuation
	-- bilgisidir. Bu yüzden geçerli her öğeyi kayıpsız koruyoruz.
	for index, item in ipairs(safe_table(result)) do
		if valid_item(item) then
			table.insert(output, child_node(parent, item, index))
		end
	end

	table.sort(output, function(a, b)
		local an = one_line(a.item.name):lower()
		local bn = one_line(b.item.name):lower()

		if an ~= bn then
			return an < bn
		end

		local au = tostring(a.item.uri)
		local bu = tostring(b.item.uri)

		if au ~= bu then
			return au < bu
		end

		local ap = a.item.selectionRange.start
		local bp = b.item.selectionRange.start

		if ap.line ~= bp.line then
			return ap.line < bp.line
		end

		if ap.character ~= bp.character then
			return ap.character < bp.character
		end

		return (a.ordinal or 0) < (b.ordinal or 0)
	end)

	return output
end

local function current_root()
	return state.trees[state.direction]
end

local flatten_tree = common.flatten_tree

local function calculate_visible()
	local output = {}
	flatten_tree(current_root(), output)
	state.visible = output
end

-- ─────────────────────────────────────────────────────────────
-- Geometry
-- ─────────────────────────────────────────────────────────────

local function geometry()
	return common.geometry("Type Hierarchy")
end

local float_config = common.float_config
local truncate_display = common.truncate_display

-- ─────────────────────────────────────────────────────────────
-- Selection Helpers
-- ─────────────────────────────────────────────────────────────

local function selected_node()
	return common.selected_node(state)
end

local function selected_key()
	return common.selected_key(state)
end

-- ─────────────────────────────────────────────────────────────
-- Rendering
-- ─────────────────────────────────────────────────────────────

local render_preview
local refresh

local function direction_title(direction)
	return direction == "subtypes" and "DERIVED TYPES" or "BASE TYPES"
end

local function direction_root(direction)
	return state.trees[direction]
end

local function direction_status(direction)
	local root = direction_root(direction)

	if not root then
		return {
			token = "?",
			hl = "Comment",
			state = "unknown",
			count = nil,
		}
	end

	if root.loading then
		return {
			token = "…",
			hl = "DiagnosticInfo",
			state = "loading",
			count = nil,
		}
	end

	if root.load_error then
		return {
			token = "!",
			hl = "DiagnosticError",
			state = "error",
			count = nil,
		}
	end

	if not root.loaded then
		return {
			token = "?",
			hl = "Comment",
			state = "unknown",
			count = nil,
		}
	end

	local count = #safe_table(root.children)

	if count == 0 then
		return {
			token = "0",
			hl = "Comment",
			state = "empty",
			count = 0,
		}
	end

	return {
		token = tostring(count),
		hl = "DiagnosticOk",
		state = "available",
		count = count,
	}
end

local function direction_option_label(direction)
	local status = direction_status(direction)
	local key = direction == "supertypes" and "B" or "D"
	local title = direction == "supertypes" and "BASE TYPES" or "DERIVED TYPES"

	return string.format("[%s:%s] %s", key, status.token, title), status
end

local function render_direction_highlights(buf, row, text, base_label, base_status, derived_label, derived_status)
	-- Başlık metni yalnız seçili modu gösterir. İlişkinin gerçekten var olduğu
	-- anlamını renk üzerinden vermiyoruz. Status token'ları ayrı ve çakışmayan
	-- extmark'larla boyanır.
	local _ = base_label
	_ = derived_label

	highlight_literal(buf, row, text, "BASE TYPES", state.direction == "supertypes" and "Visual" or "Comment")

	highlight_literal(buf, row, text, "DERIVED TYPES", state.direction == "subtypes" and "Visual" or "Comment")

	-- İlişki durumu yalnız küçük status token'ında semantik renge sahiptir:
	-- ? bilinmiyor, … yükleniyor, 0 yok, n>0 mevcut, ! hata.
	highlight_literal(buf, row, text, "B:" .. base_status.token, base_status.hl)
	highlight_literal(buf, row, text, "D:" .. derived_status.token, derived_status.hl)
end

local function render_header()
	if not valid_buf(state.bufs.header) then
		return
	end

	local client = active_client()
	local client_name = client and client.name or "LSP"
	local project = state.project_root and vim.fs.basename(state.project_root) or "workspace"
	local root = current_root()
	local root_name = root and one_line(root.item.name) or "<none>"
	local active_direction_title = direction_title(state.direction)
	local base_label, base_status = direction_option_label("supertypes")
	local derived_label, derived_status = direction_option_label("subtypes")

	local first = string.format("  󰠱  TYPE HIERARCHY     󰉋 %s     󰒋 %s", project, client_name)
	local second = string.format("  %s     %s     %s: %s", base_label, derived_label, active_direction_title, root_name)

	local node = selected_node()
	local third

	if node then
		local info = kind_info(node.item.kind)
		local detail = one_line(node.item.detail)
		local suffix = detail ~= "" and ("     " .. detail) or ""
		third = string.format(
			"  %s  %s     %s     %s%s",
			info.icon,
			one_line(node.item.name),
			info.name,
			item_location_text(node.item),
			suffix
		)
	else
		third = "  No type hierarchy item selected"
	end

	local width = valid_win(state.wins.header) and math.max(1, vim.api.nvim_win_get_width(state.wins.header) - 1) or 120
	first = truncate_display(first, width)
	second = truncate_display(second, width)
	third = truncate_display(third, width)

	set_lines(state.bufs.header, { first, second, third })
	vim.api.nvim_buf_clear_namespace(state.bufs.header, ns, 0, -1)

	highlight_literal(state.bufs.header, 0, first, "TYPE HIERARCHY", "Title")
	highlight_literal(state.bufs.header, 0, first, client_name, "DiagnosticInfo")
	render_direction_highlights(state.bufs.header, 1, second, base_label, base_status, derived_label, derived_status)
end

local function node_branch(node)
	if node.loading then
		return "󰔟"
	end

	if node.cycle then
		return "↻"
	end

	if node.depth_limited then
		return "×"
	end

	if node.load_error then
		return "!"
	end

	if node.loaded and #node.children == 0 then
		return "·"
	end

	return node.expanded and "▾" or "▸"
end

local function render_list(preferred_key)
	if not valid_buf(state.bufs.list) then
		return
	end

	calculate_visible()
	state.line_map = {}
	state.key_to_line = {}

	local lines = {}
	local width = 80

	if valid_win(state.wins.list) then
		width = math.max(8, vim.api.nvim_win_get_width(state.wins.list) - 1)
	end

	if #state.visible == 0 then
		lines = {
			"",
			"   󰄬  No type hierarchy items",
		}
		set_lines(state.bufs.list, lines)
		vim.api.nvim_buf_clear_namespace(state.bufs.list, ns, 0, -1)

		if valid_win(state.wins.list) then
			pcall(vim.api.nvim_win_set_cursor, state.wins.list, { 1, 0 })
		end

		return
	end

	for _, node in ipairs(state.visible) do
		local info = kind_info(node.item.kind)
		local indent = string.rep("  ", node.depth)
		local branch = node_branch(node)
		local detail = one_line(node.item.detail)
		local text = string.format("  %s%s %s  %s", indent, branch, info.icon, one_line(node.item.name))

		if detail ~= "" then
			text = text .. "  " .. detail
		end

		text = truncate_display(text, width)
		table.insert(lines, text)

		local line = #lines
		state.line_map[line] = node
		state.key_to_line[node.key] = line
	end

	set_lines(state.bufs.list, lines)
	vim.api.nvim_buf_clear_namespace(state.bufs.list, ns, 0, -1)

	for line, node in pairs(state.line_map) do
		local info = kind_info(node.item.kind)
		local text = lines[line] or ""
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

		if node.loading then
			highlight_literal(state.bufs.list, line - 1, text, "󰔟", "DiagnosticInfo")
		elseif node.load_error then
			highlight_literal(state.bufs.list, line - 1, text, "!", "DiagnosticError")
		elseif node.cycle then
			highlight_literal(state.bufs.list, line - 1, text, "↻", "DiagnosticWarn")
		elseif node.depth_limited then
			highlight_literal(state.bufs.list, line - 1, text, "×", "DiagnosticWarn")
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

	if #lines > 0 then
		pcall(vim.api.nvim_win_set_cursor, state.wins.list, { 1, 0 })
	end
end

local function preview_location(node)
	if not node or not valid_item(node.item) then
		return nil
	end

	return {
		uri = node.item.uri,
		range = node.item.selectionRange or node.item.range,
	}
end

render_preview = function()
	if not valid_buf(state.bufs.preview) then
		return
	end

	local node = selected_node()

	if not node then
		show_preview_message({
			"",
			"  Select a type hierarchy item to preview it.",
		})
		render_header()
		return
	end

	local location = preview_location(node)

	if not location or not valid_range(location.range) then
		show_preview_message({
			"",
			"  This type has no previewable location.",
		})
		render_header()
		return
	end

	local descriptor = source_descriptor(location.uri)

	if not descriptor then
		show_preview_message({
			"",
			"  Preview is available only for readable file:// locations.",
			"",
			"  " .. one_line(location.uri or ""),
		})
		render_header()
		return
	end

	local token = descriptor.token
	local needs_copy = state.preview_file ~= descriptor.file or state.preview_token ~= token
	local lines

	if needs_copy then
		lines = read_source_lines(descriptor)

		if not lines then
			show_preview_message({
				"",
				"  Source preview could not be read.",
			})
			render_header()
			return
		end

		set_lines(state.bufs.preview, lines)

		local file_changed = state.preview_file ~= descriptor.file
		local filetype_changed = state.preview_ft ~= descriptor.ft

		if file_changed or filetype_changed then
			pcall(vim.treesitter.stop, state.bufs.preview)
			vim.bo[state.bufs.preview].filetype = descriptor.ft

			if descriptor.ft ~= "" then
				pcall(vim.treesitter.start, state.bufs.preview, descriptor.ft)
			end
		end

		state.preview_file = descriptor.file
		state.preview_token = token
		state.preview_ft = descriptor.ft
	else
		lines = vim.api.nvim_buf_get_lines(state.bufs.preview, 0, -1, false)
	end

	if #lines == 0 then
		lines = { "" }
	end

	vim.api.nvim_buf_clear_namespace(state.bufs.preview, ns, 0, -1)

	local start_row, start_col = clamp_position_in_lines(lines, location.range.start, state.encoding)
	local finish_row, finish_col = clamp_position_in_lines(lines, location.range["end"], state.encoding)
	local info = kind_info(node.item.kind)
	local label = string.format(" %s %s ", info.icon, info.name)

	local extmark_opts = {
		line_hl_group = "CursorLine",
		virt_text = {
			{ label, info.hl },
		},
		virt_text_pos = "right_align",
	}

	if finish_row == start_row and finish_col > start_col then
		extmark_opts.end_col = finish_col
		extmark_opts.hl_group = info.hl
	end

	safe_extmark(state.bufs.preview, start_row, start_col, extmark_opts)

	if valid_win(state.wins.preview) then
		pcall(vim.api.nvim_win_set_cursor, state.wins.preview, {
			start_row + 1,
			start_col,
		})

		pcall(vim.api.nvim_win_call, state.wins.preview, function()
			vim.cmd("normal! zz")
		end)
	end

	render_header()
end

local function render_footer()
	if not valid_buf(state.bufs.footer) then
		return
	end

	local base_label, base_status = direction_option_label("supertypes")
	local derived_label, derived_status = direction_option_label("subtypes")

	local first = string.format(
		"  B Base types [%s]   D Derived types [%s]   za Expand/Collapse   ← Parent   → Expand",
		base_status.token,
		derived_status.token
	)
	local second = "  ↵ Open type   r Refresh   ? Help   q Close"
	local width = valid_win(state.wins.footer) and math.max(1, vim.api.nvim_win_get_width(state.wins.footer) - 1) or 120

	first = truncate_display(first, width)
	second = truncate_display(second, width)

	set_lines(state.bufs.footer, { first, second })
	vim.api.nvim_buf_clear_namespace(state.bufs.footer, ns, 0, -1)

	-- B/D eylemleri artık sabit yeşil değildir. Visual yalnız aktif modu,
	-- köşeli parantez içindeki status ise ilişkinin gerçek durumunu gösterir.
	highlight_literal(
		state.bufs.footer,
		0,
		first,
		"B Base types",
		state.direction == "supertypes" and "Visual" or "Comment"
	)
	highlight_literal(
		state.bufs.footer,
		0,
		first,
		"D Derived types",
		state.direction == "subtypes" and "Visual" or "Comment"
	)
	highlight_literal(state.bufs.footer, 0, first, "[" .. base_status.token .. "]", base_status.hl)
	highlight_literal(state.bufs.footer, 0, first, "[" .. derived_status.token .. "]", derived_status.hl)
	highlight_literal(state.bufs.footer, 1, second, "↵ Open type", "Type")
end

local function render_direction_chrome()
	if not state.open then
		return
	end

	render_header()
	render_footer()
end

refresh = function(preferred_key)
	if not state.open then
		return
	end

	preferred_key = preferred_key or selected_key()
	render_list(preferred_key)
	render_preview()
	render_header()
	render_footer()
end

-- Hierarchy Requests
-- ─────────────────────────────────────────────────────────────

local function method_for_direction(direction)
	return direction == "subtypes" and SUBTYPES_METHOD or SUPERTYPES_METHOD
end

local function request_children(node)
	if not state.open or not node then
		return
	end

	if node.cycle then
		notify("Döngü algılandı; aynı tür bu dalda yeniden genişletilmeyecek.", vim.log.levels.INFO)
		return
	end

	if node.depth_limited then
		notify(string.format("Güvenlik derinlik sınırına ulaşıldı (%d).", MAX_DEPTH), vim.log.levels.WARN)
		return
	end

	if node.loading then
		return
	end

	if node.loaded then
		node.expanded = true
		refresh(node.key)
		return
	end

	local client = active_client()

	if not client or (client.is_stopped and client:is_stopped()) then
		node.loading = false
		node.load_error = "LSP client kapandı."

		if state.direction == node.direction then
			refresh(node.key)
		else
			render_direction_chrome()
		end

		return
	end

	local direction = node.direction
	local method = method_for_direction(direction)
	local request_buf = request_buffer_for_item(client, node.item)

	if not client:supports_method(method, request_buf) then
		node.loading = false
		node.loaded = false
		node.load_error = "LSP bu tür hiyerarşisi yöntemini artık desteklemiyor."

		if state.direction == direction then
			refresh(node.key)
		else
			render_direction_chrome()
		end

		return
	end

	local session_id = state.session_id
	local generation = state.request_generation[direction] or 0
	local request_tick = loaded_buf(request_buf) and vim.api.nvim_buf_get_changedtick(request_buf) or nil

	node.loading = true
	node.load_error = nil
	node.expanded = true
	refresh(node.key)

	local ok = request_from_client(client, method, { item = node.item }, function(err, result)
		if
			not state.open
			or state.session_id ~= session_id
			or generation ~= (state.request_generation[direction] or 0)
		then
			return
		end

		if
			request_tick
			and loaded_buf(request_buf)
			and vim.api.nvim_buf_get_changedtick(request_buf) ~= request_tick
		then
			node.loading = false
			node.loaded = false
			node.load_error = "Kaynak buffer değişti; hiyerarşiyi yeniden açın."

			if state.direction == direction then
				refresh()
			else
				render_direction_chrome()
			end
			return
		end

		node.loading = false

		if err then
			node.loaded = false
			node.load_error = one_line(err.message or err)

			if state.direction == direction then
				refresh()
			else
				render_direction_chrome()
			end

			return
		end

		node.children = normalize_type_children(node, result)
		node.loaded = true
		node.load_error = nil
		node.expanded = true

		if state.direction == direction then
			-- Preserve whichever node the user is currently on. An async response
			-- must never drag the cursor back to the node that initiated it.
			refresh()
		else
			render_direction_chrome()
		end
	end, {
		bufnr = request_buf,
		direction = direction,
		on_cancel = function()
			node.loading = false

			if not node.loaded then
				node.expanded = false
			end

			if state.open then
				if state.direction == direction then
					refresh()
				else
					render_direction_chrome()
				end
			end
		end,
	})

	if not ok then
		node.loading = false
		node.loaded = false
		node.load_error = "LSP request gönderilemedi."

		if state.direction == direction then
			refresh(node.key)
		else
			render_direction_chrome()
		end
	end
end

local function ensure_root_loaded(direction)
	local root = state.trees[direction]

	if root and not root.loaded and not root.loading then
		request_children(root)
	end
end

-- Tree Actions
-- ─────────────────────────────────────────────────────────────

local function switch_direction(direction)
	if direction ~= "supertypes" and direction ~= "subtypes" then
		return
	end

	if not state.open then
		return
	end

	state.direction = direction

	if not state.trees[direction] and state.root_item then
		state.trees[direction] = root_node(state.root_item, direction)
	end

	refresh()
	ensure_root_loaded(direction)
end

local function toggle_fold()
	local node = selected_node()

	if not node then
		return
	end

	if node.cycle or node.depth_limited then
		return
	end

	if not node.loaded then
		request_children(node)
		return
	end

	if #node.children == 0 then
		return
	end

	node.expanded = not node.expanded
	refresh(node.key)
end

local function expand_selected()
	local node = selected_node()

	if not node or node.cycle or node.depth_limited then
		return
	end

	if not node.loaded then
		request_children(node)
		return
	end

	if #node.children > 0 then
		node.expanded = true
		refresh(node.key)
	end
end

local function collapse_or_parent()
	local node = selected_node()

	if not node then
		return
	end

	if node.expanded and #node.children > 0 then
		node.expanded = false
		refresh(node.key)
		return
	end

	if node.parent and valid_win(state.wins.list) then
		local line = state.key_to_line[node.parent.key]

		if line then
			pcall(vim.api.nvim_win_set_cursor, state.wins.list, { line, 0 })
			render_preview()
		end
	end
end

local function refresh_tree()
	if not state.open or not state.root_item then
		return
	end

	local direction = state.direction
	state.request_generation[direction] = (state.request_generation[direction] or 0) + 1
	cancel_requests(direction)

	state.trees[direction] = root_node(state.root_item, direction)
	refresh(state.trees[direction].key)
	ensure_root_loaded(direction)
end

-- Close / Cleanup
-- ─────────────────────────────────────────────────────────────

local cleanup_ui = common.cleanup_ui

local function clear_session_state()
	state.preparing = false
	state.prepare_request = nil
	state.direction = "subtypes"
	state.source_buf = nil
	state.source_win = nil
	state.source_file = nil
	state.source_tick = nil
	state.active_client_id = nil
	state.encoding = "utf-16"
	state.project_root = nil
	state.root_item = nil
	state.roots = {}
	state.relevant_buffers = {}
	state.trees = {
		supertypes = nil,
		subtypes = nil,
	}
	state.visible = {}
	state.line_map = {}
	state.key_to_line = {}
	state.pending_requests = {}
	state.request_generation = {
		supertypes = 0,
		subtypes = 0,
	}
	state.preview_file = nil
	state.preview_token = nil
	state.preview_ft = nil
	state.bufs = {}
	state.wins = {}
	state.augroup = nil
end

local function close_hierarchy(opts)
	opts = opts or {}

	if state.closing or not state.open then
		return
	end

	local restore_focus = opts.restore_focus ~= false

	state.closing = true
	state.open = false
	state.launch_generation = state.launch_generation + 1
	state.request_generation.supertypes = (state.request_generation.supertypes or 0) + 1
	state.request_generation.subtypes = (state.request_generation.subtypes or 0) + 1

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

	-- Otomatik lifecycle kapanışları (özellikle TabLeave) kullanıcıyı eski
	-- pencereye/tab'a geri çekmemeli. Açık bir kullanıcı eyleminde ise kaynak
	-- pencereye dönmek beklenen davranıştır.
	if restore_focus and valid_win(source_win) then
		pcall(vim.api.nvim_set_current_win, source_win)
	end

	state.closing = false
end

M.close = close_hierarchy

-- ─────────────────────────────────────────────────────────────
-- Navigation
-- ─────────────────────────────────────────────────────────────

local function show_location(location)
	if not location or type(location.uri) ~= "string" or not valid_range(location.range) then
		return false
	end

	local encoding = state.encoding or "utf-16"
	local source_win = state.source_win

	close_hierarchy({ restore_focus = false })

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

	notify("Tür konumu açılamadı.", vim.log.levels.WARN)
	return false
end

local function open_type()
	local node = selected_node()

	if not node then
		return
	end

	show_location({
		uri = node.item.uri,
		range = node.item.selectionRange or node.item.range,
	})
end

-- Help
-- ─────────────────────────────────────────────────────────────

local function show_help()
	vim.notify(
		table.concat({
			"Type Hierarchy",
			"",
			"B        Base types / supertypes",
			"D        Derived types / subtypes",
			"",
			"Status   ? unknown   … loading   0 none   n relation count   ! error",
			"za       Expand / collapse selected type",
			"Right    Expand selected type",
			"Left     Collapse or go to parent",
			"",
			"Enter    Open selected type",
			"r        Rebuild current hierarchy direction",
			"?        Help",
			"q / Esc  Close",
		}, "\n"),
		vim.log.levels.INFO,
		{ title = "Type Hierarchy" }
	)
end

-- Mouse
-- ─────────────────────────────────────────────────────────────

local function mouse_select()
	local mouse = vim.fn.getmousepos()

	if mouse.winid ~= state.wins.list or not valid_buf(state.bufs.list) then
		return
	end

	local line_count = vim.api.nvim_buf_line_count(state.bufs.list)
	local line = math.max(1, math.min(tonumber(mouse.line) or 1, line_count))
	local text = vim.api.nvim_buf_get_lines(state.bufs.list, line - 1, line, false)[1] or ""
	local col = math.max(0, math.min((tonumber(mouse.column) or 1) - 1, #text))

	local ok = pcall(vim.api.nvim_win_set_cursor, state.wins.list, { line, col })

	if ok then
		render_preview()
	end
end

-- ─────────────────────────────────────────────────────────────
-- Window Configuration / Resize
-- ─────────────────────────────────────────────────────────────

local function configure_window_appearance()
	common.configure_window_appearance(state.wins)
end

local function reposition()
	if not state.open then
		return
	end

	local g, err = geometry()

	if not g then
		notify(err or "Terminal Type Hierarchy için çok küçük.", vim.log.levels.WARN)
		close_hierarchy()
		return
	end

	local ok, config_err = xpcall(function()
		if valid_win(state.wins.header) then
			vim.api.nvim_win_set_config(
				state.wins.header,
				float_config(g.row, g.col, g.header_width, g.header_height, " 󰠱  Type Hierarchy ", false)
			)
		end

		if valid_win(state.wins.list) then
			vim.api.nvim_win_set_config(
				state.wins.list,
				float_config(g.body_row, g.col, g.left_width, g.body_height, " 󰠱  Types ", true)
			)
		end

		if valid_win(state.wins.preview) then
			vim.api.nvim_win_set_config(
				state.wins.preview,
				float_config(g.body_row, g.right_col, g.right_width, g.body_height, " 󰈙  Source Preview ", false)
			)
		end

		if valid_win(state.wins.footer) then
			vim.api.nvim_win_set_config(
				state.wins.footer,
				float_config(g.footer_row, g.col, g.footer_width, g.footer_height, " Actions ", false)
			)
		end
	end, debug.traceback)

	if not ok then
		report_internal_error("Type Hierarchy yeniden konumlandırılamadı", config_err)
		close_hierarchy()
		return
	end

	refresh()
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

	vim.keymap.set("n", "q", close_hierarchy, opts)
	vim.keymap.set("n", "<Esc>", close_hierarchy, opts)

	vim.keymap.set("n", "B", function()
		switch_direction("supertypes")
	end, opts)

	vim.keymap.set("n", "D", function()
		switch_direction("subtypes")
	end, opts)

	vim.keymap.set("n", "za", toggle_fold, opts)
	vim.keymap.set("n", "<Right>", expand_selected, opts)
	vim.keymap.set("n", "<Left>", collapse_or_parent, opts)

	vim.keymap.set("n", "<CR>", open_type, opts)
	vim.keymap.set("n", "r", refresh_tree, opts)
	vim.keymap.set("n", "?", show_help, opts)

	vim.keymap.set("n", "<LeftMouse>", mouse_select, opts)
	vim.keymap.set("n", "<2-LeftMouse>", function()
		mouse_select()
		open_type()
	end, opts)
end

-- Runtime Events
-- ─────────────────────────────────────────────────────────────

local function setup_runtime_events(session_id)
	state.augroup = vim.api.nvim_create_augroup("DemirTypeHierarchyRuntime", {
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
							close_hierarchy({ restore_focus = false })
						end
					end)
					return
				end
			end
		end,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		group = state.augroup,
		callback = function(args)
			if not state.open or state.session_id ~= session_id then
				return
			end

			if not args.data or args.data.client_id ~= state.active_client_id then
				return
			end

			local detached_buf = args.buf
			local relevant = detached_buf == state.source_buf or state.relevant_buffers[detached_buf] == true

			if not relevant then
				return
			end

			vim.schedule(function()
				if state.open and state.session_id == session_id then
					notify(
						"Type Hierarchy ilgili LSP buffer'ından ayrıldığı için kapatıldı.",
						vim.log.levels.WARN
					)
					close_hierarchy({ restore_focus = false })
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
		group = state.augroup,
		callback = function(args)
			if not state.open or state.session_id ~= session_id then
				return
			end

			local changed_buf = args.buf
			local relevant = changed_buf == state.source_buf or state.relevant_buffers[changed_buf] == true

			if not relevant then
				return
			end

			vim.schedule(function()
				if state.open and state.session_id == session_id then
					notify(
						"İlgili bir LSP buffer'ı değiştiği için Type Hierarchy kapatıldı; yeniden açın.",
						vim.log.levels.INFO
					)
					close_hierarchy({ restore_focus = false })
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd("TabLeave", {
		group = state.augroup,
		callback = function()
			if not state.open or state.session_id ~= session_id then
				return
			end

			vim.schedule(function()
				if state.open and state.session_id == session_id then
					close_hierarchy({ restore_focus = false })
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
		group = state.augroup,
		callback = function(args)
			if not state.open or state.session_id ~= session_id then
				return
			end

			local affected_buf = args.buf
			local relevant = affected_buf == state.source_buf or state.relevant_buffers[affected_buf] == true

			if not relevant then
				return
			end

			vim.schedule(function()
				if state.open and state.session_id == session_id then
					close_hierarchy({ restore_focus = false })
				end
			end)
		end,
	})
end

-- ─────────────────────────────────────────────────────────────
-- Transactional UI Open
-- ─────────────────────────────────────────────────────────────

local function open_ui(client, item, source_buf, source_win, source_file, source_tick)
	local g, geometry_err = geometry()

	if not g then
		notify(geometry_err or "Terminal Type Hierarchy için çok küçük.", vim.log.levels.WARN)
		return
	end

	if not valid_item(item) then
		notify("LSP geçerli bir TypeHierarchyItem döndürmedi.", vim.log.levels.WARN)
		return
	end

	if not loaded_buf(source_buf) or not valid_win(source_win) then
		notify("Kaynak buffer veya pencere artık geçerli değil.", vim.log.levels.WARN)
		return
	end

	if vim.api.nvim_win_get_buf(source_win) ~= source_buf then
		notify(
			"Type Hierarchy hazırlanırken kaynak pencerenin buffer'ı değişti; yeniden açın.",
			vim.log.levels.INFO
		)
		return
	end

	if source_tick and vim.api.nvim_buf_get_changedtick(source_buf) ~= source_tick then
		notify("Type Hierarchy hazırlanırken kaynak buffer değişti; yeniden açın.", vim.log.levels.INFO)
		return
	end

	local live_client = vim.lsp.get_client_by_id(client.id)

	if not live_client or live_client:is_stopped() then
		notify("Type Hierarchy LSP client artık çalışmıyor.", vim.log.levels.WARN)
		return
	end

	if not client_attached_to_buffer(live_client, source_buf) then
		notify("Type Hierarchy LSP client kaynak buffer'dan ayrılmış.", vim.log.levels.WARN)
		return
	end

	if not live_client:supports_method(PREPARE_METHOD, source_buf) then
		notify("LSP Type Hierarchy desteğini artık sunmuyor.", vim.log.levels.WARN)
		return
	end

	state.session_id = state.session_id + 1
	local session_id = state.session_id

	state.direction = "subtypes"
	state.source_buf = source_buf
	state.source_win = source_win
	state.source_file = source_file
	state.source_tick = source_tick or vim.api.nvim_buf_get_changedtick(source_buf)
	state.active_client_id = live_client.id
	state.encoding = live_client.offset_encoding or "utf-16"
	state.project_root, state.roots = workspace.collect_roots(live_client, source_file)
	state.root_item = item
	state.relevant_buffers = {}
	mark_relevant_buffer(source_buf)
	state.trees = {
		supertypes = nil,
		subtypes = root_node(item, "subtypes"),
	}
	state.visible = {}
	state.line_map = {}
	state.key_to_line = {}
	state.pending_requests = {}
	state.request_generation = {
		supertypes = 0,
		subtypes = 0,
	}
	state.preview_file = nil
	state.preview_token = nil
	state.preview_ft = nil
	state.bufs = {}
	state.wins = {}
	state.augroup = nil

	local staged_bufs = {}
	local staged_wins = {}

	local ok, err = xpcall(function()
		local prefix = string.format("demir://type-hierarchy/%d/", session_id)

		staged_bufs.header = create_buffer(prefix .. "header")
		staged_bufs.list = create_buffer(prefix .. "list")
		staged_bufs.preview = create_buffer(prefix .. "preview")
		staged_bufs.footer = create_buffer(prefix .. "footer")

		staged_wins.header = vim.api.nvim_open_win(
			staged_bufs.header,
			false,
			float_config(g.row, g.col, g.header_width, g.header_height, " 󰠱  Type Hierarchy ", false)
		)

		staged_wins.list = vim.api.nvim_open_win(
			staged_bufs.list,
			true,
			float_config(g.body_row, g.col, g.left_width, g.body_height, " 󰠱  Types ", true)
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
		render_list(state.trees.subtypes.key)
		render_preview()
		render_header()
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

		report_internal_error("Type Hierarchy transactional açılışı başarısız", err)
		return
	end

	state.open = true
	state.closing = false

	refresh(state.trees.subtypes.key)
	ensure_root_loaded("subtypes")
end

-- ─────────────────────────────────────────────────────────────
-- Prepare Type Hierarchy
-- ─────────────────────────────────────────────────────────────

local function format_prepare_item(item)
	local info = kind_info(item.kind)
	local detail = one_line(item.detail)
	local suffix = detail ~= "" and ("  " .. detail) or ""
	return string.format("%s  %s%s  ·  %s", info.icon, one_line(item.name), suffix, item_location_text(item))
end

local function prepare_from_cursor()
	if state.open then
		close_hierarchy()
		return
	end

	if state.preparing then
		cancel_prepare_request()
		notify("Type Hierarchy hazırlama/seçim işlemi iptal edildi.", vim.log.levels.INFO)
		return
	end

	local source_buf = vim.api.nvim_get_current_buf()
	local source_win = vim.api.nvim_get_current_win()
	local source_file = normalize_path(vim.api.nvim_buf_get_name(source_buf))
	local source_tick = vim.api.nvim_buf_get_changedtick(source_buf)

	if source_file == "" or vim.bo[source_buf].buftype ~= "" then
		notify("Type Hierarchy yalnızca dosyaya bağlı normal buffer'larda açılabilir.", vim.log.levels.WARN)
		return
	end

	local client = preferred_client_for_buffer(source_buf, PREPARE_METHOD)

	if not client then
		notify("Bu buffer'a Type Hierarchy destekleyen LSP bağlı değil.", vim.log.levels.WARN)
		return
	end

	local g, geometry_err = geometry()

	if not g then
		notify(geometry_err or "Terminal Type Hierarchy için çok küçük.", vim.log.levels.WARN)
		return
	end

	local ok_params, params = pcall(vim.lsp.util.make_position_params, source_win, client.offset_encoding or "utf-16")

	if not ok_params then
		report_internal_error("Type Hierarchy position params oluşturulamadı", params)
		return
	end

	state.launch_generation = state.launch_generation + 1
	local generation = state.launch_generation
	state.preparing = true

	local completed = false
	local request_id = nil

	local function handler(err, result)
		completed = true

		if state.prepare_request and state.prepare_request.id == request_id then
			state.prepare_request = nil
		end

		if generation ~= state.launch_generation then
			return
		end

		if
			not loaded_buf(source_buf)
			or not valid_win(source_win)
			or vim.api.nvim_win_get_buf(source_win) ~= source_buf
			or vim.api.nvim_buf_get_changedtick(source_buf) ~= source_tick
		then
			state.preparing = false
			notify("Type Hierarchy hazırlanırken kaynak bağlam değişti; yeniden açın.", vim.log.levels.INFO)
			return
		end

		if err then
			state.preparing = false
			notify("Type Hierarchy hazırlanamadı: " .. one_line(err.message or err), vim.log.levels.WARN)
			return
		end

		local items = {}

		for _, item in ipairs(safe_table(result)) do
			if valid_item(item) then
				table.insert(items, item)
			end
		end

		if #items == 0 then
			state.preparing = false
			notify(
				"İmleç konumunda tür hiyerarşisi oluşturulabilecek bir sembol bulunamadı.",
				vim.log.levels.INFO
			)
			return
		end

		local function commit(item)
			if generation ~= state.launch_generation then
				return
			end

			if
				not loaded_buf(source_buf)
				or not valid_win(source_win)
				or vim.api.nvim_win_get_buf(source_win) ~= source_buf
				or vim.api.nvim_buf_get_changedtick(source_buf) ~= source_tick
			then
				notify(
					"Type Hierarchy seçimi tamamlanmadan kaynak bağlam değişti; yeniden açın.",
					vim.log.levels.INFO
				)
				return
			end

			open_ui(client, item, source_buf, source_win, source_file, source_tick)
		end

		if #items == 1 then
			state.preparing = false
			commit(items[1])
			return
		end

		-- Çoklu prepare sonucunda seçim UI'sı açık kaldığı sürece `preparing`
		-- true kalır. Böylece kullanıcı aynı komutu tekrar çalıştırırsa eski seçim
		-- generation ile geçersizleşir ve sonradan eski bir UI oturumu açamaz.
		local select_ok, select_err = pcall(vim.ui.select, items, {
			prompt = "Type Hierarchy öğesi seç:",
			kind = "typehierarchy",
			format_item = format_prepare_item,
		}, function(choice)
			if generation ~= state.launch_generation then
				return
			end

			state.preparing = false

			if choice then
				commit(choice)
			end
		end)

		if not select_ok then
			state.preparing = false
			report_internal_error("Type Hierarchy seçim arayüzü açılamadı", select_err)
		end
	end

	local call_ok, status, id = pcall(client.request, client, PREPARE_METHOD, params, handler, source_buf)

	if not call_ok then
		state.preparing = false
		state.prepare_request = nil
		report_internal_error("Type Hierarchy hazırlama isteği gönderilirken hata oluştu", status)
		notify("Type Hierarchy hazırlama isteği gönderilemedi.", vim.log.levels.WARN)
		return
	end

	request_id = id

	if status ~= true or (not completed and not request_id) then
		state.preparing = false
		state.prepare_request = nil
		notify("Type Hierarchy hazırlama isteği gönderilemedi.", vim.log.levels.WARN)
		return
	end

	if request_id and not completed then
		state.prepare_request = {
			client = client,
			id = request_id,
			generation = generation,
		}
	end
end

M.open = prepare_from_cursor

function M.close()
	if state.preparing then
		cancel_prepare_request()
		return
	end

	close_hierarchy()
end

-- ─────────────────────────────────────────────────────────────
-- Public Mapping / Command
-- ─────────────────────────────────────────────────────────────
--
-- Kullanıcının veya başka bir plugin'in aynı global mapping/command'i daha
-- önce sahiplenmiş olması durumunda sessizce üzerine yazmıyoruz. Sağ tık menüsü
-- ve :DemirTypeHierarchy komutu birbirinden bağımsız erişim yolları olarak
-- kalır; mevcut config'te <leader>lt boş olsa da bu guard gelecekteki plugin
-- eklemelerine karşı çakışmayı önler.
-- ─────────────────────────────────────────────────────────────

local mapping_ok, mapping_err = pcall(vim.keymap.set, "n", "<leader>lt", M.open, {
	desc = "Tür hiyerarşisi",
	unique = true,
})

if not mapping_ok then
	report_internal_error("<leader>lt mapping'i kurulmadı; mevcut mapping korundu", mapping_err)
end

local command_exists = vim.fn.exists(":DemirTypeHierarchy") == 2

if not command_exists then
	vim.api.nvim_create_user_command("DemirTypeHierarchy", M.open, {
		desc = "Open Demir Type Hierarchy",
	})
end

return M
