local wk = require("which-key")

wk.setup({
	preset = "modern",

	delay = 200,

	icons = {
		mappings = true,
	},
})

wk.add({
	{
		"<leader>e",
		desc = "Dosya gezgini",
	},

	{
		"<leader>f",
		desc = "Dosya bul",
	},

	{
		"<leader>?",
		desc = "Tuş rehberi",
	},

	{
		"<leader>p",
		desc = "Proje problemleri",
	},

	{
		"<leader>pb",
		desc = "Buffer problems",
	},

	{
		"<leader>pe",
		desc = "Errors only",
	},

	{
		"<leader>b",
		desc = "Derleme merkezi",
	},

	{
		"<leader>m",
		desc = "Dosyayı biçimlendir",
	},

	{
		"<leader>M",
		desc = "Markdown görünümü",
	},

	{
		"<leader>i",
		desc = "AI sohbeti",
	},

	{
		"<leader>s",
		desc = "Symbol Center",
	},

	-- ─────────────────────────────────────────────────────────────
	-- LSP / Semantic Tools
	-- ─────────────────────────────────────────────────────────────

	{
		"<leader>l",
		group = "LSP / Semantic",
	},

	{
		"<leader>lh",
		desc = "Çağrı hiyerarşisi",
	},
})
