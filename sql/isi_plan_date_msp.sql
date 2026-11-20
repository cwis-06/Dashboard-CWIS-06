-- =====================================================================
-- ISI TANGGAL RENCANA (plan_date) PIPA LATERAL DAN MANHOLE
-- Sumber : "MSP - KERTAS KERJA CWIS 06 0.2.xlsx", sheet "Skema Jadwal Pelaksanaan"
--          (diubah 21 Okt 2026), ditambah gambar "Urutan Pekerjaan Zona 2"
--          (Alternatif 1 dan 2). plan_date = tanggal RENCANA MULAI pekerjaan.
-- Cara   : jalankan sekali di DB Manager QGIS (SQL Window) atau pgAdmin, lalu
--          jalankan update_dashboard.bat. Aman diulang; menimpa plan_date yang cocok.
--
--   * Zona 1 Jacking      : tanggal per ruas dan per shaft dari MSP.
--   * Zona 2 Jacking      : urutan dari gambar Alternatif 1 / 2 (bagian 5), tanggal
--     dihitung dengan pola MSP: shaft dibuat berurutan mulai 9 Okt 2026, 21 hari per
--     shaft; jacking 21 hari per dorongan, mulai setelah kedua shaft-nya selesai dan
--     dorongan sebelumnya selesai. Shaft MH_06_0163 (Zona 1) selesai 9 Jan 2027 (MSP).
--   * Zona 3-6 Open Trench: MSP hanya per zona dan kelas kedalaman, jadi semua pipa
--     atau manhole di kelas yang sama mendapat tanggal MULAI kelas tersebut.
--   * Belum ada jadwal (plan_date tidak diubah): jacking Zona 6 (Kudu Raya,
--     MHJ_06_0284..0288B), jacking Zona 2 MHJ_06_0755..0776, dan manhole kelas
--     kedalaman 4-5 m di luar shaft (MH_06_0221, MH_06_0304A).
--
-- Ganti alternatif Zona 2 kapan saja:  SELECT sewer.terapkan_urutan_zona2(2);
-- lalu jalankan update_dashboard.bat.
-- =====================================================================
BEGIN;

-- 1. Pipa jacking Zona 1 (per ruas, dari MSP)
UPDATE sewer.lateral_pipe p SET plan_date = v.d
  FROM (VALUES
    ('MHJ_06_0158>MHJ_06_02_0150', DATE '2026-09-28'),  -- MH_06_0158 ke MH_06_0150
    ('MHJ_06_0160>MHJ_06_0158', DATE '2026-10-23'),  -- MH_06_0158 ke MH_06_0160
    ('MHJ_06_0162>MHJ_06_0160', DATE '2026-11-17'),  -- MH_06_0162 ke MH_06_0160
    ('MHJ_06_0163>MHJ_06_0162', DATE '2026-12-26'),  -- MH_06_0162 ke MH_06_0163
    ('MHJ_06_0189>MHJ_06_0163', DATE '2027-01-18'),  -- MH_06_0189 ke MH_06_0163
    ('MHJ_06_0190>MHJ_06_0189', DATE '2027-02-11'),  -- MH_06_0189 ke MH_06_0190
    ('MHJ_06_0191>MHJ_06_0190', DATE '2027-02-27'),  -- MH_06_0191 ke MH_06_0190
    ('MHJ_06_0193>MHJ_06_0191', DATE '2027-03-27'),  -- MH_06_0191 ke MH_06_0193
    ('MHJ_06_0195>MHJ_06_0193', DATE '2027-04-23'),  -- MH_06_0195 ke MH_06_0193
    ('MHJ_06_0196>MHJ_06_0195', DATE '2027-06-05'),  -- MH_06_0195 ke MH_06_0196
    ('MHJ_06_0212>MHJ_06_0196', DATE '2027-06-28'),  -- MH_06_0212 ke MH_06_0196
    ('MHJ_06_0236>MHJ_06_0212', DATE '2027-08-12'),  -- MH_06_0212 ke MH_06_0236
    ('MHJ_06_0238>MHJ_06_0236', DATE '2027-09-07'),  -- MH_06_0238 ke MH_06_0236
    ('MHJ_06_0268>MHJ_06_0238', DATE '2027-10-15'),  -- MH_06_0238 ke MH_06_0268
    ('MHJ_06_0270>MHJ_06_0268', DATE '2027-11-10'),  -- MH_06_0270 ke MH_06_0268
    ('MHJ_06_0272>MHJ_06_0270', DATE '2027-12-17')  -- MH_06_0270 ke MH_06_0272
  ) AS v(id, d)
 WHERE p.pipe_id = v.id;

