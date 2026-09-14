local render_markdown = require("render-markdown")

-- ─────────────────────────────────────────────────────────────
-- Render Markdown
-- ─────────────────────────────────────────────────────────────

render_markdown.setup({
	enabled = true,

	-- Normal Markdown belgeleriyle birlikte CopilotChat
	-- cevaplarını da aynı render sistemiyle göster.
	file_types = {
		"markdown",
		"copilot-chat",
	},

	-- Normal modda güzel render.
	-- Insert moduna girince Markdown sözdizimi tekrar görünür.
	render_modes = {
		"n",
		"c",
		"t",
	},

	-- İmleç render edilmiş öğenin üzerine geldiğinde
	-- kaynak Markdown sözdizimini tekrar gösterme.
	anti_conceal = {
		enabled = false,
	},

	-- Blink zaten LSP completion kullandığı için
	-- checkbox ve callout completion'ları da gelsin.
	completions = {
		lsp = {
			enabled = true,
		},
	},

	-- Sol sign column'u Markdown süsleriyle doldurma.
	-- Diagnostic / breakpoint alanımız temiz kalsın.
	sign = {
		enabled = false,
	},

	-- ─────────────────────────────────────────────────────────
	-- Başlıklar
	-- ─────────────────────────────────────────────────────────

	heading = {
		enabled = true,

		sign = false,

		icons = {
			"󰲡 ",
			"󰲣 ",
			"󰲥 ",
			"󰲧 ",
			"󰲩 ",
			"󰲫 ",
		},

		position = "overlay",

		-- Başlıklar tam satır boyunca görsel bir blok olsun.
		width = "full",

		left_margin = 0,
		left_pad = 1,
		right_pad = 1,

		backgrounds = {
			"RenderMarkdownH1Bg",
			"RenderMarkdownH2Bg",
			"RenderMarkdownH3Bg",
			"RenderMarkdownH4Bg",
			"RenderMarkdownH5Bg",
			"RenderMarkdownH6Bg",
		},

		foregrounds = {
			"RenderMarkdownH1",
			"RenderMarkdownH2",
			"RenderMarkdownH3",
			"RenderMarkdownH4",
			"RenderMarkdownH5",
			"RenderMarkdownH6",
		},
	},

	-- ─────────────────────────────────────────────────────────
	-- Kod Blokları
	-- ─────────────────────────────────────────────────────────

	code = {
		enabled = true,

		sign = false,

		conceal_delimiters = true,

		language = true,
		position = "left",

		language_icon = true,
		language_name = true,
		language_info = true,

		-- Kod blokları belge içinde kart gibi dursun.
		width = "full",

		left_margin = 0,
		left_pad = 2,
		right_pad = 2,

		min_width = 45,

		border = "thin",

		inline = true,
	},

	-- ─────────────────────────────────────────────────────────
	-- Listeler
	-- ─────────────────────────────────────────────────────────

	bullet = {
		enabled = true,

		icons = {
			"●",
			"○",
			"◆",
			"◇",
		},

		left_pad = 0,
		right_pad = 1,
	},

	-- ─────────────────────────────────────────────────────────
	-- Checkbox
	-- ─────────────────────────────────────────────────────────

	checkbox = {
		enabled = true,

		bullet = false,

		left_pad = 0,
		right_pad = 1,

		unchecked = {
			icon = "󰄱 ",
			highlight = "RenderMarkdownUnchecked",
		},

		checked = {
			icon = "󰱒 ",
			highlight = "RenderMarkdownChecked",

			scope_highlight = "@markup.strikethrough",
		},

		custom = {
			todo = {
				raw = "[-]",
				rendered = "󰥔 ",
				highlight = "RenderMarkdownTodo",
			},
		},
	},

	-- ─────────────────────────────────────────────────────────
	-- Ayraç
	-- ─────────────────────────────────────────────────────────

	dash = {
		enabled = true,
		icon = "─",
		width = "full",
	},

	-- ─────────────────────────────────────────────────────────
	-- Blockquote / Callout
	-- ─────────────────────────────────────────────────────────

	quote = {
		enabled = true,
	},

	callout = {
		note = {
			raw = "[!NOTE]",
			rendered = "󰋽 Note",
			highlight = "RenderMarkdownInfo",
		},

		tip = {
			raw = "[!TIP]",
			rendered = "󰌶 Tip",
			highlight = "RenderMarkdownSuccess",
		},

		important = {
			raw = "[!IMPORTANT]",
			rendered = "󰅾 Important",
			highlight = "RenderMarkdownHint",
		},

		warning = {
			raw = "[!WARNING]",
			rendered = "󰀪 Warning",
			highlight = "RenderMarkdownWarn",
		},

		caution = {
			raw = "[!CAUTION]",
			rendered = "󰳦 Caution",
			highlight = "RenderMarkdownError",
		},
	},

	-- ─────────────────────────────────────────────────────────
	-- Tablolar
	-- ─────────────────────────────────────────────────────────

	pipe_table = {
		enabled = true,

		cell = "padded",
		padding = 1,

		border_enabled = true,

		alignment_indicator = "━",
	},

	-- ─────────────────────────────────────────────────────────
	-- Render Sırasında Pencere Seçenekleri
	-- ─────────────────────────────────────────────────────────

	win_options = {
		conceallevel = {
			default = vim.o.conceallevel,
			rendered = 3,
		},

		concealcursor = {
			default = vim.o.concealcursor,
			rendered = "",
		},
	},

	-- CopilotChat, LSP hover vb. nofile buffer'larda tam geniş
	-- kod bloklarının gereksiz padding üretmesini engelle.
	overrides = {
		buftype = {
			nofile = {
				code = {
					left_pad = 1,
					right_pad = 1,
				},

				sign = {
					enabled = false,
				},
			},
		},
	},
})

-- ─────────────────────────────────────────────────────────────
-- Markdown / AI Sohbet Pencere Davranışı
-- ─────────────────────────────────────────────────────────────

local group = vim.api.nvim_create_augroup("DemirMarkdown", {
	clear = true,
})

vim.api.nvim_create_autocmd("FileType", {
	group = group,

	pattern = {
		"markdown",
		"copilot-chat",
	},

	callback = function()
		local opt = vim.opt_local

		-- Uzun metinleri pencere içinde sar.
		opt.wrap = true

		-- Kelimenin ortasından kırma.
		opt.linebreak = true

		-- Sarılmış satırların görsel girintisini koru.
		opt.breakindent = true

		-- Belge / sohbet okurken yatay kaydırma istemiyoruz.
		opt.sidescrolloff = 0

		-- Fiziksel satır uzunluğunu zorla bölme.
		opt.textwidth = 0
	end,
})

-- ─────────────────────────────────────────────────────────────
-- Render Aç / Kapat
-- ─────────────────────────────────────────────────────────────

vim.keymap.set("n", "<leader>M", "<cmd>RenderMarkdown toggle<CR>", {
	desc = "Markdown görünümü",
})
