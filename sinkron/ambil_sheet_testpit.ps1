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

# 3. Cari baris judul (boleh ada baris judul laporan di atasnya; dicari di 15 baris pertama)
#    Judul dinormalkan: huruf kecil, tanpa spasi dan tanda baca. "No. Test Pit" -> "notestpit"
$pola = [ordered]@{
  tp        = '^(no)?(testpit|tp)$'
  zona      = '^zona$'
  mh        = '^(no)?manhole$|^mh$'
  utilitas  = 'utilitas'
  permukaan = 'permukaan'
  status    = '^status$'
  tanggal   = 'tanggal'
  link      = '^link'
  mandor    = 'mandor'
}
$kol = $null
for ($baris = 0; $baris -lt 15 -and -not $p.EndOfData; $baris++) {
  $judul = @($p.ReadFields() | ForEach-Object { ($_ -replace '[^A-Za-z0-9]', '').ToLower() })
  $coba = [ordered]@{}
  foreach ($k in $pola.Keys) {
    $coba[$k] = -1
    for ($i = 0; $i -lt $judul.Count; $i++) { if ($judul[$i] -match $pola[$k]) { $coba[$k] = $i; break } }   # kolom pertama yang cocok
  }
  if ($coba.tp -ge 0 -and $coba.status -ge 0) { $kol = $coba; break }
}
if (-not $kol) { throw 'Kolom "No. Test Pit" dan "Status" tidak ditemukan di 15 baris pertama Sheet.' }
$hilang = @($kol.Keys | Where-Object { $kol[$_] -lt 0 })
if ($hilang.Count) { Write-Host ('  Catatan: kolom tidak ditemukan dan dianggap kosong: ' + ($hilang -join ', ')) }

# 4. Tulis CSV rapi: hanya baris yang nomor test pit-nya berisi angka
function Q([string]$s) { '"' + ($s -replace '"', '""') + '"' }
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine((@($kol.Keys) -join ','))
$n = 0
while (-not $p.EndOfData) {
  $f = $p.ReadFields()
  $nilai = foreach ($k in $kol.Keys) {
    $i = $kol[$k]
    if ($i -ge 0 -and $i -lt $f.Count) { $f[$i].Trim() } else { '' }
  }
  if ($nilai[0] -notmatch '\d') { continue }
  [void]$sb.AppendLine((@($nilai | ForEach-Object { Q $_ }) -join ','))
  $n++
}
$p.Close()
[IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
Write-Host "  $n baris test pit diunduh dari Sheet."