-- 2. Manhole shaft Zona 1 (mulai pembuatan shaft, dari MSP)
UPDATE sewer.manhole m SET plan_date = v.d
  FROM (VALUES
    ('MHJ_06_0158', DATE '2026-09-01'),  -- Shaft MH_06_0158 (Arrival Shaft)
    ('MHJ_06_0160', DATE '2026-10-25'),  -- Shaft MH_06_0160 (Arrival Shaft)
    ('MHJ_06_0162', DATE '2027-01-10'),  -- Shaft MH_06_0162 (Arrival Shaft)
    ('MHJ_06_0163', DATE '2026-12-15'),  -- Shaft MH_06_0163 (Driving Shaft)
    ('MHJ_06_0189', DATE '2027-03-01'),  -- Shaft MH_06_0189 (Arrival Shaft)
    ('MHJ_06_0190', DATE '2027-02-04'),  -- Shaft MH_06_90 (Driving Shaft)
    ('MHJ_06_0191', DATE '2027-04-21'),  -- Shaft MH_06_0191 (Arrival Shaft)
    ('MHJ_06_0193', DATE '2027-05-17'),  -- Shaft MH_06_0193 (Arrival Shaft)
    ('MHJ_06_0195', DATE '2027-06-11'),  -- Shaft MH_06_0195 (Arrival Shaft)
    ('MHJ_06_0196', DATE '2027-07-07'),  -- Shaft MH_06_196 (Driving Shaft)
    ('MHJ_06_0212', DATE '2027-08-26'),  -- Shaft MH_06_0212 (Driving Shaft)
    ('MHJ_06_0236', DATE '2027-10-16'),  -- Shaft MH_06_236(Driving Shaft)
    ('MHJ_06_0238', DATE '2027-11-11'),  -- Shaft MH_06_238 (Driving Shaft)
    ('MHJ_06_0268', DATE '2027-12-06'),  -- Shaft MH_06_268 (Driving Shaft)
    ('MHJ_06_0270', DATE '2027-12-31'),  -- Shaft MH_06_270 (Driving Shaft)
    ('MHJ_06_0272', DATE '2028-01-26')  -- Shaft MH_06_272 (Driving Shaft)
  ) AS v(id, d)
 WHERE m.manhole_id = v.id;

-- 3. Pipa Open Trench Zona 3-6 (mulai pasang pipa PVC 200 per kelas kedalaman)
UPDATE sewer.lateral_pipe p SET plan_date = v.d
  FROM (VALUES
    (3, '1-2', DATE '2026-09-05'),  -- s/d 2027-05-01
    (3, '2-3', DATE '2027-01-03'),  -- s/d 2027-08-19
    (3, '3-4', DATE '2027-05-03'),  -- s/d 2027-12-10
    (4, '1-2', DATE '2026-10-05'),  -- s/d 2027-03-27
    (4, '2-3', DATE '2027-02-02'),  -- s/d 2027-07-19
    (4, '3-4', DATE '2027-06-02'),  -- s/d 2027-11-10
    (5, '1-2', DATE '2026-10-05'),  -- s/d 2027-05-17
    (5, '2-3', DATE '2027-02-02'),  -- s/d 2027-09-05
    (5, '3-4', DATE '2027-06-02'),  -- s/d 2027-12-28
    (6, '1-2', DATE '2026-10-05'),  -- s/d 2027-07-09
    (6, '2-3', DATE '2027-02-02'),  -- s/d 2027-10-26
    (6, '3-4', DATE '2027-06-02')  -- s/d 2028-02-15
  ) AS v(zone, kelas, d)
 WHERE p.method = 'Open Trench' AND p.zone = v.zone
   AND replace(p.depth_class, ' ', '') = v.kelas;

