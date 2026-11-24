/**
 * Antrian salinan foto ke SharePoint Waskita.
 * Simpan sebagai file baru "Antrian.gs" di proyek Apps Script yang sama dengan Code.gs.
 * Panduan lengkap: panduan/02_foto_ke_sharepoint.md
 * Memakai fungsi yang sudah ada di Code.gs: sheet_(), info_(), tglSel_(), linkFoto_(), ZONA_WAKTU.
 *
 * Cara kerja (versi B, tanpa konektor Google Sheets di Power Automate):
 *  - tiap 15 menit, foto baru di tab "Dokumentasi Lapangan" dicatat ke tab "Antrian SharePoint";
 *  - daftar foto yang masuk antrian dalam HARI_JENDELA hari terakhir ditulis ke file
 *    "antrian_sharepoint.json" di folder Drive yang sama dengan Sheet foto;
 *  - Power Automate membaca file JSON itu (1 panggilan Google Drive), mengecek ke SharePoint
 *    apakah foto sudah ada, dan hanya menyalin yang belum ada.
 * Code.gs tidak diubah sama sekali.
 */
const NAMA_SHEET_ANTRIAN = 'Antrian SharePoint';
const KOLOM_ANTRIAN = ['file_id', 'nama_file', 'folder', 'tanggal', 'waktu', 'petugas', 'tim', 'kode',
                       'keterangan', 'lat', 'lng', 'link_foto', 'status', 'dicatat'];
const MAKS_PER_JALAN = 200;   // batas baris baru per sekali jalan (foto lama ikut masuk bertahap)
const NAMA_FILE_JSON = 'antrian_sharepoint.json';
const HARI_JENDELA = 7;       // foto yang masuk antrian dalam 7 hari terakhir ikut dicek flow

// Jalankan SEKALI dari editor: menyiapkan tab antrian dan mengisi foto lama.
// Pemicu 15 menit dibuat lewat menu Pemicu (ikon jam), BUKAN dari kode, supaya
// tidak butuh izin tambahan (script.scriptapp) yang sering gagal di akun ganda.
function siapkanAntrianSP() {
  const q = antrian_();
  q.getRange(1, 1, 1, KOLOM_ANTRIAN.length).setValues([KOLOM_ANTRIAN]);
  q.setFrozenRows(1);
  q.getRange('A:D').setNumberFormat('@');            // id, nama, folder, tanggal disimpan sebagai teks
  isiAntrianSP();
}

// Dipanggil pemicu tiap 15 menit. Bisa juga dijalankan manual untuk mencoba.
function isiAntrianSP() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(20000)) return;
  try {
    const data = sheet_().getDataRange().getValues();
    const h = data[0].map(String), c = n => h.indexOf(n);
    const q = antrian_();
    const ada = new Set(q.getLastRow() > 1
      ? q.getRange(2, 1, q.getLastRow() - 1, 1).getValues().flat().map(String) : []);
    const baru = [];
    for (let i = 1; i < data.length && baru.length < MAKS_PER_JALAN; i++) {
      const r = data[i], id = String(r[c('file_id')] || '');
      if (!id || ada.has(id)) continue;
      let nama;
      try { nama = DriveApp.getFileById(id).getName(); } catch (e) { continue; }   // file sudah dihapus: lewati
      if (!/\.jpe?g$/i.test(nama)) nama += '.jpg';
      const waktu = r[c('waktu')] instanceof Date ? r[c('waktu')] : new Date();
      const tg = tglSel_(r[c('tanggal')], waktu), f = info_(tg);
      const folder = f.bulan + ' ' + f.namaBulan + '/Pekan ' + f.pekan + '/' + f.tanggal + ' ' + f.hari;   // sama dengan susunan di Drive
      baru.push([id, nama, folder, tg, Utilities.formatDate(waktu, ZONA_WAKTU, 'yyyy-MM-dd HH:mm'),
                 r[c('petugas')], r[c('tim')], r[c('kode')], r[c('keterangan')], r[c('lat')], r[c('lng')],
                 linkFoto_(id), '', new Date()]);
      ada.add(id);
    }
    if (baru.length) q.getRange(q.getLastRow() + 1, 1, baru.length, KOLOM_ANTRIAN.length).setValues(baru);
    console.log('Masuk antrian: ' + baru.length + ' foto');
    tulisJsonSP();
  } finally {
    lock.releaseLock();
  }
}

