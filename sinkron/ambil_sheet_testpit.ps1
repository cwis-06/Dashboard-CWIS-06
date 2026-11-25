<#
  Mengunduh tab TEST PIT dari Google Sheet (format CSV), memilih kolom yang
  dipakai berdasarkan judul kolomnya, lalu menulis CSV rapi untuk PostgreSQL.
  Dipanggil oleh update_dashboard.bat (langkah sinkron test pit).
  Penjelasan lengkap: panduan\01_sinkron_test_pit.md

  Syarat: Sheet bisa dibuka lewat tautan (Share > General access:
  "Anyone with the link" - Viewer). ID Sheet disimpan di config_lokal.bat,
  bukan di repo.
#>
param(
  [Parameter(Mandatory = $true)][string]$Url,   # .../export?format=csv&gid=...
  [Parameter(Mandatory = $true)][string]$Out    # CSV hasil untuk staging.tp_sheet
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1. Unduh
$raw = Join-Path $env:TEMP 'cwis06_tp_mentah.csv'
Invoke-WebRequest -Uri $Url -OutFile $raw -UseBasicParsing -MaximumRedirection 10
$awal = Get-Content -Path $raw -TotalCount 1 -Encoding UTF8
if ($awal -match '^\s*<') {
  throw 'Yang terunduh halaman login, bukan isi Sheet. Atur Share > General access: Anyone with the link (Viewer), atau periksa TP_SHEET_ID dan TP_SHEET_GID di config_lokal.bat.'
}

# 2. Baca CSV (aman untuk koma dan tanda kutip di dalam sel)
Add-Type -AssemblyName Microsoft.VisualBasic
$p = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($raw, [Text.Encoding]::UTF8)
$p.TextFieldType = 'Delimited'
$p.SetDelimiters(',')
$p.HasFieldsEnclosedInQuotes = $true

# 3. Baca semua baris, lalu cari baris judul (dicari di 15 baris pertama)
#    Judul dinormalkan: huruf kecil, tanpa spasi dan tanda baca. "No. Test Pit" -> "notestpit"
#    Tiap kolom punya beberapa pola; pola di depan diutamakan.
$semua = New-Object System.Collections.Generic.List[object]
while (-not $p.EndOfData) { $semua.Add(@($p.ReadFields())) }
$p.Close()
$pola = [ordered]@{
  tp        = @('^(no)?(testpit|tp)$', '^(no)?(titik)?(testpit|tp)')
  zona      = @('^zona$')
  mh        = @('^(no)?manhole$', '^mh$')
  utilitas  = @('^utilitas', 'utilitas')
  permukaan = @('permukaan')
  status    = @('^status$')
  tanggal   = @('^tanggal', 'tanggal')
  link      = @('linkdokumentasibatestpit', 'batestpit', 'linkba', '^link')
  mandor    = @('mandor')
}
function Cari-Kolom($judul, $daftar) {
  foreach ($pl in $daftar) { for ($i = 0; $i -lt $judul.Count; $i++) { if ($judul[$i] -match $pl) { return $i } } }
  return -1
}
$kol = $null; $mulai = 0
for ($baris = 0; $baris -lt [Math]::Min(15, $semua.Count); $baris++) {
  $judul = @($semua[$baris] | ForEach-Object { ($_ -replace '[^A-Za-z0-9]', '').ToLower() })
  $coba = [ordered]@{}
  foreach ($k in $pola.Keys) { $coba[$k] = Cari-Kolom $judul $pola[$k] }
  if ($coba.status -lt 0) { continue }
  if ($coba.tp -lt 0) {
    # Judul kolom nomor test pit diganti (misalnya jadi "Q"): cari kolom yang isinya "TP 01", "TP 02", ...
    $contoh = $semua.GetRange($baris + 1, [Math]::Min(30, $semua.Count - $baris - 1))
    for ($i = 0; $i -lt $judul.Count; $i++) {
      $cocok = @($contoh | Where-Object { $i -lt $_.Count -and $_[$i] -match '^\s*TP[\s\-_.]*\d' }).Count
      if ($cocok -ge [Math]::Max(3, [int]($contoh.Count / 2))) { $coba.tp = $i; Write-Host ('  Catatan: kolom nomor test pit dikenali dari isinya (judul kolom: "' + $semua[$baris][$i] + '").'); break }
    }
  }
  if ($coba.tp -ge 0) { $kol = $coba; $mulai = $baris + 1; break }
}
if (-not $kol) { throw 'Kolom nomor test pit (isi "TP 01" dst.) dan "Status" tidak ditemukan di 15 baris pertama Sheet.' }
$hilang = @($kol.Keys | Where-Object { $kol[$_] -lt 0 })
if ($hilang.Count) { Write-Host ('  Catatan: kolom tidak ditemukan dan dianggap kosong: ' + ($hilang -join ', ')) }

# 4. Tulis CSV rapi: hanya baris yang nomor test pit-nya berisi angka
function Q([string]$s) { '"' + ($s -replace '"', '""') + '"' }
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine((@($kol.Keys) -join ','))
$n = 0
for ($r = $mulai; $r -lt $semua.Count; $r++) {
  $f = $semua[$r]
  $nilai = foreach ($k in $kol.Keys) {
    $i = $kol[$k]
    if ($i -ge 0 -and $i -lt $f.Count) { $f[$i].Trim() } else { '' }
  }
  if ($nilai[0] -notmatch '\d') { continue }
  [void]$sb.AppendLine((@($nilai | ForEach-Object { Q $_ }) -join ','))
  $n++
}
[IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
Write-Host "  $n baris test pit diunduh dari Sheet."
