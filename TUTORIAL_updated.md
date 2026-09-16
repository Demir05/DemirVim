# DemirVim Tuş ve Çalışma Rehberi

Bu rehber DemirVim'in günlük kullanım modelini açıklar.

Yapılandırma küçük ve tahmin edilebilir bir düzenleme dili kullanır; bunun üzerine proje arama, LSP semantic navigation, C/C++ analysis, build ve debugging katmanları eklenir.

# Temel zihinsel model

DemirVim'de dört ana çalışma alanı vardır:

```text
DÜZENLEME
    Vim hareketleri + özel cut/copy/delete modeli

GEZİNME
    Snacks + LSP + Symbol / Call / Type Hierarchy

ANALİZ
    live clangd + clang-tidy
    whole-project deep clang-tidy + Static Analyzer

ÇALIŞTIRMA
    CMake build + GDB/DAP debug
```

Leader tuşu:

```text
Space
```

Ayrıntılı tuş rehberini Neovim içinden açmak için:

```vim
:Keys
```

veya:

```text
Space ?
```

---

# Modlar

## Normal Mod

Normal mod gezinmek, düzenleme operatörlerini kullanmak ve komut çalıştırmak için temel moddur.

Herhangi bir anda Normal moda dönmek için:

```text
Esc
```

## Insert Mod

```text
i    İmlecin önünde yazmaya başla
a    İmlecin arkasında yazmaya başla
o    Alt satırda yeni bir satır aç
O    Üst satırda yeni bir satır aç
```

Normal moda dönmek için:

```text
Esc
```

## Visual Mod

```text
v         Karakter tabanlı seçim
V         Satır tabanlı seçim
Ctrl+v    Blok tabanlı seçim
```

Seçim oluşturulduktan sonra `c`, `C`, `d` ve `p` doğrudan seçili alan üzerinde çalışır.

---

# Gezinme

Temel yön hareketleri:

```text
h    Sola
j    Aşağı
k    Yukarı
l    Sağa
```

Kelime hareketleri:

```text
w    Sonraki kelime
b    Önceki kelime
e    Kelimenin sonu
```

Satır:

```text
0    Satır başı
$    Satır sonu
```

Dosya:

```text
gg   Dosya başı
G    Dosya sonu
```

Pencereler:

```text
Ctrl+h    Soldaki pencereye geç
Ctrl+j    Aşağıdaki pencereye geç
Ctrl+k    Yukarıdaki pencereye geç
Ctrl+l    Sağdaki pencereye geç
```

Pencere boyutu:

```text
Alt+Up       Yüksekliği artır
Alt+Down     Yüksekliği azalt
Alt+Left     Genişliği azalt
Alt+Right    Genişliği artır
```

---

# Kesme, Kopyalama ve Silme

DemirVim'in özel düzenleme modeli:

```text
c    Kes
C    Kopyala
d    Sil
```

Anlamları:

```text
c    Metni siler ve sistem panosuna koyar.
C    Metni değiştirmeden sistem panosuna koyar.
d    Metni siler ancak sistem panosunu değiştirmez.
```

Bu nedenle `d`, daha önce kopyalanmış clipboard içeriğini bozmaz.

## Yapıştırma

```text
p    İmlecin sonrasına yapıştır
P    İmlecin öncesine yapıştır
```

## Mevcut satır

```text
cc    Satırı kes
CC    Satırı kopyala
dd    Satırı sil
```

Genel kural:

```text
operatör + operatör = mevcut satır
```

## Hareket ile birlikte

```text
cw     Sonraki kelime hareketinin kapsadığı alanı kes
Cw     Aynı alanı kopyala
dw     Aynı alanı sil

c2w    İki kelimelik alanı kes
C2w    İki kelimelik alanı kopyala
d2w    İki kelimelik alanı sil
```

## Metin nesneleri

```text
ciw    İçinde bulunulan kelimeyi kes
Ciw    İçinde bulunulan kelimeyi kopyala
diw    İçinde bulunulan kelimeyi sil
```

Parantez içeriği:

```text
ci(    (...) içeriğini kes
Ci(    (...) içeriğini kopyala
di(    (...) içeriğini sil
```

Süslü parantez:

```text
ci{    {...} içeriğini kes
Ci{    {...} içeriğini kopyala
di{    {...} içeriğini sil
```

Tırnak:

```text
ci"    "..." içeriğini kes
Ci"    "..." içeriğini kopyala
di"    "..." içeriğini sil
```

