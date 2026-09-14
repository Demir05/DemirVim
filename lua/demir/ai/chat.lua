local CopilotChat = require("CopilotChat")

-- ─────────────────────────────────────────────────────────────
-- Copilot Chat
-- ─────────────────────────────────────────────────────────────

CopilotChat.setup({
	-- 4.x stabil sürüm kendi varsayılan modelini kullansın.
	-- v4.7.4 varsayılanı: gpt-4.1
	--
	-- Farklı model:
	-- Space+i m
	language = "Turkish",

	-- Kod görevlerinde daha tutarlı cevaplar.
	temperature = 0.1,

	-- Visual seçim AI bağlamı olarak kullanılabilir.
	selection = "visual",

	-- #file, #buffer, @copilot, /Explain vb.
	-- token'larda completion.
	chat_autocomplete = true,

	-- Visual olarak AI'a gönderilen bölgeyi kaynak kodda göster.
	highlight_selection = true,

	-- Kod değişikliklerini okunabilir unified diff olarak göster.
	diff = "unified",

	-- Prompt içerisinde belirtilen model / resource vb.
	-- tercihlerin sohbet süresince korunmasına izin ver.
	remember_as_sticky = true,

	-- Tool zincirindeki bir işlem başarısız olursa devam edip
	-- anlamsız sonuç üretme.
	stop_on_function_failure = true,

	-- Gereksiz debug mesajlarıyla UI'ı kirletme.
	log_level = "warn",

	-- ─────────────────────────────────────────────────────────
	-- Sağ AI Paneli
	-- ─────────────────────────────────────────────────────────

	window = {
		layout = "vertical",

		-- Kod alanını öldürmeden rahat sohbet genişliği.
		width = 0.42,

		title = "   Copilot Chat ",
	},

	-- ─────────────────────────────────────────────────────────
	-- Mesaj Görünümü
	-- ─────────────────────────────────────────────────────────

	headers = {
		user = "  Sen",
		assistant = "  Copilot",
		tool = "󰒓  Araç",
	},

	separator = "────────────────────────────────",

	-- Mesajları render-markdown.nvim güzelleştiriyor.
	highlight_headers = false,

	-- Sürekli yardım metni gösterme.
	show_help = false,

	-- Chat'i metin editörü değil gerçek sohbet gibi göster.
	show_folds = false,
	auto_fold = false,

	-- Streaming cevap geldikçe aşağıyı takip et.
	auto_follow_cursor = true,

	-- Panel açıldığında hemen yazabil.
	auto_insert_mode = true,

	-- Yeni prompt alanına otomatik git.
	insert_at_end = true,

	-- Yeni soru eski konuşmayı silmesin.
	clear_chat_on_new_prompt = false,
})

-- ─────────────────────────────────────────────────────────────
-- Highlight Katmanı
-- ─────────────────────────────────────────────────────────────
--
-- Sabit hex renkler kullanmıyoruz.
-- Gruber Darker'ın kendi renk dilinden türetiyoruz.
-- ─────────────────────────────────────────────────────────────

local highlights = {
	CopilotChatHeader = "Identifier",
	CopilotChatSeparator = "Comment",

	CopilotChatSelection = "Visual",
	CopilotChatStatus = "DiagnosticInfo",
	CopilotChatHelp = "Comment",

	CopilotChatResource = "Directory",
	CopilotChatTool = "Function",
	CopilotChatPrompt = "Keyword",
	CopilotChatModel = "Type",
	CopilotChatUri = "Underlined",

	CopilotChatAnnotation = "Comment",
	CopilotChatAnnotationHeader = "Special",
}

for name, target in pairs(highlights) do
	vim.api.nvim_set_hl(0, name, {
		link = target,
	})
end

vim.api.nvim_set_hl(0, "DemirAIWinBar", {
	link = "Identifier",
})

vim.api.nvim_set_hl(0, "DemirAIWinBarHint", {
	link = "Comment",
})

