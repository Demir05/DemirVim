# DemirVim

CachyOS / Arch Linux üzerinde çalışan, native `vim.pack` kullanan kişisel Neovim C/C++ development environment yapılandırması.

DemirVim'in amacı yalnızca klasik IDE özelliklerini Neovim'e taşımak değildir. Yapılandırma; düşük gecikmeli LSP analizi, `clangd + clang-tidy`, whole-project statik analiz, Clang Static Analyzer, CMake tabanlı build akışı, GDB/DAP debugging, semantic navigation, Project Problems Center, dosya arama, terminal ve GitHub Copilot katmanlarını tek bir çalışma ortamında birleştirir.

C/C++ tarafında iki ayrı analiz katmanı bulunur:

- **Live analysis:** `clangd + clang-tidy + Include Cleaner`
- **Deep analysis:** `compile_commands.json` tabanlı whole-project `clang-tidy + Clang Static Analyzer`

Deep analysis sonuçları live clangd diagnostics ile Project Problems Center içinde birleştirilir.

## Özellikler

### Editor ve UI

- Native Neovim paket yöneticisi: `vim.pack`
- Gruber Darker renk teması
- Nerd Font ikonları
- Snacks explorer, picker, grep, terminal ve notification sistemi
- Context-aware sağ tık menüsü
- Which-key tuş yardım menüsü
- Lualine durum çubuğu
- Tree-sitter sözdizimi ayrıştırma
- Blink completion ve snippet sistemi
- Conform tabanlı biçimlendirme
- Render Markdown desteği
- Trouble tabanlı diagnostic görünümleri
- Proje içi tuş rehberi: `:Keys` veya `<Space>?`

### C/C++ semantic tooling

- Native Neovim LSP
- `clangd`
- Background indexing
- Live `clang-tidy`
- Include Cleaner
- `compile_commands.json` desteği
- Definition / declaration / references / implementation / type definition
- Rename ve code actions
- Call Hierarchy
- Type Hierarchy
- Symbol Center
- Project-aware diagnostics

### Deep C++ analysis

- Whole-project `compile_commands.json` analizi
- Standalone `clang-tidy` worker süreçleri
- Clang Static Analyzer
- Path-sensitive ve inter-procedural bulgular
- Bounded parallel analysis
- Multi-build compilation database seçimi
- Project-wide diagnostic deduplication
- Atomic result commit
- Stale-result detection
- Source / config / compilation database mutation koruması
- Cancellable analysis
- Static Analyzer path-note gösterimi
- Live LSP quick-fix ile deep-only bulguların ayrılması

### Build ve Debug

- CMake proje desteği
- CMake Tools entegrasyonu
- Build Center
- Build Profile seçimi
- GDB tabanlı `nvim-dap`
- DAP View
- Breakpoint, step, pause, restart, terminate ve watch akışları
- Debug Center

### AI

- GitHub Copilot
- Blink completion entegrasyonu
- Copilot Chat

## Sistem gereksinimleri

Bu yapılandırma CachyOS / Arch Linux için hazırlanmıştır.

Önerilen temel ortam:

- Neovim 0.12+
- Git
- GCC
- Clang
- CMake
- Ninja
- GDB
- `ripgrep`
- `fd`
- Tree-sitter CLI
- Wayland üzerinde `wl-clipboard`
- Bir Nerd Font
- Gerekli language server'lar

C/C++ analysis katmanı için özellikle şunlar gereklidir:

```text
clangd
clang-format
clang-tidy
```

## Hızlı kurulum

### 1. Bağımlılıkları kur

Depoda bulunan kurulum betiğini çalıştır:

```bash
chmod +x install-deps.sh
./install-deps.sh
```

Betiğin yaptığı kurulum kabaca şu gruplardan oluşur:

- Neovim ve paket indirme araçları
- Snacks için `ripgrep` ve `fd`
- Tree-sitter için `tree-sitter-cli` ve C derleyicisi
- C/C++ geliştirme araçları
- Language server'lar
- Bash analiz / biçimlendirme araçları
- Nerd Font
- Wayland clipboard desteği