Satır sonu:

```text
c$    Kes
C$    Kopyala
d$    Sil
```

Satır başı:

```text
c0    Kes
C0    Kopyala
d0    Sil
```

Dosya sonu:

```text
cG    Kes
CG    Kopyala
dG    Sil
```

---

# Visual Modda Düzenleme

Önce seçim:

```text
v
```

Sonra:

```text
c    Seçimi kes
C    Seçimi kopyala
d    Seçimi sil
p    Seçimin üzerine yapıştır
```

---

# Geri Alma ve Yineleme

```text
u    Geri al
U    İleri al / yinele
```

Örnek:

```text
uuu
```

üç değişikliği geri alır.

---

# Kaydetme

Normal, Insert veya Visual modda:

```text
Ctrl+s
```

mevcut dosyayı kaydeder.

---

# Dosya gezgini, arama ve terminal

```text
Space e      Dosya gezgini
Space f      Projede dosya bul
Space ff     Home altında dosya bul
Space F      Proje içeriğinde ara
Space t      Terminal
```

Tuş rehberi:

```text
Space ?
```

---

# LSP ve C/C++ semantic navigation

## Hover ve tanım hareketleri

```text
K             Hover / symbol bilgisi
gd            Definition
gD            Declaration
gr            References
gI            Implementation
gy            Type definition
```

## Refactor ve API

```text
Space r       Rename
Space a       Code action
Space h       Signature help
```

## Call Hierarchy

```text
Space l h
```

veya:

```vim
:DemirCallHierarchy
```

Bir fonksiyonun kimleri çağırdığını ve kimler tarafından çağrıldığını incelemek için kullanılır.

## Type Hierarchy

```text
Space l t
```

veya:

```vim
:DemirTypeHierarchy
```

Sınıf / tür kalıtım ilişkilerini incelemek için kullanılır.

## Symbol Center

```text
Space s
```

Proje veya buffer içindeki semantic sembollere ulaşmak için kullanılır.

---

# Tanılama sistemi

Normal clangd / clang-tidy diagnostics editör içinde:

- sign column ikonları;
- warning / error underline;
- current-line diagnostic text;
- diagnostic popup

olarak gösterilir.

Tanılama hareketleri:

```text
[d    Önceki diagnostic
]d    Sonraki diagnostic
```

---

# Project Problems Center

Açmak için:

```text
Space p
```

Problems Center live clangd diagnostics ile deep whole-project bulgularını tek yerde gösterir.

Temel tuşlar:

```text
A       Tüm bulgular
E       Yalnız errors
W       Yalnız warnings
/       Arama
D       Deep analysis başlat / aynı proje scan'ini iptal et
F       Live LSP Quick Fix
Enter   Seçili bulguyu aç
r       Yenile
q       Kapat
```

Ek current-buffer görünümleri:

```text
Space p b    Current file diagnostics
Space p e    Current file errors
```

## Live ve deep finding farkı

Live finding:

```text
clangd / live clang-tidy
```

tarafından gelir ve uygun durumda `F` ile LSP Quick Fix kullanılabilir.

Deep-only finding:

```text
whole-project clang-tidy / Static Analyzer
```

tarafından gelir. Böyle bir bulguya sahte LSP fix bağlanmaz.

---

# Deep C++ Analysis

Deep analyzer proje genelindeki translation unit'ları `compile_commands.json` üzerinden tarar.

Başlat:

```vim
:DemirAnalyzeProject
```

Belirli worker sayısı:

```vim
:DemirAnalyzeProject 4
```

Değiştirilmiş proje buffer'larını kaydedip başlat:

```vim
:DemirAnalyzeProject!
```

İptal:

```vim
:DemirCancelAnalysis
```

Sonuçları temizle:

```vim
:DemirClearAnalysis
```

Durum:

```vim
:DemirAnalysisStatus
```

## Scan lifecycle

Yaklaşık akış:

```text
preparing
    ↓
unsaved buffer check
    ↓
compilation database discovery / selection
    ↓
deep config verification
    ↓
whole-project analysis
    ↓
atomic result commit
```

Scan sırasında kaynak kod veya compilation database değişirse sonuç kümesi güncel kabul edilmez.

Deep sonuçlar stale olduğunda Problems Center bunları güncel hata gibi göstermez.

---

# `compile_commands.json`

C/C++ tarafında gerçek include path, define ve compile flags için compilation database önemlidir.

