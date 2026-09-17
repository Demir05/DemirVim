# Changelog

Bu dosya DemirVim'deki mimari ve davranış değişikliklerini, özellikle gelecekte projeyi devralacak bir geliştirici veya AI'nın önceki kararları yanlışlıkla geri almaması için ayrıntılı biçimde kaydeder.

## [Unreleased] - 2026-09-17

### Genel durum

Bu revizyon serisi DemirVim'in C/C++ geliştirme akışını yalnız özellik ekleyerek değil, ownership ve lifecycle sınırlarını belirginleştirerek sertleştirdi. Ana amaçlar şunlardı:

- aynı kavram için birden fazla bağımsız "project root" tanımı oluşmasını engellemek;
- CMake, compilation database ve clangd arasında deterministik senkronizasyon kurmak;
- Deep Analysis sonuçlarını yalnız tutarlı bir filesystem/editor snapshot'ından geldiklerinde commit etmek;
- Call/Type Hierarchy kopya kodunu azaltırken protokol semantiğini birbirine karıştırmamak;
- plugin internal API bağımlılıklarını azaltmak veya tek compatibility boundary içinde izole etmek;
- tutorial/statusline gibi UI bileşenlerinde filename inference yerine semantic context kullanmak.

### Added

- `lua/demir/core/project.lua`
  - Deep Analysis ve Problems Center için merkezi analysis-root çözümleyicisi.
  - Root marker'ları analysis bağlamında değerlendirilir; CMake ve LSP ownership'ı bu modüle taşınmamıştır.

- `lua/demir/lsp/workspace.lua`
  - LSP semantic workspace için merkezi çözümleyici.
  - Öncelik: aktif client `workspace_folders` → client `root_dir` → semantic filesystem fallback.
  - Canonical/symlink-safe path normalizasyonu ve relative-path yardımcıları sağlar.

- `lua/demir/lsp/hierarchy_common.lua`
  - Call Hierarchy ve Type Hierarchy'nin ortak, semantik olmayan mekaniklerini paylaşır.
  - Buffer/window doğrulama, URI/path dönüşümü, symlink-aware loaded-buffer bulma, preview source, extmark, geometry, scratch window ve tree-selection yardımcıları burada toplanmıştır.
  - Root keşfi yapmaz; `demir.lsp.workspace` ownership'ını tüketir.

- Deep Analyzer project-local C/C++ input integrity snapshot'ı.
  - Translation unit'lere ek olarak header/include/module/generated C/C++ input dosyaları scan başlangıcında metadata signature ile kaydedilir.
  - Yeni eklenen, silinen veya scan sırasında değişen input'lar commit aşamasında sonuçların discard edilmesine yol açar.
  - `.git`, `.hg`, `.svn` traversal dışındadır; build/generated dizinlerindeki C/C++ input'lar körlemesine dışlanmaz.
  - File symlink'leri target signature üzerinden takip edilir; directory symlink'leri external/cyclic tree expansion riskine karşı recursively izlenmez.

### Changed

#### LSP startup ve keymap lifecycle

- `lsp/keymaps.lua` server enable işleminden önce yüklenir.
- clangd server config de `vim.lsp.enable()` öncesinde kurulacak biçimde sıralandı.
- Belgelenmiş custom edit modeli etkinleştirildi:
  - `c`: system clipboard'a cut
  - `C`: system clipboard'a copy
  - `d`: black-hole delete
  - `p`: normal paste davranışı

#### Root ownership ayrımı

Aşağıdaki root kavramları bilinçli olarak ayrı tutulur:

| Concern | Authority |
| --- | --- |
| Deep Analysis / Problems | `demir.core.project` |
| CMake source/build | `cmake-tools` state + `demir.build.cmake` |
| LSP semantic workspace | `demir.lsp.workspace` |
| Context-menu relative path | `demir.ui.context_menu` içindeki UI-local resolver |

Bu sınır gelecekte "tek universal root" altında birleştirilmemelidir.

#### CMake / compilation database / clangd synchronization