CMake language server Arch resmi deposunda bulunmadığı durumda `paru` veya `yay` üzerinden AUR kullanılabilir.

### 2. Yapılandırmayı yerleştir

Mevcut Neovim yapılandırmasını yedeklemek istersen:

```bash
mv ~/.config/nvim ~/.config/nvim.backup
```

Ardından:

```bash
git clone https://github.com/Demir05/DemirVim.git ~/.config/nvim
```

### 3. Clang profillerini etkinleştir

DemirVim üç kullanıcı-seviyesi Clang profilini repository içinde sürüm kontrolünde tutar:

```text
profiles/clangd/config.yaml
profiles/clang-tidy/default.yaml
profiles/clang-tidy/deep.yaml
```

Aktif sistem yolları:

```text
~/.config/clangd/config.yaml
~/.clang-tidy
~/.config/clang-tidy/deep.yaml
```

Mevcut dosyaların varsa önce yedekle:

```bash
mkdir -p ~/.config/clangd ~/.config/clang-tidy

[ ! -e ~/.config/clangd/config.yaml ] && [ ! -L ~/.config/clangd/config.yaml ] || \
    mv ~/.config/clangd/config.yaml ~/.config/clangd/config.yaml.backup

[ ! -e ~/.clang-tidy ] && [ ! -L ~/.clang-tidy ] || \
    mv ~/.clang-tidy ~/.clang-tidy.backup

[ ! -e ~/.config/clang-tidy/deep.yaml ] && [ ! -L ~/.config/clang-tidy/deep.yaml ] || \
    mv ~/.config/clang-tidy/deep.yaml ~/.config/clang-tidy/deep.yaml.backup
```

Sonra repository profillerini aktif konumlara bağla:

```bash
ln -s ~/.config/nvim/profiles/clangd/config.yaml \
    ~/.config/clangd/config.yaml

ln -s ~/.config/nvim/profiles/clang-tidy/default.yaml \
    ~/.clang-tidy

ln -s ~/.config/nvim/profiles/clang-tidy/deep.yaml \
    ~/.config/clang-tidy/deep.yaml
```

Böylece `git pull` sonrasında Clang profile'ları da repository ile birlikte güncellenir.

### 4. Neovim'i ilk kez başlat

```bash
nvim
```

İlk açılışta `vim.pack` gerekli eklentileri indirir.

Tree-sitter parser'ları da yapılandırmada tanımlanan dillere göre kurulur. İlk açılış normalden biraz daha uzun sürebilir.

## GitHub Copilot

Copilot tamamlamaları Blink menüsüne entegredir.

İlk kurulumdan sonra Neovim içinde:

```vim
:Copilot auth
```

komutunu çalıştır ve GitHub hesabınla giriş yap.

Copilot'un ayrı inline suggestion arayüzü yerine completion akışı Blink üzerinden birleştirilir. Copilot Chat ayrıca `ai/chat.lua` üzerinden yapılandırılır.

## Language Server'lar

| Dil / dosya türü | Language server | Sistem paketi |
| --- | --- | --- |
| C / C++ | `clangd` | `clang` |
| Lua | `lua_ls` | `lua-language-server` |
| JSON | `jsonls` | `vscode-json-languageserver` |
| YAML | `yamlls` | `yaml-language-server` |
| Markdown | `marksman` | `marksman` |
| Bash | `bashls` | `bash-language-server` |
| CMake | `cmake` | `cmake-language-server` |

`clang` paketi ayrıca `clang-format` ve `clang-tidy` araçlarını sağlar.

## C/C++ analysis architecture

```text
                         C/C++ Source
                              │
                 ┌────────────┴────────────┐
                 │                         │
                 ▼                         ▼
            Live Analysis             Deep Analysis
                 │                         │
              clangd                compile_commands.json
                 │                         │
       clang-tidy / Include Cleaner       clang-tidy
                 │                  Clang Static Analyzer
                 │                         │
                 └────────────┬────────────┘
                              ▼
                       Problems Center
```

