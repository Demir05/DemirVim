# Neovim Tuş Rehberi

Bu yapılandırma küçük, tutarlı ve tahmin edilebilir bir komut dili kullanır.

Temel mantık şöyledir:

* Küçük harf, temel işlemi gerçekleştirir.
* Büyük harf, aynı işlem ailesindeki karşıt veya koruyucu işlemi gerçekleştirir.
* Bir operatörü iki kez kullanmak, mevcut satırın tamamını hedefler.
* Operatör ile hareket komutunu birleştirmek, hareketin kapsadığı metin üzerinde işlem yapar.
* Mümkün olduğunca az tuş ezberlenir, mevcut hareket sistemi farklı işlemlerle tekrar kullanılır.

---

## Modlar

### Normal Mod

Normal mod; gezinmek, metni düzenlemek ve komut çalıştırmak için kullanılır.

Herhangi bir anda Normal moda dönmek için:

```text
Esc
```

kullanılır.

---

### Insert Mod

Insert mod yalnızca metin yazmak için kullanılır.

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

kullanılır.

---

### Visual Mod

Visual mod metin seçmek için kullanılır.

```text
v         Karakter tabanlı seçim
V         Satır tabanlı seçim
Ctrl+v    Blok tabanlı seçim
```

Bir seçim oluşturulduktan sonra `c`, `C`, `d` ve `p` gibi düzenleme komutları doğrudan seçili alan üzerinde çalışır.

---

# Gezinme

Temel yön hareketleri:

```text
h    Sola git
j    Aşağı git
k    Yukarı git
l    Sağa git
```

Kelime hareketleri:

```text
w    Sonraki kelimeye git
b    Önceki kelimeye git
e    Kelimenin sonuna git
```

Satır hareketleri:

```text
0    Satırın başına git
$    Satırın sonuna git
```

Dosya hareketleri:

```text
gg   Dosyanın başına git
G    Dosyanın sonuna git
```

---

# Kesme, Kopyalama ve Silme

Üç temel düzenleme operatörü vardır:

```text
c    Kes
C    Kopyala
d    Sil
```

Buradaki önemli fark:

```text
c    Metni siler ve sistem panosuna koyar.
C    Metni değiştirmeden sistem panosuna koyar.
d    Metni siler ancak sistem panosunu değiştirmez.
```

Bu nedenle önceden kopyaladığın bir şeyi kaybetmeden başka metinleri `d` ile temizleyebilirsin.

---

# Yapıştırma

```text
p    İmlecin sonrasına yapıştır
P    İmlecin öncesine yapıştır
```

---

# Mevcut Satır

Bir operatörün iki kez kullanılması mevcut satırın tamamını hedefler.

```text
cc    Mevcut satırı kes
CC    Mevcut satırı kopyala
dd    Mevcut satırı sil
```

Buradaki genel kural:

```text
operatör + operatör = mevcut satır
```

---

# Kelimeler Üzerinde İşlem

Operatörler hareket komutlarıyla birleştirilebilir.

Örneğin:

```text
cw    Bir sonraki kelime hareketinin kapsadığı alanı kes
Cw    Bir sonraki kelime hareketinin kapsadığı alanı kopyala
dw    Bir sonraki kelime hareketinin kapsadığı alanı sil
```

Birden fazla kelime için sayı kullanılabilir:

```text
c2w    İki kelimelik alanı kes
C2w    İki kelimelik alanı kopyala
d2w    İki kelimelik alanı sil
```

---

# Metin Nesneleri

`i`, burada `inside`, yani bir metin nesnesinin iç kısmı anlamına gelir.

Kelimenin tamamını hedeflemek için:

```text
ciw    İçinde bulunulan kelimeyi kes
Ciw    İçinde bulunulan kelimeyi kopyala
diw    İçinde bulunulan kelimeyi sil
```

Örneğin imleç şu kelimenin içindeyse:

```text
first_value
```

şu komut:

```text
Ciw
```

`first_value` kelimesini kopyalar.

---

# Parantez İçeriği

Yuvarlak parantezlerin içini hedeflemek için:

```text
ci(    (...) içeriğini kes
Ci(    (...) içeriğini kopyala
di(    (...) içeriğini sil
```

Örnek:

```cpp
print(first_value, second_value);
```

İmleç parantezlerin içindeyken:

```text
Ci(
```

şu kısmı kopyalar:

```text
first_value, second_value
```

---

# Süslü Parantez İçeriği

```text
ci{    {...} içeriğini kes
Ci{    {...} içeriğini kopyala
di{    {...} içeriğini sil
```

Örnek:

```cpp
if (ready)
{
    run();
    finish();
}
```

İmleç blok içerisindeyken:

```text
Ci{
```

süslü parantezlerin içindeki bölümü kopyalar.

---

# Tırnak İçeriği

```text
ci"    "..." içerisini kes
Ci"    "..." içerisini kopyala
di"    "..." içerisini sil
```