-- 4. Manhole precast Zona 3-6 (bukan shaft, bukan referensi paket sebelah)
UPDATE sewer.manhole m SET plan_date = v.d
  FROM (VALUES
    (3, 1000, '1-1.5', DATE '2027-05-02'),  -- s/d 2027-10-05
    (3, 1000, '1.5-2', DATE '2027-05-31'),  -- s/d 2028-01-12
    (3, 1200, '2-3', DATE '2027-08-20'),  -- s/d 2028-01-21
    (3, 1200, '3-4', DATE '2027-12-11'),  -- s/d 2028-03-29
    (4, 1000, '1-1.5', DATE '2027-03-30'),  -- s/d 2027-07-22
    (4, 1000, '1.5-2', DATE '2027-04-26'),  -- s/d 2027-10-14
    (4, 1200, '2-3', DATE '2027-07-20'),  -- s/d 2027-11-26
    (4, 1200, '3-4', DATE '2027-11-11'),  -- s/d 2028-02-08
    (5, 1000, '1-1.5', DATE '2027-05-19'),  -- s/d 2027-10-15
    (5, 1000, '1.5-2', DATE '2027-06-16'),  -- s/d 2028-01-18
    (5, 1200, '2-3', DATE '2027-09-06'),  -- s/d 2028-02-02
    (5, 1200, '3-4', DATE '2027-12-29'),  -- s/d 2028-04-16
    (6, 1000, '1-1.5', DATE '2027-07-11'),  -- s/d 2028-01-04
    (6, 1000, '1.5-2', DATE '2027-08-08'),  -- s/d 2028-04-20
    (6, 1200, '2-3', DATE '2027-10-27'),  -- s/d 2028-04-18
    (6, 1200, '3-4', DATE '2028-02-16')  -- s/d 2028-06-14
  ) AS v(zone, dia, kelas, d)
 WHERE m.zone = v.zone AND m.diameter_mm = v.dia
   AND replace(m.depth_class, ' ', '') = v.kelas
   AND m.shaft IS NULL AND NOT COALESCE(m.is_reference, false);

-- 5. Urutan pekerjaan Zona 2 (MH_06_0753 s/d 0163), dua alternatif
CREATE TABLE IF NOT EXISTS sewer.urutan_zona2 (
    alternatif  smallint NOT NULL,
    jenis       text     NOT NULL CHECK (jenis IN ('shaft', 'jacking')),
    urutan      smallint NOT NULL,
    kode        text     NOT NULL,   -- huruf urutan shaft (A, B, ...) atau nomor dorongan jacking
    asset_id    text     NOT NULL,   -- manhole_id (shaft) atau pipe_id (jacking)
    keterangan  text,                -- posisi alat jacking dan arah dorongan
    plan_start  date     NOT NULL,
    plan_finish date     NOT NULL,
    PRIMARY KEY (alternatif, jenis, urutan)
);
COMMENT ON TABLE sewer.urutan_zona2 IS
    'Urutan shaft dan jacking Zona 2 dari gambar Alternatif 1 dan 2. Tanggal dihitung dengan pola MSP (21 hari per shaft, 21 hari per dorongan). Boleh diedit langsung; terapkan ke plan_date dengan SELECT sewer.terapkan_urutan_zona2(n).';

CREATE TABLE IF NOT EXISTS sewer.pengaturan (kunci text PRIMARY KEY, nilai text);