### Live analysis

Neovim içindeki `clangd.lua` clangd process politikasını yönetir.

Kullanıcı-seviyesi clangd runtime policy:

```text
profiles/clangd/config.yaml
→ ~/.config/clangd/config.yaml
```

Live clang-tidy fallback policy:

```text
profiles/clang-tidy/default.yaml
→ ~/.clang-tidy
```

Bir proje kendi `.clang-tidy` dosyasını içeriyorsa proje-local politika kullanılabilir.

### Deep analysis

Deep profile:

```text
profiles/clang-tidy/deep.yaml
→ ~/.config/clang-tidy/deep.yaml
```

Deep analyzer:

```text
lua/demir/analysis/clang_tidy.lua
```

Deep scan komutları:

```vim
:DemirAnalyzeProject
:DemirAnalyzeProject 4
:DemirAnalyzeProject!
:DemirCancelAnalysis
:DemirClearAnalysis
:DemirAnalysisStatus
```

`4`, worker sayısını belirtir.

`!`, değiştirilmiş proje buffer'larını kaydedip analize devam eder.

Deep scan tamamlanmadan yeni sonuçlar aktif sonuç kümesinin yerine geçmez. Kaynak kod, deep profile veya compilation database scan sırasında değişirse yeni sonuç kümesi güvenilir kabul edilmez.

## `compile_commands.json`

`compile_commands.json`, DemirVim C/C++ subsystem'inin temel proje modelidir.

`clangd` dosyanın gerçek include path, define ve compile flag bilgisini buradan alır. Whole-project analyzer da taranacak translation unit kümesini compilation database üzerinden belirler.

CMake projelerinde:

```bash
cmake -S . -B build -G Ninja \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

cmake --build build
```

Birden fazla compilation database bulunursa deep analyzer seçim ekranı gösterebilir.

## Project Problems Center

Açmak için:

```text
<Space>p
```

Center içinde:

```text
A       Tüm bulgular
E       Hatalar
W       Uyarılar
/       Arama
D       Deep analysis başlat / aynı proje scan'ini iptal et
F       Live LSP diagnostic için Quick Fix
Enter   Bulguyu kaynak dosyada aç
r       Yenile
q       Kapat
```

Project Problems Center:

- live clangd diagnostics;
- live clang-tidy diagnostics;
- whole-project deep analyzer bulguları;
- Static Analyzer path notes

gibi kaynakları tek görünümde birleştirir.

Stale deep-analysis sonuçları güncel hata gibi gösterilmez. Yeniden scan yapılana kadar gizlenir.

Ek Trouble görünümleri:

```text
<Space>pb    Current file diagnostics
<Space>pe    Current file errors
```

## Semantic navigation

```text
K             Hover
gd            Definition
gD            Declaration
gr            References
gI            Implementation
gy            Type definition

<Space>r      Rename
<Space>a      Code action
<Space>h      Signature help

<Space>lh     Call Hierarchy
<Space>lt     Type Hierarchy
<Space>s      Symbol Center
```

## Build ve Debug

```text
<Space>b      Build Center
<Space>c      Build Profile
<Space>d      Debug Center
```

Temel debug tuşları:

```text
F5            Start / continue
F9            Toggle breakpoint
F10           Step over
F11           Step into
Shift+F11     Step out
```

## Dosya, arama ve terminal

```text
<Space>e      Dosya gezgini
<Space>f      Projede dosya bul
<Space>ff     Home altında dosya bul
<Space>F      Dosya içeriklerinde ara
<Space>t      Terminal
<Space>?      Tuş rehberi
```

## Biçimlendirme

```text
<Space>m      Mevcut buffer'ı biçimlendir
```

Biçimlendirme Conform üzerinden yürütülür ve uygun formatter olmadığında yapılandırılmış LSP fallback kullanılabilir.

## Özel düzenleme modeli

DemirVim standart Vim davranışının bazı kısımlarını bilinçli olarak değiştirir:

```text
c = cut
C = copy
d = delete
p = paste
```