-- ─────────────────────────────────────────────────────────────
-- Chat Penceresini Stilize Et
-- ─────────────────────────────────────────────────────────────

local uuid_pattern = [[\s\+([0-9A-Fa-f]\{8}-[0-9A-Fa-f]\{4}-[0-9A-Fa-f]\{4}-[0-9A-Fa-f]\{4}-[0-9A-Fa-f]\{12})$]]

local function style_chat_window(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end

	local buf = vim.api.nvim_win_get_buf(win)

	if vim.bo[buf].filetype ~= "copilot-chat" then
		return
	end

	-- ─────────────────────────────────────────────────────────
	-- Editör Gürültüsünü Kaldır
	-- ─────────────────────────────────────────────────────────

	vim.api.nvim_set_option_value("number", false, { win = win })

	vim.api.nvim_set_option_value("relativenumber", false, { win = win })

	vim.api.nvim_set_option_value("signcolumn", "no", { win = win })

	vim.api.nvim_set_option_value("foldcolumn", "0", { win = win })

	vim.api.nvim_set_option_value("statuscolumn", "", { win = win })

	vim.api.nvim_set_option_value("cursorline", false, { win = win })

	vim.api.nvim_set_option_value("colorcolumn", "", { win = win })

	-- ─────────────────────────────────────────────────────────
	-- Okuma Deneyimi
	-- ─────────────────────────────────────────────────────────

	vim.api.nvim_set_option_value("wrap", true, { win = win })

	vim.api.nvim_set_option_value("linebreak", true, { win = win })

	vim.api.nvim_set_option_value("breakindent", true, { win = win })

	vim.api.nvim_set_option_value("scrolloff", 2, { win = win })

	vim.api.nvim_set_option_value("sidescrolloff", 0, { win = win })

	-- Sağ AI panelinin genişliği yanlışlıkla bozulmasın.
	vim.api.nvim_set_option_value("winfixwidth", true, { win = win })

	-- ─────────────────────────────────────────────────────────
	-- UUID Gizleme
	-- ─────────────────────────────────────────────────────────
	--
	-- CopilotChat mesaj kimliğini buffer'dan SİLMİYORUZ.
	-- Yalnızca görsel olarak conceal ediyoruz.
	-- Plugin kendi iç kimliğini kullanmaya devam edebilir.
	-- ─────────────────────────────────────────────────────────

	vim.api.nvim_set_option_value("conceallevel", 2, { win = win })

	vim.api.nvim_set_option_value("concealcursor", "nivc", { win = win })

	-- ─────────────────────────────────────────────────────────
	-- VS Code Benzeri Üst Çubuk
	-- ─────────────────────────────────────────────────────────

	vim.api.nvim_set_option_value(
		"winbar",
		"%#DemirAIWinBar#   Copilot Chat %*"
			.. "%="
			.. "%#DemirAIWinBarHint#"
			.. " Ctrl+S Gönder"
			.. "  ·  Tab Bağlam"
			.. "  ·  q Kapat "
			.. "%*",
		{ win = win }
	)

	vim.api.nvim_set_option_value(
		"winhighlight",
		"Normal:Normal,"
			.. "NormalNC:Normal,"
			.. "WinSeparator:FloatBorder,"
			.. "WinBar:Normal,"
			.. "WinBarNC:Normal,"
			.. "EndOfBuffer:Normal",
		{ win = win }
	)

	-- matchadd pencereye özeldir.
	vim.api.nvim_win_call(win, function()
		if vim.w.demir_ai_uuid_match then
			pcall(vim.fn.matchdelete, vim.w.demir_ai_uuid_match)
		end

		vim.w.demir_ai_uuid_match = vim.fn.matchadd("Conceal", uuid_pattern, 100, -1, {
			conceal = "",
		})
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Chat Buffer Otomasyonu
-- ─────────────────────────────────────────────────────────────

local group = vim.api.nvim_create_augroup("DemirCopilotChat", {
	clear = true,
})

local function style_buffer_windows(buf)
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		for _, win in ipairs(vim.fn.win_findbuf(buf)) do
			style_chat_window(win)
		end
	end)
end

vim.api.nvim_create_autocmd("FileType", {
	group = group,
	pattern = "copilot-chat",

	callback = function(args)
		local opt = vim.opt_local

		opt.list = false
		opt.spell = false
		opt.textwidth = 0

		style_buffer_windows(args.buf)
	end,
})

vim.api.nvim_create_autocmd({
	"BufWinEnter",
	"WinEnter",
}, {
	group = group,

	callback = function(args)
		if vim.bo[args.buf].filetype ~= "copilot-chat" then
			return
		end

		style_buffer_windows(args.buf)
	end,
})

-- ─────────────────────────────────────────────────────────────
-- Hızlı AI
-- ─────────────────────────────────────────────────────────────

local function quick_chat()
	vim.ui.input({
		prompt = "  Copilot: ",
	}, function(input)
		if not input or vim.trim(input) == "" then
			return
		end

		CopilotChat.open({
			resources = {
				"buffer",
			},
		})

		CopilotChat.ask(input, {
			resources = {
				"buffer",
			},
		})
	end)
end

-- ─────────────────────────────────────────────────────────────
-- Kısayollar
-- ─────────────────────────────────────────────────────────────

local map = vim.keymap.set

-- Space+i
-- Sağ AI panelini aç / kapat.
map({ "n", "v" }, "<leader>i", function()
	CopilotChat.toggle()
end, {
	desc = "AI sohbeti",
})

-- Space+i q
-- VS Code Quick Chat benzeri:
-- küçük input açar, mevcut buffer'ı otomatik bağlama ekler.
map("n", "<leader>iq", quick_chat, {
	desc = "AI hızlı soru",
})

-- Space+i n
-- Yeni, temiz konuşma.
map("n", "<leader>in", function()
	CopilotChat.reset()
	CopilotChat.open()
end, {
	desc = "Yeni AI sohbeti",
})

-- Space+i m
-- Snacks üzerinden model seçici.
map("n", "<leader>im", function()
	CopilotChat.select_model()
end, {
	desc = "AI modeli",
})

-- Space+i p
-- Explain / Review / Fix / Optimize / Docs / Tests.
map({ "n", "v" }, "<leader>ip", function()
	CopilotChat.select_prompt()
end, {
	desc = "AI eylemleri",
})

-- Space+i l
-- Geçmiş sohbet yükle.
map("n", "<leader>il", "<cmd>CopilotChatLoad<CR>", {
	desc = "AI sohbet geçmişi",
})

-- Space+i s
-- Sohbeti kaydet.
map("n", "<leader>is", "<cmd>CopilotChatSave<CR>", {
	desc = "AI sohbetini kaydet",
})

-- Space+i x
-- Streaming cevabı durdur.
map("n", "<leader>ix", function()
	CopilotChat.stop()
end, {
	desc = "AI yanıtını durdur",
})

-- ─────────────────────────────────────────────────────────────
-- Seçili Kod İçin AI
-- ─────────────────────────────────────────────────────────────

map("x", "<leader>ie", "<cmd>CopilotChatExplain<CR>", {
	desc = "AI: Seçimi açıkla",
})

map("x", "<leader>ir", "<cmd>CopilotChatReview<CR>", {
	desc = "AI: Seçimi incele",
})

map("x", "<leader>if", "<cmd>CopilotChatFix<CR>", {
	desc = "AI: Seçimi düzelt",
})

map("x", "<leader>it", "<cmd>CopilotChatTests<CR>", {
	desc = "AI: Test üret",
})

map("x", "<leader>io", "<cmd>CopilotChatOptimize<CR>", {
	desc = "AI: Seçimi optimize et",
})

map("x", "<leader>id", "<cmd>CopilotChatDocs<CR>", {
	desc = "AI: Dokümantasyon yaz",
})