- CMake source root `cmake.get_config().cwd` üzerinden alınır; process cwd otorite değildir.
- Build directory `cmake-tools` state'inden okunur.
- Source-root `compile_commands.json` DemirVim tarafından güvenli symlink olarak uzlaştırılır.
- Kullanıcıya ait normal `compile_commands.json` dosyası hiçbir durumda overwrite edilmez.
- Link replacement geçici link + rename ile atomik yapılır.
- Configure operasyonları synchronization barrier olarak ele alınır.
- Build ve run sonrasında compilation model yeniden okunur.
- Compilation model karşılaştırması yalnız pathname değil, database file signature'ını da içerir.
- Değişiklik halinde `DemirCompilationModelChanged` user event'i yayımlanır.
- clangd gerektiğinde restart edilerek yeni compilation model deterministik biçimde görünür yapılır.

#### Deep Analysis transaction ve provenance

- Sonuçlar scan bitene kadar geçici run state'inde tutulur; yalnız integrity kontrolleri geçerse commit edilir.
- Committed state ile son attempt state ayrıldı:
  - committed `root` / `database`
  - `last_attempt.root` / `last_attempt.database`
- Problems Center aynı proje için aktif scan, committed results ve last attempt bilgisini birbirine karıştırmadan gösterir.
- Zero-issue fakat stale bir sonuç "deep clean" olarak gösterilmez.
- Scan sırasında şu mutation yüzeyleri ayrı kontrol edilir:
  - CMake compilation model
  - `compile_commands.json`
  - deep clang-tidy config
  - Neovim'de açık project buffer'ları
  - translation unit dosyaları
  - project-local C/C++ semantic input tree
- File signature artık size + mtime + ctime bilgilerini içerir.
- Project-local input snapshot alınamazsa analyzer fail-closed davranır; integrity garantisi veremediği scan'i başlatmaz/commit etmez.
- Project root dışındaki SDK/header dependency'leri bu transaction guarantee'ye dahil değildir. Bu alanı genişletmek için gerçek compiler dependency graph gerekir.

#### Call Hierarchy / Type Hierarchy refactor

- İki büyük modülün ortak mekanikleri `hierarchy_common.lua` içine çıkarıldı.
- Call-specific semantik ayrı bırakıldı:
  - incoming/outgoing
  - `fromRanges`
  - call-site merge/cycle
- Type-specific semantik ayrı bırakıldı:
  - supertypes/subtypes
  - opaque type-hierarchy data
  - type direction semantics
- Her iki hierarchy semantic root için `demir.lsp.workspace` kullanır.
- Call Hierarchy lifecycle close davranışı Type ile eşitlendi: otomatik kapanış eski source tab/window'a zorla focus döndürmez.
- Call empty-result render sırasında eski extmark namespace temizlenir.
- Ortak buffer write helper modifiable durumunu hata halinde bile geri kapatır.

#### Tutorial / Statusline

- Tutorial'ın gerçek dosya edit'i değil, `readfile()` ile doldurulan `nofile` scratch buffer olduğu açık bir semantic contract haline getirildi.
- Tutorial buffer `demir_statusline_context = "tutorial"` ile işaretlenir.
- Stable scratch URI adı kullanılır (`demir://tutorial/...`).
- Statusline artık yalnız `TUTORIAL.md` filename tahminiyle tutorial algılamaz.
- Tutorial singleton davranır; aynı pencere tekrar açılmaya çalışılırsa mevcut pencereye focus edilir.
- Resize ve BufWipeout lifecycle temizliği eklendi.
- Generic Snacks picker yüzeyi statusline'da yanlışlıkla Explorer diye etiketlenmez.
- `project_name` benzeri UI alanı authoritative project root gibi davranmaz; cwd yalnız cosmetic bilgi olarak kalır.

#### Context Menu / plugin integration

- Snacks picker keşfinde `picker.list.win.win` ve benzeri nested implementation alanlarına doğrudan bağımlılık kaldırıldı.
- Belgelenmiş `Snacks.picker.current` / `Snacks.picker.get()` yüzeyleri tercih edildi.
- Explorer file/directory ayrımında plugin item internals yerine filesystem bilgisi kullanılır.
- Neovim'in `nvim.popupmenu` augroup'unu fiziksel olarak silmek yerine desteklenen popup autocmd temizleme yolu kullanılır.
- Context-menu relative-path root resolver yalnız UI concern olarak kalır ve analysis/CMake/LSP root authority'sine bağlanmaz.