CMake:

```bash
cmake -S . -B build -G Ninja \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

cmake --build build
```

Deep analyzer da taranacak translation unit'ları bu database üzerinden belirler.

---

# Biçimlendirme

Mevcut buffer:

```text
Space m
```

Biçimlendirme Conform üzerinden yürütülür.

C/C++ tarafında normal formatter:

```text
clang-format
```

---

# Build

Build Center:

```text
Space b
```

Build Profile:

```text
Space c
```

CMake proje/build işlemlerinin ana giriş noktaları bunlardır.

---

# Debug

Debug Center:

```text
Space d
```

Temel function-key akışı:

```text
F5            Start / Continue
F9            Toggle Breakpoint
F10           Step Over
F11           Step Into
Shift+F11     Step Out
```

Debug Center içinde restart, terminate, pause ve watch gibi ek işlemler bulunur.

---

# Context Menu

Sağ tık menüsü bulunduğun bağlama göre farklı işlemler gösterebilir.

Source buffer'da semantic/LSP işlemleri, explorer/picker yüzeylerinde ilgili dosya işlemleri ve terminalde terminale uygun menü davranışı kullanılabilir.

---

# GitHub Copilot

Copilot completion sonuçları Blink completion menüsüne entegredir.

İlk kimlik doğrulama:

```vim
:Copilot auth
```

Copilot Chat ayrıca yapılandırılmıştır.

---

# Arama vurgusunu temizleme

Normal modda:

```text
Esc
```

arama sonucunda kalan highlight'ları temizler.

---

# Sağlık ve sorun çözme

Genel:

```vim
:checkhealth
```

LSP:

```vim
:checkhealth vim.lsp
```

Tree-sitter:

```vim
:checkhealth nvim-treesitter
```

Snacks:

```vim
:checkhealth snacks
```

Aktif LSP istemcileri:

```vim
:lua vim.print(vim.lsp.get_clients({ bufnr = 0 }))
```

Deep analyzer state:

```vim
:DemirAnalysisStatus
```

---

# Clang profile yapısı

DemirVim'in C/C++ policy dosyaları repository içinde tutulur:

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

Bu yolların repository profile'larına symlink olması önerilir.

Kontrol:

```bash
readlink -f ~/.config/clangd/config.yaml
readlink -f ~/.clang-tidy
readlink -f ~/.config/clang-tidy/deep.yaml
```

---

# Kısa Referans

```text
GEZİNME

h              Sol
j              Aşağı
k              Yukarı
l              Sağ

w              Sonraki kelime
b              Önceki kelime
e              Kelime sonu

0              Satır başı
$              Satır sonu
gg             Dosya başı
G              Dosya sonu


DÜZENLEME

c              Kes
C              Kopyala
d              Sil
p              Sonrasına yapıştır
P              Öncesine yapıştır

cc             Satırı kes
CC             Satırı kopyala
dd             Satırı sil

u              Geri al
U              Yinele


SEÇİM

v              Karakter seçimi
V              Satır seçimi
Ctrl+v         Blok seçimi


INSERT

i              Yazmaya başla
a              İmleç sonrasında yaz
o              Alt satır aç
O              Üst satır aç
Esc            Normal moda dön


DOSYA / ARAMA

Space e        Explorer
Space f        Find files
Space ff       Home files
Space F        Grep
Space t        Terminal


LSP / SEMANTIC

K              Hover
gd             Definition
gD             Declaration
gr             References
gI             Implementation
gy             Type definition

Space r        Rename
Space a        Code action
Space h        Signature help
Space l h      Call Hierarchy
Space l t      Type Hierarchy
Space s        Symbol Center


ANALİZ

[d             Önceki diagnostic
]d             Sonraki diagnostic

Space p        Project Problems Center
Space p b      Current file diagnostics
Space p e      Current file errors

D              Problems Center içinde deep scan / cancel

:DemirAnalyzeProject
:DemirAnalysisStatus


BUILD / DEBUG

Space b        Build Center
Space c        Build Profile
Space d        Debug Center

F5             Start / Continue
F9             Toggle Breakpoint
F10            Step Over
F11            Step Into
Shift+F11      Step Out


GENEL

Ctrl+s         Kaydet
Space m        Format
Space ?        Tuş rehberi

Ctrl+h         Sol pencere
Ctrl+j         Alt pencere
Ctrl+k         Üst pencere
Ctrl+l         Sağ pencere
```