DELETE FROM sewer.urutan_zona2;
INSERT INTO sewer.urutan_zona2 VALUES
    (1, 'shaft', 1, 'A', 'MHJ_06_0751', NULL, DATE '2026-10-09', DATE '2026-10-30'),
    (1, 'shaft', 2, 'B', 'MHJ_06_0752', NULL, DATE '2026-10-30', DATE '2026-11-20'),
    (1, 'shaft', 3, 'C', 'MHJ_06_0747', NULL, DATE '2026-11-20', DATE '2026-12-11'),
    (1, 'shaft', 4, 'D', 'MHJ_06_0745', NULL, DATE '2026-12-11', DATE '2027-01-01'),
    (1, 'shaft', 5, 'E', 'MHJ_06_0744', NULL, DATE '2027-01-01', DATE '2027-01-22'),
    (1, 'shaft', 6, 'F', 'MHJ_06_0743', NULL, DATE '2027-01-22', DATE '2027-02-12'),
    (1, 'shaft', 7, 'G', 'MHJ_06_0742', NULL, DATE '2027-02-12', DATE '2027-03-05'),
    (1, 'shaft', 8, 'H', 'MHJ_06_0741', NULL, DATE '2027-03-05', DATE '2027-03-26'),
    (1, 'shaft', 9, 'I', 'MHJ_06_0740', NULL, DATE '2027-03-26', DATE '2027-04-16'),
    (1, 'shaft', 10, 'J', 'MHJ_06_0739', NULL, DATE '2027-04-16', DATE '2027-05-07'),
    (1, 'shaft', 11, 'K', 'MHJ_06_0738', NULL, DATE '2027-05-07', DATE '2027-05-28'),
    (1, 'shaft', 12, 'L', 'MHJ_06_0737', NULL, DATE '2027-05-28', DATE '2027-06-18'),
    (1, 'jacking', 1, '1', 'MHJ_06_0752>MHJ_06_0751', 'a1 di MHJ_06_0751, dorong ke MHJ_06_0752', DATE '2026-11-20', DATE '2026-12-11'),
    (1, 'jacking', 2, '2', 'MHJ_06_0751>MHJ_06_0747', 'a1 di MHJ_06_0751, dorong ke MHJ_06_0747', DATE '2026-12-11', DATE '2027-01-01'),
    (1, 'jacking', 3, '3', 'MHJ_06_0747>MHJ_06_0745', 'b1 di MHJ_06_0745, dorong ke MHJ_06_0747', DATE '2027-01-01', DATE '2027-01-22'),
    (1, 'jacking', 4, '4', 'MHJ_06_0745>MHJ_06_0744', 'b1 di MHJ_06_0745, dorong ke MHJ_06_0744', DATE '2027-01-22', DATE '2027-02-12'),
    (1, 'jacking', 5, '5', 'MHJ_06_0744>MHJ_06_0743', 'c1 di MHJ_06_0743, dorong ke MHJ_06_0744', DATE '2027-02-12', DATE '2027-03-05'),
    (1, 'jacking', 6, '6', 'MHJ_06_0743>MHJ_06_0742', 'd1 di MHJ_06_0742, dorong ke MHJ_06_0743', DATE '2027-03-05', DATE '2027-03-26'),
    (1, 'jacking', 7, '7', 'MHJ_06_0742>MHJ_06_0741', 'd1 di MHJ_06_0742, dorong ke MHJ_06_0741', DATE '2027-03-26', DATE '2027-04-16'),
    (1, 'jacking', 8, '8', 'MHJ_06_0741>MHJ_06_0740', 'e1 di MHJ_06_0740, dorong ke MHJ_06_0741', DATE '2027-04-16', DATE '2027-05-07'),
    (1, 'jacking', 9, '9', 'MHJ_06_0740>MHJ_06_0739', 'f1 di MHJ_06_0739, dorong ke MHJ_06_0740', DATE '2027-05-07', DATE '2027-05-28'),
    (1, 'jacking', 10, '10', 'MHJ_06_0739>MHJ_06_0738', 'g1 di MHJ_06_0738, dorong ke MHJ_06_0739', DATE '2027-05-28', DATE '2027-06-18'),
    (1, 'jacking', 11, '11', 'MHJ_06_0738>MHJ_06_0737', 'g1 di MHJ_06_0738, dorong ke MHJ_06_0737', DATE '2027-06-18', DATE '2027-07-09'),
    (1, 'jacking', 12, '12', 'MHJ_06_0737>MHJ_06_0163', 'h1 di MHJ_06_0737, dorong ke MHJ_06_0163', DATE '2027-07-09', DATE '2027-07-30'),
    (2, 'shaft', 1, 'A', 'MHJ_06_0751', NULL, DATE '2026-10-09', DATE '2026-10-30'),
    (2, 'shaft', 2, 'B', 'MHJ_06_0752', NULL, DATE '2026-10-30', DATE '2026-11-20'),
    (2, 'shaft', 3, 'C', 'MHJ_06_0753', NULL, DATE '2026-11-20', DATE '2026-12-11'),
    (2, 'shaft', 4, 'D', 'MHJ_06_0747', NULL, DATE '2026-12-11', DATE '2027-01-01'),
    (2, 'shaft', 5, 'E', 'MHJ_06_0745', NULL, DATE '2027-01-01', DATE '2027-01-22'),
    (2, 'shaft', 6, 'F', 'MHJ_06_0744', NULL, DATE '2027-01-22', DATE '2027-02-12'),
    (2, 'shaft', 7, 'G', 'MHJ_06_0743', NULL, DATE '2027-02-12', DATE '2027-03-05'),
    (2, 'shaft', 8, 'H', 'MHJ_06_0742', NULL, DATE '2027-03-05', DATE '2027-03-26'),
    (2, 'shaft', 9, 'I', 'MHJ_06_0741', NULL, DATE '2027-03-26', DATE '2027-04-16'),
    (2, 'shaft', 10, 'J', 'MHJ_06_0740', NULL, DATE '2027-04-16', DATE '2027-05-07'),
    (2, 'shaft', 11, 'K', 'MHJ_06_0739', NULL, DATE '2027-05-07', DATE '2027-05-28'),
    (2, 'shaft', 12, 'L', 'MHJ_06_0738', NULL, DATE '2027-05-28', DATE '2027-06-18'),
    (2, 'shaft', 13, 'M', 'MHJ_06_0737', NULL, DATE '2027-06-18', DATE '2027-07-09'),
    (2, 'jacking', 1, '1', 'MHJ_06_0752>MHJ_06_0751', 'a1 di MHJ_06_0751, dorong ke MHJ_06_0752', DATE '2026-11-20', DATE '2026-12-11'),
    (2, 'jacking', 2, '2', 'MHJ_06_0753>MHJ_06_0752', 'b1 di MHJ_06_0752, dorong ke MHJ_06_0753', DATE '2026-12-11', DATE '2027-01-01'),
    (2, 'jacking', 3, '3', 'MHJ_06_0751>MHJ_06_0747', 'c1 di MHJ_06_0747, dorong ke MHJ_06_0751', DATE '2027-01-01', DATE '2027-01-22'),
    (2, 'jacking', 4, '4', 'MHJ_06_0747>MHJ_06_0745', 'c1 di MHJ_06_0747, dorong ke MHJ_06_0745', DATE '2027-01-22', DATE '2027-02-12'),
    (2, 'jacking', 5, '5', 'MHJ_06_0745>MHJ_06_0744', 'd1 di MHJ_06_0744, dorong ke MHJ_06_0745', DATE '2027-02-12', DATE '2027-03-05'),
    (2, 'jacking', 6, '6', 'MHJ_06_0744>MHJ_06_0743', 'e1 di MHJ_06_0743, dorong ke MHJ_06_0744', DATE '2027-03-05', DATE '2027-03-26'),
    (2, 'jacking', 7, '7', 'MHJ_06_0743>MHJ_06_0742', 'f1 di MHJ_06_0742, dorong ke MHJ_06_0743', DATE '2027-03-26', DATE '2027-04-16'),
    (2, 'jacking', 8, '8', 'MHJ_06_0742>MHJ_06_0741', 'f1 di MHJ_06_0742, dorong ke MHJ_06_0741', DATE '2027-04-16', DATE '2027-05-07'),
    (2, 'jacking', 9, '9', 'MHJ_06_0741>MHJ_06_0740', 'g1 di MHJ_06_0740, dorong ke MHJ_06_0741', DATE '2027-05-07', DATE '2027-05-28'),
    (2, 'jacking', 10, '10', 'MHJ_06_0740>MHJ_06_0739', 'h1 di MHJ_06_0739, dorong ke MHJ_06_0740', DATE '2027-05-28', DATE '2027-06-18'),
    (2, 'jacking', 11, '11', 'MHJ_06_0739>MHJ_06_0738', 'i1 di MHJ_06_0738, dorong ke MHJ_06_0739', DATE '2027-06-18', DATE '2027-07-09'),
    (2, 'jacking', 12, '12', 'MHJ_06_0738>MHJ_06_0737', 'i1 di MHJ_06_0738, dorong ke MHJ_06_0737', DATE '2027-07-09', DATE '2027-07-30'),
    (2, 'jacking', 13, '13', 'MHJ_06_0737>MHJ_06_0163', 'j1 di MHJ_06_0737, dorong ke MHJ_06_0163', DATE '2027-07-30', DATE '2027-08-20');