Örnek:

```cpp
std::string name = "Demir";
```

İmleç `Demir` üzerindeyken:

```text
Ci"
```

yalnızca:

```text
Demir
```

metnini kopyalar.

---

# Satır Sonuna Kadar İşlem

```text
c$    İmleçten satır sonuna kadar kes
C$    İmleçten satır sonuna kadar kopyala
d$    İmleçten satır sonuna kadar sil
```

---

# Satır Başına Kadar İşlem

```text
c0    İmleçten satır başına kadar kes
C0    İmleçten satır başına kadar kopyala
d0    İmleçten satır başına kadar sil
```

---

# Dosya Sonuna Kadar İşlem

```text
cG    İmleçten dosyanın sonuna kadar kes
CG    İmleçten dosyanın sonuna kadar kopyala
dG    İmleçten dosyanın sonuna kadar sil
```

Aynı mantık diğer hareket komutlarıyla da kullanılabilir.

---

# Visual Modda Düzenleme

Önce bir seçim oluştur:

```text
v
```

Ardından:

```text
c    Seçimi kes
C    Seçimi kopyala
d    Seçimi sil
p    Seçimin üzerine yapıştır
```

Örneğin:

```text
v
w
C
```

önce bir alan seçer, ardından seçili alanı kopyalar.

Visual modda hedef zaten seçildiği için ayrıca hareket komutu belirtmek gerekmez.

---

# Geri Alma ve Yineleme

```text
u    Geri al
U    İleri al
```

Birden fazla işlemi geri almak için aynı tuş tekrarlanabilir:

```text
uuu
```

üç değişikliği geri alır.

Benzer şekilde:

```text
UU
```

iki değişikliği yeniden uygular.

---

# Pencereler Arasında Gezinme

Birden fazla Neovim penceresi açıkken:

```text
Ctrl+h    Soldaki pencereye geç
Ctrl+j    Aşağıdaki pencereye geç
Ctrl+k    Yukarıdaki pencereye geç
Ctrl+l    Sağdaki pencereye geç
```

---

# Pencere Boyutlandırma

```text
Alt+Up       Pencerenin yüksekliğini artır
Alt+Down     Pencerenin yüksekliğini azalt

Alt+Left     Pencerenin genişliğini azalt
Alt+Right    Pencerenin genişliğini artır
```

---

# Dosyayı Kaydetme

Normal, Insert veya Visual mod içerisindeyken:

```text
Ctrl+s
```

mevcut dosyayı kaydeder.

---

# Arama Vurgusunu Temizleme

Normal modda:

```text
Esc
```

arama sonucunda kalan vurgulamaları temizler.

---

# Tanılama Mesajları

LSP sistemi etkinleştirildiğinde:

```text
[d    Önceki tanılama mesajına git
]d    Sonraki tanılama mesajına git
```

Örneğin C++ kodundaki bir hata veya uyarıdan diğerine geçmek için kullanılabilir.

---

# Temel Zihinsel Model

Her kombinasyonu ayrı ayrı ezberlemeye çalışma.

Önce yalnızca üç operatörü öğren:

```text
c    Kes
C    Kopyala
d    Sil
```

Daha sonra hedefi seç:

```text
w     Kelime hareketi
iw    İçinde bulunulan kelime
(     Parantez
{     Süslü parantez
$     Satır sonu
G     Dosya sonu
```

Genel formül:

```text
operatör + hedef
```

Örneğin:

```text
c + iw  →  ciw  →  Kelimeyi kes
C + iw  →  Ciw  →  Kelimeyi kopyala
d + iw  →  diw  →  Kelimeyi sil
```

Bir operatör iki kez kullanılırsa mevcut satır hedeflenir:

```text
operatör + operatör = mevcut satır
```

Bu nedenle:

```text
cc    Satırı kes
CC    Satırı kopyala
dd    Satırı sil
```

---

# Kısa Referans

```text
GEZİNME

h        Sol
j        Aşağı
k        Yukarı
l        Sağ

w        Sonraki kelime
b        Önceki kelime
e        Kelime sonu

0        Satır başı
$        Satır sonu

gg       Dosya başı
G        Dosya sonu


DÜZENLEME

c        Kes
C        Kopyala
d        Sil

cc       Satırı kes
CC       Satırı kopyala
dd       Satırı sil

p        Sonrasına yapıştır
P        Öncesine yapıştır

u        Geri al
U        İleri al


SEÇİM

v        Karakter seçimi
V        Satır seçimi
Ctrl+v   Blok seçimi


INSERT

i        Yazmaya başla
a        İmleç sonrasında yaz
o        Alt satır aç
O        Üst satır aç
Esc      Normal moda dön


GENEL

Ctrl+s   Kaydet

Ctrl+h   Sol pencere
Ctrl+j   Alt pencere
Ctrl+k   Üst pencere
Ctrl+l   Sağ pencere

[d       Önceki tanılama
]d       Sonraki tanılama
```