#### BuildSentry timing compatibility boundary

- BuildSentry'nin public extension API'si timing overlay için yeterli olmadığından private dependency tamamen kaldırılmadı.
- Bunun yerine bütün private erişimler yalnız `lua/demir/build/buildsentry_time.lua` içinde izole edildi.
- Internal modules `pcall(require, ...)` ve capability checks ile doğrulanır; upstream kırılırsa timing özelliği fail-closed olur ve Neovim'in geri kalanı çalışır.
- Eski ve yeni status vocabulary birlikte kabul edilir:
  - `RUN` / `RUNNING`
  - `OK` / `SUCCESS`
  - `FAIL` / `FAILED`
  - `TRM` / `TERMINATED`
- Demir timing metadata plugin task object'lerine field eklemek yerine weak-key side tables içinde tutulur.
- Task UI kapalıyken tamamlanırsa finish timestamp yine state üzerinden yakalanır; pencere yeniden açıldığında süre yapay biçimde uzamaz.

### Fixed

- LSP keymap dosyasının mevcut olup runtime'da yüklenmemesi.
- clangd config'in client enable işleminden sonra yüklenebilmesi nedeniyle oluşan lifecycle riski.
- Analysis, CMake, LSP ve UI path-root kavramlarının birbirine karışma ihtimali.
- CMake configure/profile/build/run yollarının `compile_commands.json` ve clangd ile farklı postcondition üretmesi.
- Problems Center'ın farklı proje scan/committed sonuç provenance'ını yanlış eşleştirebilmesi.
- Tutorial'ın statusline'da `YENİ BUFFER` görünmesi.
- Call Hierarchy otomatik lifecycle kapanışının kullanıcıyı eski tab/window'a geri çekebilmesi.
- Call Hierarchy empty state'te eski extmark'ların kalabilmesi.
- Context Menu'nün generic Snacks picker'ı Explorer olarak değerlendirebilecek internal coupling'i.
- BuildSentry timer'ın UI kapalıyken biten task süresini geç tamamlanmış gibi ölçebilmesi.
- Deep Analyzer'ın açık olmayan project-local header/generated C/C++ input değişikliklerini kaçırabilmesi.

### Verification status

- Issues 1-8 için kullanıcı runtime testleri başarılı olarak raporlandı.
- Issue 9 external-input integrity değişikliği statik olarak incelendi ve önceki transaction modeline entegre edildi.
- Issue 9 için özellikle şu runtime regression testi korunmalıdır:

```text
Deep Analysis başlat
→ scan sürerken Neovim'de açık olmayan project-local bir .hpp/.inc dosyasını dışarıdan değiştir
→ scan bitince yeni sonuçların commit edilmediğini doğrula
→ previous committed results korunmalı ve changed input yolu discard reason içinde görünmeli
```

### Maintainer / AI handoff invariants

1. `demir.core.project`, `demir.lsp.workspace` ve CMake root modelini tek resolver altında birleştirme.
2. `hierarchy_common.lua` içine Call/Type protokol semantiği taşıma; yalnız gerçekten ortak mekanikleri koy.
3. Deep Analyzer'da partial/inconsistent scan sonuçlarını commit etme. Eski known-good result set'i korumak tercih edilen failure mode'dur.
4. `compile_commands.json` user-owned regular file ise overwrite etme.
5. CMake model değişikliğini yalnız symlink target değişimiyle ölçme; database content signature da önemlidir.
6. Plugin private API gerekiyorsa onu feature'ın her yerine yayma; tek compatibility boundary içinde capability-check ederek izole et.
7. Tutorial gibi plugin/scratch UI yüzeylerini dosya adına bakarak kimliklendirme; semantic buffer context kullan.
8. UI convenience root'larını authoritative analysis/LSP/CMake root'a dönüştürme.
9. README, CHANGELOG ve TUTORIAL davranış değişiklikleriyle birlikte güncellenmelidir.