CREATE OR REPLACE FUNCTION sewer.terapkan_urutan_zona2(p_alt smallint)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE n_pipa int; n_mh int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sewer.urutan_zona2 WHERE alternatif = p_alt) THEN
        RAISE EXCEPTION 'Alternatif % tidak ada. Pilihan: %', p_alt,
            (SELECT string_agg(DISTINCT alternatif::text, ', ') FROM sewer.urutan_zona2);
    END IF;
    -- kosongkan dulu semua aset yang ada di alternatif mana pun, lalu isi dari alternatif terpilih
    UPDATE sewer.lateral_pipe SET plan_date = NULL
     WHERE pipe_id IN (SELECT asset_id FROM sewer.urutan_zona2 WHERE jenis = 'jacking');
    UPDATE sewer.manhole SET plan_date = NULL
     WHERE manhole_id IN (SELECT asset_id FROM sewer.urutan_zona2 WHERE jenis = 'shaft');
    UPDATE sewer.lateral_pipe p SET plan_date = u.plan_start
      FROM sewer.urutan_zona2 u
     WHERE u.alternatif = p_alt AND u.jenis = 'jacking' AND p.pipe_id = u.asset_id;
    GET DIAGNOSTICS n_pipa = ROW_COUNT;
    UPDATE sewer.manhole m SET plan_date = u.plan_start
      FROM sewer.urutan_zona2 u
     WHERE u.alternatif = p_alt AND u.jenis = 'shaft' AND m.manhole_id = u.asset_id;
    GET DIAGNOSTICS n_mh = ROW_COUNT;
    INSERT INTO sewer.pengaturan VALUES ('alternatif_zona2', p_alt::text)
        ON CONFLICT (kunci) DO UPDATE SET nilai = EXCLUDED.nilai;
    RETURN format('Alternatif %s diterapkan: %s ruas jacking, %s shaft', p_alt, n_pipa, n_mh);
END $$;

-- Alternatif aktif: yang tersimpan sebelumnya, atau 1 bila belum pernah dipilih
SELECT sewer.terapkan_urutan_zona2(COALESCE(
    (SELECT nilai::smallint FROM sewer.pengaturan WHERE kunci = 'alternatif_zona2'), 1::smallint));

-- 6. Ringkasan: berapa yang terisi dan berapa yang masih kosong
SELECT 'pipa lateral' AS aset, count(*) AS total, count(plan_date) AS terisi,
       count(*) - count(plan_date) AS kosong
  FROM sewer.lateral_pipe
UNION ALL
SELECT 'manhole', count(*), count(plan_date), count(*) - count(plan_date)
  FROM sewer.manhole WHERE NOT COALESCE(is_reference, false);

COMMIT;
