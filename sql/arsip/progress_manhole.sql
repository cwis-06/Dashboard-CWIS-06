-- =====================================================================
-- Progres manual manhole (0-100 %) dan jenis pekerjaan yang sedang berjalan
-- Alur: staging.manhole_raw -> sewer.manhole_work -> sewer.v_manhole -> dashboard
--
-- Seluruhnya satu transaksi: kalau ada error, semua dibatalkan dan view lama
-- tetap utuh. Jalankan sekali dari atas ke bawah.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Pastikan kolom di staging ada (aman bila sudah pernah dibuat)
-- ---------------------------------------------------------------------
ALTER TABLE staging.manhole_raw
  ADD COLUMN IF NOT EXISTS progress_pct numeric(5,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS work_stage   text;

-- ---------------------------------------------------------------------
-- 2. Tabel progres manual (satu baris per manhole)
--    Dipisah dari sewer.manhole supaya v_manhole dan v_net_nodes tidak perlu
--    dibongkar. progress_pct NULL = belum diisi manual; dashboard memakai
--    progres dari tahap (stage_code) seperti sebelumnya.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sewer.manhole_work (
    manhole_id   text PRIMARY KEY
                 REFERENCES sewer.manhole(manhole_id)
                 ON UPDATE CASCADE ON DELETE CASCADE,
    progress_pct numeric(5,2) CHECK (progress_pct BETWEEN 0 AND 100),
    work_stage   text CHECK (work_stage IN (
                   'Galian Shaft',
                   'Pekerjaan Jacking',
                   'Pemasangan Pipa',
                   'Pengembalian Galian',
                   'House Keeping')),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON COLUMN sewer.manhole_work.progress_pct IS
    'Progres manual 0-100 (%). NULL = pakai progres dari tahap (stage_code).';

CREATE OR REPLACE FUNCTION sewer.touch_manhole_work() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_manhole_work_touch ON sewer.manhole_work;
CREATE TRIGGER trg_manhole_work_touch BEFORE UPDATE ON sewer.manhole_work
    FOR EACH ROW EXECUTE FUNCTION sewer.touch_manhole_work();

-- ---------------------------------------------------------------------
-- 3. Salin isi staging.manhole_raw ke tabel progres.
--    Hanya baris yang sudah diisi (progress > 0 atau ada jenis pekerjaan),
--    supaya manhole yang belum disentuh tidak menimpa progres dari tahap
--    dengan angka 0. Bisa dijalankan ulang kapan saja untuk sinkron ulang.
-- ---------------------------------------------------------------------
INSERT INTO sewer.manhole_work (manhole_id, progress_pct, work_stage)
SELECT DISTINCT ON (trim(r."Manhole"))
       trim(r."Manhole"),
       r.progress_pct,
       NULLIF(trim(r.work_stage), '')
  FROM staging.manhole_raw r
  JOIN sewer.manhole m ON m.manhole_id = trim(r."Manhole")
 WHERE r.progress_pct > 0
    OR NULLIF(trim(r.work_stage), '') IS NOT NULL
 ORDER BY trim(r."Manhole"), r.fid DESC
ON CONFLICT (manhole_id) DO UPDATE
   SET progress_pct = EXCLUDED.progress_pct,
       work_stage   = EXCLUDED.work_stage;

-- ---------------------------------------------------------------------
-- 4. Perbarui view dashboard.
--    Kolom lama tidak berubah urutan; work_stage ditambahkan di paling akhir,
--    dan progress_pct sekarang = progres manual, kalau kosong baru progres tahap.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW sewer.v_manhole AS
SELECT m.*,
       s.stage_label,
       COALESCE(w.progress_pct, s.cum_weight, 0) AS progress_pct,
       w.work_stage
  FROM sewer.manhole m
  LEFT JOIN sewer.ref_stage s
         ON s.asset_type = 'manhole' AND s.method = 'ALL' AND s.stage_code = m.stage_code
  LEFT JOIN sewer.manhole_work w
         ON w.manhole_id = m.manhole_id;

COMMIT;

-- =====================================================================
-- PENGECEKAN
-- =====================================================================
SELECT manhole_id, stage_code, progress_pct, work_stage
  FROM sewer.v_manhole
 WHERE work_stage IS NOT NULL OR progress_pct > 0
 ORDER BY manhole_id;

-- =====================================================================
-- CARA MENGISI SETELAH INI (pilih salah satu)
-- =====================================================================
-- a) Lewat SQL (tambah atau ubah):
-- INSERT INTO sewer.manhole_work (manhole_id, progress_pct, work_stage)
-- VALUES ('MHJ_06_0751', 40, 'Galian Shaft')
-- ON CONFLICT (manhole_id) DO UPDATE
--    SET progress_pct = EXCLUDED.progress_pct, work_stage = EXCLUDED.work_stage;
--
-- b) Lewat staging lalu sinkron: ubah progress_pct dan work_stage di
--    staging.manhole_raw, lalu jalankan ulang langkah 3 di atas.
--
-- c) Lewat QGIS: tambahkan layer sewer.manhole_work (centang "Also list tables
--    with no geometry"), lalu edit tabelnya. Baris baru bisa ditambah di situ.

-- =====================================================================
-- OPSIONAL: koreksi "selesai" yang muncul karena actual_date
-- Migrasi lama menandai selesai bila REALISASI PEKERJAAN terisi. Karena kolom
-- itu ternyata tanggal MULAI kerja, manhole yang hanya punya tanggal tersebut
-- ikut terbaca 100%. Cek dulu, ubah hanya yang memang belum selesai:
-- SELECT manhole_id, actual_date FROM sewer.manhole WHERE stage_code = 'selesai';
-- UPDATE sewer.manhole SET stage_code = 'belum_mulai' WHERE manhole_id = 'MHJ_06_0751';