// Melihat ringkasan: berapa yang sudah tersalin, belum, dan gagal.
function cekAntrianSP() {
  const q = antrian_(), n = q.getLastRow() - 1;
  if (n < 1) { console.log('Antrian kosong'); return; }
  const st = q.getRange(2, 13, n, 1).getValues().flat().map(s => String(s).toLowerCase());
  console.log('Total ' + n + ' | selesai ' + st.filter(s => s === 'selesai').length +
              ' | belum ' + st.filter(s => !s).length + ' | gagal ' + st.filter(s => s === 'gagal').length);
}

function antrian_() {
  const ss = sheet_().getParent();
  return ss.getSheetByName(NAMA_SHEET_ANTRIAN) || ss.insertSheet(NAMA_SHEET_ANTRIAN);
}

// Mengosongkan antrian (judul kolom tetap), lalu mengisi ulang semua foto dari awal.
// Kosongkan dulu folder tujuan di SharePoint supaya foto tidak dobel.
function ulangAntrianSP() {
  const q = antrian_();
  if (q.getLastRow() > 1) q.getRange(2, 1, q.getLastRow() - 1, q.getLastColumn()).clearContent();
  isiAntrianSP();
  console.log('Baris di antrian sekarang: ' + (q.getLastRow() - 1));
}

// Pemeriksaan bila antrian tetap kosong: tab, judul kolom, dan akses file Drive.
function diagnosaAntrianSP() {
  const data = sheet_().getDataRange().getValues();
  console.log('Sheet foto: ' + sheet_().getParent().getName() + ' / tab ' + sheet_().getName());
  console.log('Jumlah baris foto: ' + (data.length - 1));
  console.log('Judul kolom: ' + data[0].join(' | '));
  const c = data[0].map(String).indexOf('file_id');
  console.log('Posisi kolom file_id: ' + c);
  if (c >= 0 && data.length > 1) {
    const id = data[data.length - 1][c];
    console.log('Contoh file_id terakhir: ' + id);
    try { console.log('Nama file di Drive: ' + DriveApp.getFileById(id).getName()); }
    catch (e) { console.log('Gagal buka file di Drive: ' + e.message); }
  }
  console.log('Baris di Antrian SharePoint: ' + (antrian_().getLastRow() - 1));
}

// Menulis daftar foto untuk Power Automate ke file JSON di Drive.
// Isi: foto yang dicatat ke antrian dalam HARI_JENDELA hari terakhir,
// atau semua foto bila mode semua aktif (lihat modeSemuaSP).
function tulisJsonSP() {
  const q = antrian_(), n = q.getLastRow() - 1;
  const semua = PropertiesService.getScriptProperties().getProperty('SP_SEMUA') === '1';
  const batas = Date.now() - HARI_JENDELA * 24 * 3600 * 1000;
  const isi = [];
  if (n > 0) {
    q.getRange(2, 1, n, KOLOM_ANTRIAN.length).getValues().forEach(r => {
      const dicatat = r[13] instanceof Date ? r[13].getTime() : 0;      // kolom "dicatat"
      if (r[0] && (semua || dicatat >= batas)) {
        isi.push({ file_id: String(r[0]), nama_file: String(r[1]), folder: String(r[2]) });
      }
    });
  }
  const f = fileJson_();
  f.setContent(JSON.stringify(isi));
  console.log('File JSON (' + f.getName() + ', id ' + f.getId() + '): ' + isi.length + ' foto, ' +
              (semua ? 'mode semua' : HARI_JENDELA + ' hari terakhir'));
}

// Sekali-sekali: masukkan SEMUA foto ke file JSON (mis. untuk menyalin ulang foto lama).
function modeSemuaSP() {
  PropertiesService.getScriptProperties().setProperty('SP_SEMUA', '1');
  tulisJsonSP();
}

// Kembali ke mode biasa (hanya HARI_JENDELA hari terakhir).
function modeNormalSP() {
  PropertiesService.getScriptProperties().deleteProperty('SP_SEMUA');
  tulisJsonSP();
}

// File JSON dibuat sekali di folder tempat Sheet foto berada; ID-nya diingat di Script Properties.
function fileJson_() {
  const props = PropertiesService.getScriptProperties(), id = props.getProperty('SP_JSON_ID');
  if (id) { try { return DriveApp.getFileById(id); } catch (e) { /* file terhapus: buat lagi */ } }
  const folder = DriveApp.getFileById(sheet_().getParent().getId()).getParents().next();
  const f = folder.createFile(NAMA_FILE_JSON, '[]', MimeType.PLAIN_TEXT);
  props.setProperty('SP_JSON_ID', f.getId());
  return f;
}
