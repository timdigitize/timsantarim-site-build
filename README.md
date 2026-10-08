# timsantarim-site-build

timsantarim.com'un **derlenmiş** hâli. Elle düzenlenmez; kaynak kod özel depodadır
(`timdigitize/timsantarim`). Her `main` push'unda GitHub Actions siteyi derleyip buraya yazar,
sunucudaki `Timsan-TimsantarimDeploy` görevi 5 dakika içinde alıp yayınlar.

- `VERSION.txt` — hangi kaynak commit'inden, ne zaman derlendiği (canlıda: https://timsantarim.com/VERSION.txt)
- `ops/deploy-site.ps1` — sunucu tarafı yayın betiği (kendini bu depodan günceller)
- `ops/install.ps1` — sunucuya tek seferlik kurulum

## Sunucu kurulumu (bir kez)

Yönetici PowerShell'de (Kurtarma Konsolu Shift iletmez; bu iki satır Shift'siz yazılabilir):

```powershell
curl.exe --location raw.githubusercontent.com/timdigitize/timsantarim-site-build/main/ops/install.ps1 --output \ts-install.ps1
powershell -executionpolicy bypass -file \ts-install.ps1
```

Kurulum site kökünü IIS'ten (timsantarim.com bağlantısı olan site) bulur, `site-root.txt`'ye yazar ve
DryRun yapar. Ardından gerçek ilk yayın:

```powershell
powershell -executionpolicy bypass -file \programdata\timsanops\timsantarim-deploy\deploy-site.ps1 -force
```

Günlük: `C:\ProgramData\TimsanOps\timsantarim-deploy\deploy.log`. Yedekler: `...\timsantarim-deploy\backup\` (son 5).

Kopyalama `robocopy /E` ile yapılır: yeni/değişen dosyalar yazılır, sunucuda fazladan duran dosyalar
**silinmez** (eski siteden kalanlar ve sunucuya özel dosyalar korunur). `App_Data\`, `.well-known\`,
`aspnet_client\` ve site kökünün içinde duran başka IIS sitelerinin klasörleri hiç ellenmez.
Geri almak için: yedek klasörünü site köküne `robocopy <yedek> <site kökü> /E` ile kopyalayın ve
`current-sha.txt` dosyasını silin.