Kesme ve kopyalama sistem clipboard'unu kullanır.

Silme black-hole register üzerinden yapılır, böylece mevcut clipboard içeriği korunur.

Örnek:

```text
cw   -> kelimeyi kes
Cw   -> kelimeyi kopyala
dw   -> kelimeyi sil

cc   -> satırı kes
CC   -> satırı kopyala
dd   -> satırı sil
```

Ayrıntılı açıklama için:

```vim
:Keys
```

veya:

```text
<Space>?
```

## Sağlık kontrolü

Neovim içinde:

```vim
:checkhealth
:checkhealth nvim-treesitter
:checkhealth vim.lsp
:checkhealth snacks
```

Aktif LSP istemcileri:

```vim
:lua vim.print(vim.lsp.get_clients({ bufnr = 0 }))
```

Deep analyzer durumu:

```vim
:DemirAnalysisStatus
```

Clang profile symlink'lerini kontrol etmek için:

```bash
readlink -f ~/.config/clangd/config.yaml
readlink -f ~/.clang-tidy
readlink -f ~/.config/clang-tidy/deep.yaml
```

## Komut satırı kontrolleri

```bash
nvim --version
git --version

rg --version
fd --version

gcc --version
g++ --version

clangd --version
clang-format --version
clang-tidy --version

cmake --version
ninja --version
gdb --version

tree-sitter --version

lua-language-server --version
bash-language-server --version
yaml-language-server --version
marksman --version

cmake-language-server --version
```

JSON language server:

```bash
vscode-json-language-server --help
```

## Yapılandırma yapısı

```text
~/.config/nvim/
├── init.lua
├── TUTORIAL.md
├── install-deps.sh
├── profiles/
│   ├── clangd/
│   │   └── config.yaml
│   └── clang-tidy/
│       ├── default.yaml
│       └── deep.yaml
└── lua/
    └── demir/
        ├── ai/
        │   ├── chat.lua
        │   └── copilot.lua
        ├── analysis/
        │   └── clang_tidy.lua
        ├── build/
        │   ├── buildsentry_time.lua
        │   └── cmake.lua
        ├── core/
        │   ├── autocmds.lua
        │   ├── keymaps.lua
        │   ├── options.lua
        │   └── tutorial.lua
        ├── debug/
        │   └── init.lua
        ├── editor/
        │   ├── completion.lua
        │   ├── formatting.lua
        │   ├── markdown.lua
        │   ├── problems.lua
        │   ├── symbols.lua
        │   └── treesitter.lua
        ├── lsp/
        │   ├── call_hierarchy.lua
        │   ├── clangd.lua
        │   ├── diagnostics.lua
        │   ├── init.lua
        │   ├── keymaps.lua
        │   └── type_hierarchy.lua
        ├── ui/
        │   ├── context_menu.lua
        │   ├── icons.lua
        │   ├── snacks.lua
        │   ├── statusline.lua
        │   ├── theme.lua
        │   └── whichkey.lua
        └── packages.lua
```

## Ana eklentiler

DemirVim'in temel eklenti katmanında şunlar bulunur:

```text
snacks.nvim
which-key.nvim
lualine.nvim
nvim-treesitter
gruber-darker.nvim
nvim-web-devicons
blink.cmp
friendly-snippets
nvim-lspconfig
copilot.lua
blink-copilot
plenary.nvim
cmake-tools.nvim
BuildSentry.nvim
nvim-dap
nvim-dap-view
conform.nvim
render-markdown.nvim
CopilotChat.nvim
trouble.nvim
```

## Notlar

Snacks image özelliği etkin değildir. Bu nedenle Kitty Graphics Protocol, ImageMagick, Mermaid CLI, LaTeX veya benzeri image-rendering bağımlılıkları zorunlu değildir.

Blink fuzzy matcher desteklenen sistemlerde hazır Rust binary'sini kullanabilir. Normal kurulum için Rust toolchain zorunlu değildir.

DemirVim geliştikçe README, `TUTORIAL.md` ve repository profile'ları birlikte güncellenmelidir.
