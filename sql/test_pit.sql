-- =====================================================================
-- TITIK TEST PIT CWIS-06: 215 titik (TP 01 sampai TP 215), zona 1 sampai 6
-- Sumber (20 November 2026):
--   * Sheet "DOKUMEN TESTPIT & GEORADAR & BORELOG", tab TEST PIT: manhole,
--     utilitas, permukaan, status, tanggal, mandor, link BA.
--   * TESPIT_ZONA_4_DAN_5.gpkg dan TESPIT_ZONA_6.gpkg: posisi TP 66 sampai 215.
--   * TP 01 sampai 65: koordinat manhole dari sheet. Koordinat yang jelas salah
--     ketik (satu sumbu tepat, sumbu lain meleset > 50 m) diganti posisi manhole
--     di database: TP 14, 34, 48, 51, 56, 60, 64.
--   * Laporan WhatsApp zona 1, 4, 5, 6 dipakai sebagai pembanding status.
-- Dijalankan setup_otomasi.bat. Aman diulang: titik baru ditambahkan; titik
-- yang sudah ada hanya diisi kolom yang masih kosong, dan status hanya
-- dinaikkan dari 'Direncanakan'. Posisi dan isian dari QGIS tidak ditimpa.
-- =====================================================================
SET search_path = sewer, public;

CREATE TABLE IF NOT EXISTS sewer.test_pit (
    tp_id          text PRIMARY KEY,               -- 'TP 01'; dibentuk otomatis dari tp_no
    tp_no          integer NOT NULL UNIQUE,        -- nomor test pit (cukup isi ini saat menambah titik)
    zone           smallint,                       -- kosong = diisi dari poligon zona
    mh_ref         text,                           -- manhole acuan, mis. MH_06_0183
    location_name  text,                           -- kosong = nama jalan pipa lateral terdekat (<= 30 m)
    status         text NOT NULL DEFAULT 'Direncanakan',  -- Direncanakan / Digali / Selesai / Ditunda
    actual_date    date,                           -- tanggal pelaksanaan
    plan_date      date,
    utility_found  text,
    surface        text,                           -- jenis permukaan
    mandor         text,
    doc_link       text,                           -- link BA test pit
    depth_m        numeric(6,2),
    ground_elev    numeric(8,3),
    note           text,
    x numeric(12,3), y numeric(12,3), lon numeric(10,7), lat numeric(10,7),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    geom           geometry(Point, 32749) NOT NULL
);
ALTER TABLE sewer.test_pit ADD COLUMN IF NOT EXISTS mh_ref   text;
ALTER TABLE sewer.test_pit ADD COLUMN IF NOT EXISTS surface  text;
ALTER TABLE sewer.test_pit ADD COLUMN IF NOT EXISTS mandor   text;
ALTER TABLE sewer.test_pit ADD COLUMN IF NOT EXISTS doc_link text;
CREATE INDEX IF NOT EXISTS test_pit_gix ON sewer.test_pit USING gist (geom);
COMMENT ON TABLE sewer.test_pit IS 'Titik test pit. Status: Direncanakan, Digali, Selesai, Ditunda.';

CREATE OR REPLACE FUNCTION sewer.trg_tp() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.tp_no IS NULL THEN
        NEW.tp_no := NULLIF(regexp_replace(COALESCE(NEW.tp_id, ''), '\D', '', 'g'), '')::integer;
    END IF;
    IF NEW.tp_no IS NULL THEN RAISE EXCEPTION 'Nomor test pit (tp_no) wajib diisi'; END IF;
    NEW.tp_id  := 'TP ' || CASE WHEN NEW.tp_no < 10 THEN '0' ELSE '' END || NEW.tp_no;
    NEW.status := COALESCE(NULLIF(trim(NEW.status), ''), 'Direncanakan');
    IF NEW.geom IS NULL AND NEW.mh_ref IS NOT NULL THEN
        SELECT m.geom INTO NEW.geom FROM sewer.manhole m
         WHERE substring(m.manhole_id from '(\d{4}[A-Z]?)$') = substring(NEW.mh_ref from '(\d{4}[A-Z]?)$')
         LIMIT 1;
    END IF;
    IF NEW.geom IS NULL THEN
        RAISE EXCEPTION '% tanpa lokasi: isi titik di peta atau mh_ref yang ada di tabel manhole', NEW.tp_id;
    END IF;
    NEW.geom := ST_Force2D(NEW.geom);
    IF NEW.zone IS NULL THEN NEW.zone := sewer.zone_of(NEW.geom); END IF;
    NEW.x   := round(ST_X(NEW.geom)::numeric, 3);
    NEW.y   := round(ST_Y(NEW.geom)::numeric, 3);
    NEW.lon := round(ST_X(ST_Transform(NEW.geom, 4326))::numeric, 7);
    NEW.lat := round(ST_Y(ST_Transform(NEW.geom, 4326))::numeric, 7);
    IF NEW.location_name IS NULL THEN
        SELECT p.location_name INTO NEW.location_name FROM sewer.lateral_pipe p
         WHERE ST_DWithin(p.geom, NEW.geom, 30) ORDER BY p.geom <-> NEW.geom LIMIT 1;
    END IF;
    IF TG_OP = 'UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;
ALTER TABLE sewer.test_pit ALTER COLUMN geom DROP NOT NULL;   -- trigger mengisi dari manhole bila kosong
DROP TRIGGER IF EXISTS trg_tp_derive ON sewer.test_pit;
CREATE TRIGGER trg_tp_derive BEFORE INSERT OR UPDATE ON sewer.test_pit
    FOR EACH ROW EXECUTE FUNCTION sewer.trg_tp();
UPDATE sewer.test_pit SET tp_no = tp_no;   -- seragamkan tp_id lama ('TP 66' tetap, 'TP 1' jadi 'TP 01')

INSERT INTO sewer.test_pit AS t
       (tp_no, zone, mh_ref, status, actual_date, utility_found, surface, mandor, doc_link, geom) VALUES
  (1, 2, 'MH_06_0752', 'Selesai', DATE '2026-07-26', 'PDAM HDPE 3″', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1Q-gbuhVqu_IWbFcMDKLlTIQnVA2FMjO5/view', ST_SetSRID(ST_MakePoint(442176.399, 9231246.663), 32749)),
  (2, 2, 'MH_06_0751', 'Selesai', DATE '2026-07-27', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1X0kTsXYYZJ2lxKfDhCCOTi0tavcBIjEa/view', ST_SetSRID(ST_MakePoint(442220.443, 9231213.614), 32749)),
  (3, 2, 'MH_06_0747', 'Selesai', DATE '2026-07-28', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1Kx9baMNjeWtvCJx7336KJTfOi9u9FsO6/view', ST_SetSRID(ST_MakePoint(442245.430, 9231198.271), 32749)),
  (4, 2, 'MH_06_0745', 'Selesai', DATE '2026-07-29', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/179oM8OJ_y4d92-_S5ZPeYT8Wq_uHodm9/view', ST_SetSRID(ST_MakePoint(442304.189, 9231167.401), 32749)),
  (5, 2, 'MH_06_0744', 'Direncanakan', NULL, NULL, 'Cor beton', NULL, NULL, ST_SetSRID(ST_MakePoint(442355.406, 9231159.935), 32749)),
  (6, 2, 'MH_06_0743', 'Direncanakan', NULL, NULL, 'Cor beton', NULL, NULL, ST_SetSRID(ST_MakePoint(442362.389, 9231166.545), 32749)),
  (7, 2, 'MH_06_0742', 'Selesai', DATE '2026-07-30', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/11EHgldUAyYPQ9TYsCaryhzmturXvobVB/view', ST_SetSRID(ST_MakePoint(442413.351, 9231158.560), 32749)),
  (8, 2, 'MH_06_0741', 'Selesai', DATE '2026-07-22', 'PDAM 3″, PDAM HDPE 3″', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1A7Bjsn1p8mihun2whNJGYzEpbY3Gbhgp/view', ST_SetSRID(ST_MakePoint(442461.462, 9231145.661), 32749)),
  (9, 2, 'MH_06_0740', 'Selesai', DATE '2026-07-23', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1-aUty0emH09genkJ6Nx3uPpk5R4J2PBk/view', ST_SetSRID(ST_MakePoint(442492.295, 9231123.453), 32749)),
  (10, 2, 'MH_06_0739', 'Selesai', DATE '2026-07-24', 'PDAM HDPE 3″', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/14LbyHB7A_2NB89RS2ATzuwzhT7AKOvCu/view', ST_SetSRID(ST_MakePoint(442542.993, 9231108.112), 32749)),
  (11, 2, 'MH_06_0738', 'Selesai', DATE '2026-07-25', 'PDAM HDPE 3″, PIPA PVC 1″', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1GYroPAFgQ7xhCo5rO2fShYw3EQE3Fug9/view', ST_SetSRID(ST_MakePoint(442565.910, 9231091.252), 32749)),
  (12, 2, 'MH_06_0737', 'Direncanakan', NULL, NULL, 'Cor beton', NULL, NULL, ST_SetSRID(ST_MakePoint(442577.693, 9231088.221), 32749)),
  (13, 1, 'MH_06_0158', 'Selesai', DATE '2026-08-24', 'KABEL', 'Cor beton', 'RICARDO', 'https://drive.google.com/file/d/1J8sLLAg9sqXbmqPaH2UV2Gcts_NK7noI/view', ST_SetSRID(ST_MakePoint(442619.948, 9231362.338), 32749)),
  (14, 1, 'MH_06_0160', 'Selesai', DATE '2026-09-17', 'KABEL', 'Cor beton', 'MISROH', 'https://drive.google.com/file/d/1m2sslrDzRDhtlCMqGFxsEVyV9YzIJAlm/view', ST_SetSRID(ST_MakePoint(442607.232, 9231273.301), 32749)),
  (15, 1, 'MH_06_0162', 'Selesai', DATE '2026-09-20', 'KABEL', 'Cor beton', 'MISROH', 'https://drive.google.com/file/d/1L_TII4ICLx-q0o1_B9HpvocdyXRdcsOD/view', ST_SetSRID(ST_MakePoint(442594.097, 9231166.456), 32749)),
  (16, 1, 'MH_06_0163', 'Selesai', DATE '2026-09-22', 'Tidak ada utilitas', 'Cor beton', 'MISROH', 'https://drive.google.com/file/d/1fdktD-QN7Hk-GWrFL7OR7N7fS3GzH30U/view', ST_SetSRID(ST_MakePoint(442585.737, 9231092.835), 32749)),
  (17, 1, 'MH_06_0189', 'Selesai', DATE '2026-09-26', 'KABEL', 'Cor beton', 'MISROH', 'https://drive.google.com/file/d/10KblQiKm3dn0ERrh8oN14NQnfdNZeQTL/view', ST_SetSRID(ST_MakePoint(442578.410, 9231059.068), 32749)),
  (18, 1, 'MH_06_0190', 'Selesai', DATE '2026-09-29', 'KABEL', 'Cor beton', 'MISROH', 'https://drive.google.com/file/d/1srbyhdLag5AddIjlrUpWqgCZM-6Jh5cg/view', ST_SetSRID(ST_MakePoint(442568.610, 9231030.629), 32749)),
  (19, 1, 'MH_06_0191', 'Selesai', DATE '2026-10-02', 'KABEL', 'Cor beton', 'MISROH', 'https://drive.google.com/file/d/1EQJtKiyjMGq1LW0Rg_oL75hOOVSuWKQ9/view', ST_SetSRID(ST_MakePoint(442552.206, 9230983.379), 32749)),
  (20, 1, 'MH_06_0193', 'Selesai', DATE '2026-10-07', 'KABEL', 'Cor beton', 'MISROH', 'https://drive.google.com/file/d/1kQWbdRYS4YsHEYdHcVgoV54B35DPmT94/view', ST_SetSRID(ST_MakePoint(442520.656, 9230876.334), 32749)),
  (21, 1, 'MH_06_0195', 'Selesai', DATE '2026-10-12', 'KABEL', 'Cor beton', 'MISROH', 'https://drive.google.com/file/d/1IHh9CG0uoMrtUgnXftARJl4XmxePaNGm/view', ST_SetSRID(ST_MakePoint(442484.650, 9230756.147), 32749)),
  (22, 1, 'MH_06_0196', 'Direncanakan', NULL, NULL, 'Cor beton', NULL, NULL, ST_SetSRID(ST_MakePoint(442463.524, 9230685.574), 32749)),
  (23, 1, 'MH_06_0212', 'Direncanakan', NULL, NULL, 'Cor beton', NULL, NULL, ST_SetSRID(ST_MakePoint(442433.317, 9230550.761), 32749)),
  (24, 1, 'MH_06_0236', 'Direncanakan', NULL, NULL, 'Cor beton', NULL, NULL, ST_SetSRID(ST_MakePoint(442419.657, 9230450.666), 32749)),
  (25, 1, 'MH_06_0238', 'Direncanakan', NULL, NULL, 'Cor beton', NULL, NULL, ST_SetSRID(ST_MakePoint(442412.562, 9230349.853), 32749)),
  (26, 1, 'MH_06_0268', 'Direncanakan', NULL, NULL, 'Cor beton', NULL, NULL, ST_SetSRID(ST_MakePoint(442413.794, 9230256.354), 32749)),
  (27, 1, 'MH_06_0270', 'Direncanakan', NULL, NULL, 'Cor beton', NULL, NULL, ST_SetSRID(ST_MakePoint(442437.605, 9230157.455), 32749)),
  (28, 1, 'MH_06_0272', 'Direncanakan', NULL, NULL, 'Cor beton', NULL, NULL, ST_SetSRID(ST_MakePoint(442465.840, 9230061.611), 32749)),
  (29, 3, 'MH_06_0753', 'Selesai', DATE '2026-08-15', 'PIPA PVC 2″', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442130.406, 9231278.239), 32749)),
  (30, 3, 'MH_06_0729', 'Selesai', DATE '2026-08-15', 'PDAM HDPE 2″', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442107.710, 9231244.826), 32749)),
  (31, 3, 'MH_06_0550', 'Selesai', DATE '2026-08-10', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442090.598, 9231214.076), 32749)),
  (32, 3, 'MH_06_0771', 'Selesai', DATE '2026-08-11', 'PDAM 2″', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442037.523, 9231233.696), 32749)),
  (33, 3, 'MH_06_0775', 'Selesai', DATE '2026-08-12', 'PDAM HDPE 2″', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442196.150, 9231231.520), 32749)),
  (34, 3, 'MH_06_0776', 'Selesai', DATE '2026-08-13', 'PDAM HDPE 2″', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(441946.754, 9231292.747), 32749)),
  (35, 3, 'MH_06_0799', 'Selesai', DATE '2026-08-14', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(441899.011, 9231203.672), 32749)),
  (36, 3, 'MH_06_0753', 'Selesai', DATE '2026-08-10', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442086.571, 9231144.838), 32749)),
  (37, 3, 'MH_06_0769', 'Selesai', DATE '2026-08-08', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442165.432, 9231163.964), 32749)),
  (38, 3, 'MH_06_0757', 'Selesai', DATE '2026-08-05', 'PDAM HDPE 2″', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442187.531, 9231163.911), 32749)),
  (39, 3, 'MH_06_0758', 'Selesai', DATE '2026-08-06', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442205.512, 9231188.122), 32749)),
  (40, 3, 'MH_06_0801', 'Selesai', DATE '2026-08-05', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442234.639, 9231137.736), 32749)),
  (41, 3, 'MH_06_0800', 'Selesai', DATE '2026-08-04', 'PDAM HDPE', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442282.711, 9231104.716), 32749)),
  (42, 3, 'MH_06_0734', 'Selesai', DATE '2026-09-10', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442344.465, 9231118.882), 32749)),
  (43, 3, 'MH_06_0732', 'Selesai', DATE '2026-09-09', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442411.951, 9231098.649), 32749)),
  (44, 3, 'MH_06_0708', 'Selesai', DATE '2026-09-11', 'PIPA PVC 2″', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442438.188, 9231033.210), 32749)),
  (45, 3, 'MH_06_0707', 'Direncanakan', NULL, NULL, 'Paving block', NULL, NULL, ST_SetSRID(ST_MakePoint(442429.455, 9231006.329), 32749)),
  (46, 3, 'MH_06_0729', 'Ditunda', NULL, NULL, 'Cor beton', NULL, NULL, ST_SetSRID(ST_MakePoint(442538.654, 9231071.620), 32749)),
  (47, 3, 'MH_06_0705', 'Direncanakan', NULL, NULL, 'Paving block', NULL, NULL, ST_SetSRID(ST_MakePoint(442502.933, 9230993.714), 32749)),
  (48, 3, 'MH_06_0754', 'Selesai', DATE '2026-08-14', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442130.261, 9231342.212), 32749)),
  (49, 3, 'MH_06_0748', 'Selesai', DATE '2026-08-19', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442265.360, 9231226.970), 32749)),
  (50, 3, 'MH_06_0750', 'Direncanakan', NULL, NULL, 'Paving block', NULL, NULL, ST_SetSRID(ST_MakePoint(442310.950, 9231206.115), 32749)),
  (51, 3, 'MH_06_0835', 'Selesai', DATE '2026-08-21', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442394.547, 9231196.444), 32749)),
  (52, 3, 'MH_06_0831', 'Selesai', DATE '2026-08-27', 'PDAM HDPE 2″', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442404.188, 9231221.996), 32749)),
  (53, 3, 'MH_06_0828', 'Selesai', DATE '2026-08-27', 'PDAM HDPE 2″', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442414.330, 9231277.710), 32749)),
  (54, 3, 'MH_06_0822', 'Selesai', DATE '2026-09-06', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442419.066, 9231301.897), 32749)),
  (55, 3, 'MH_06_0824', 'Selesai', DATE '2026-08-18', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442309.772, 9231320.175), 32749)),
  (56, 3, 'MH_06_0827', 'Selesai', DATE '2026-08-16', 'PDAM HDPE 3/4″', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442329.636, 9231427.678), 32749)),
  (57, 3, 'MH_06_0839', 'Selesai', DATE '2026-08-22', 'PDAM HDPE 3″, PVC 3″', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442411.877, 9231458.518), 32749)),
  (58, 3, 'MH_06_0821', 'Selesai', DATE '2026-08-23', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442435.184, 9231391.962), 32749)),
  (59, 3, 'MH_06_0157', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442568.357, 9231528.233), 32749)),
  (60, 3, 'MH_06_0152', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442553.291, 9231424.243), 32749)),
  (61, 3, 'MH_06_0153', 'Selesai', DATE '2026-08-31', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442540.343, 9231374.343), 32749)),
  (62, 3, 'MH_06_0817', 'Selesai', DATE '2026-08-29', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442499.448, 9231344.325), 32749)),
  (63, 3, 'MH_06_0801', 'Selesai', DATE '2026-08-25', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442491.073, 9231285.616), 32749)),
  (64, 3, 'MH_06_0151A', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442614.727, 9231408.855), 32749)),
  (65, 3, 'MH_06_0810A', 'Selesai', DATE '2026-09-08', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/drive/folders/110hhE6YsxzRiaMUnHyregxHDWMbyFru2', ST_SetSRID(ST_MakePoint(442589.846, 9231175.365), 32749)),
  (66, 4, 'MH_06_0183', 'Selesai', DATE '2026-09-18', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.480611382, -6.954401777), 4326), 32749)),
  (67, 4, 'MH_06_0182', 'Selesai', DATE '2026-09-19', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481081628, -6.954564905), 4326), 32749)),
  (68, 4, 'MH_06_0181A', 'Selesai', DATE '2026-09-26', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481731886, -6.954164553), 4326), 32749)),
  (69, 4, 'MH_06_0181', 'Selesai', DATE '2026-09-24', 'PDAM HDPE 2″', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481851151, -6.953761701), 4326), 32749)),
  (70, 4, 'MH_06_0175', 'Selesai', DATE '2026-09-29', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.482169003, -6.954737130), 4326), 32749)),
  (71, 4, 'MH_06_0176', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482641330, -6.954869514), 4326), 32749)),
  (72, 4, 'MH_06_0178A', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482786090, -6.954364112), 4326), 32749)),
  (73, 4, 'MH_06_0178', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482900321, -6.954018631), 4326), 32749)),
  (74, 4, 'MH_06_0179', 'Selesai', DATE '2026-09-30', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.483128291, -6.954872162), 4326), 32749)),
  (75, 4, 'MH_06_0144', 'Selesai', DATE '2026-10-14', 'Tidak ada utilitas', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.483834977, -6.955014823), 4326), 32749)),
  (76, 4, 'MH_06_0144A', 'Selesai', DATE '2026-10-14', 'Tidak ada utilitas', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.484047372, -6.954339183), 4326), 32749)),
  (77, 4, 'MH_06_0174', 'Selesai', DATE '2026-09-21', 'PDAM HDPE 2″', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481550940, -6.954737187), 4326), 32749)),
  (78, 4, 'MH_06_0171', 'Selesai', DATE '2026-09-23', 'PIPA PEMBUANGAN WARGA 3″', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481582294, -6.955071357), 4326), 32749)),
  (79, 4, 'MH_06_0170', 'Selesai', DATE '2026-09-22', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481452263, -6.955500194), 4326), 32749)),
  (80, 4, 'MH_06_0163', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480315258, -6.955947158), 4326), 32749)),
  (81, 4, 'MH_06_0165', 'Selesai', DATE '2026-10-17', 'PDAM HDPE 3″', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.480818282, -6.955906236), 4326), 32749)),
  (82, 4, 'MH_06_0167', 'Selesai', DATE '2026-10-16', 'PIPA PVC 2″', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481156548, -6.955883323), 4326), 32749)),
  (83, 4, 'MH_06_0184A', 'Selesai', DATE '2026-10-15', 'PDAM HDPE 3″', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481880408, -6.956008683), 4326), 32749)),
  (84, 4, 'MH_06_0184', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482215425, -6.956076439), 4326), 32749)),
  (85, 4, 'MH_06_0187', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482453839, -6.955459002), 4326), 32749)),
  (86, 4, 'MH_06_0176A', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482559212, -6.955135691), 4326), 32749)),
  (87, 4, 'MH_06_0146', 'Selesai', DATE '2026-10-06', 'PIPA PVC 3″', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.483540002, -6.955236119), 4326), 32749)),
  (88, 4, 'MH_06_0147', 'Selesai', DATE '2026-10-07', 'Tidak ada utilitas', 'Tanah', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.483379014, -6.955763827), 4326), 32749)),
  (89, 4, 'MH_06_0147', 'Selesai', DATE '2026-10-08', 'Tidak ada utilitas', 'Paving block', 'RICARDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.483575380, -6.955807813), 4326), 32749)),
  (90, 4, NULL, 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.483236134, -6.956098350), 4326), 32749)),
  (91, 4, 'MH_06_0713', 'Selesai', DATE '2026-10-19', 'Tidak ada utilitas', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.480143207, -6.956496852), 4326), 32749)),
  (92, 4, 'MH_06_0714', 'Selesai', DATE '2026-10-18', 'Tidak ada utilitas', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.480717176, -6.956778267), 4326), 32749)),
  (93, 4, 'MH_06_0715', 'Selesai', DATE '2026-10-20', 'Tidak ada utilitas', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481201514, -6.956962433), 4326), 32749)),
  (94, 4, 'MH_06_0728', 'Selesai', DATE '2026-10-25', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481892322, -6.956685327), 4326), 32749)),
  (95, 4, 'MH_06_0188', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482143167, -6.956539397), 4326), 32749)),
  (96, 4, 'MH_06_0716', 'Selesai', DATE '2026-10-21', 'Tidak ada utilitas', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481193242, -6.957389423), 4326), 32749)),
  (97, 4, 'MH_06_0719', 'Selesai', DATE '2026-10-22', 'PIPA PVC 3″', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481998011, -6.957536382), 4326), 32749)),
  (98, 4, 'MH_06_0721', 'Selesai', DATE '2026-10-23', 'Tidak ada utilitas', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.482771127, -6.957788614), 4326), 32749)),
  (99, 4, 'MH_06_0723', 'Selesai', DATE '2026-10-24', 'Tidak ada utilitas', 'Paving block', 'MISROH', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.483417402, -6.957892458), 4326), 32749)),
  (100, 4, 'MH_06_0686', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479739523, -6.957888140), 4326), 32749)),
  (101, 4, 'MH_06_0687', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480644763, -6.958055935), 4326), 32749)),
  (102, 4, 'MH_06_0704', 'Selesai', DATE '2026-11-06', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.480762502, -6.957626787), 4326), 32749)),
  (103, 4, 'MH_06_0692', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481446040, -6.958168907), 4326), 32749)),
  (104, 4, 'MH_06_0724', 'Selesai', DATE '2026-11-08', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481477104, -6.957851567), 4326), 32749)),
  (105, 4, 'MH_06_0699', 'Selesai', DATE '2026-11-04', 'PIPA PVC 3″, PIPA 1/4″', 'Paving block', 'MUHAJIR', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.482661158, -6.959704139), 4326), 32749)),
  (106, 4, 'MH_06_0720A', 'Selesai', DATE '2026-11-02', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.481981354, -6.957899608), 4326), 32749)),
  (107, 4, 'MH_06_0695', 'Selesai', DATE '2026-11-02', 'PIPA PVC ARTESIS 4″', 'Paving block', 'MUHAJIR', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.482031943, -6.958269087), 4326), 32749)),
  (108, 4, 'MH_06_0702', 'Selesai', DATE '2026-11-04', 'PDAM HDPE 2″', 'Paving block', 'JACKINDO', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.482015345, -6.958603883), 4326), 32749)),
  (109, 4, 'MH_06_0696', 'Selesai', DATE '2026-11-03', 'PIPA PVC 3″', 'Paving block', 'MUHAJIR', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.482539327, -6.958333088), 4326), 32749)),
  (110, 4, 'MH_06_0697', 'Selesai', DATE '2026-11-03', 'PIPA PVC 3″', 'Paving block', 'MUHAJIR', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.483094589, -6.958472843), 4326), 32749)),
  (111, 4, 'MH_06_0700', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.483443838, -6.958597810), 4326), 32749)),
  (112, 4, 'MH_06_0698A', 'Selesai', DATE '2026-11-03', 'PIPA PVC 0,3″, PIPA PVC 3″', 'Paving block', 'MUHAJIR', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.482911397, -6.958922274), 4326), 32749)),
  (113, 4, 'MH_06_0698', 'Selesai', DATE '2026-11-04', 'PIPA PVC 3″', 'Paving block', 'MUHAJIR', 'https://drive.google.com/file/d/1YQRQhYLaUH_Kdl0RSvB-STzrkj3t66pp/view', ST_Transform(ST_SetSRID(ST_MakePoint(110.482790822, -6.959304672), 4326), 32749)),
  (114, 4, 'MH_06_0701', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.483256891, -6.958995957), 4326), 32749)),
  (115, 5, 'MH_06_0649', 'Selesai', DATE '2026-10-23', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479820312, -6.959077845), 4326), 32749)),
  (116, 5, 'MH_06_0650', 'Selesai', DATE '2026-10-27', 'PIPA ARTESIS PVC 2''', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480218732, -6.959090549), 4326), 32749)),
  (117, 5, 'MH_06_0653', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480516424, -6.958937100), 4326), 32749)),
  (118, 5, 'MH_06_0674', 'Selesai', DATE '2026-10-28', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480625856, -6.958390205), 4326), 32749)),
  (119, 5, 'MH_06_0673', 'Selesai', DATE '2026-11-09', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480765347, -6.959404480), 4326), 32749)),
  (120, 5, 'MH_06_0656', 'Selesai', DATE '2026-10-30', 'PIPA ARTESIS PVC 2''', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480997024, -6.959048346), 4326), 32749)),
  (121, 5, 'MH_06_0671', 'Selesai', DATE '2026-10-29', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481235119, -6.958502767), 4326), 32749)),
  (122, 5, 'MH_06_0658', 'Selesai', DATE '2026-10-31', 'PIPA ARTESIS PVC 2'', PDAM HDPE 2″', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481377157, -6.959069902), 4326), 32749)),
  (123, 5, 'MH_06_0666', 'Selesai', DATE '2026-11-01', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481731891, -6.958601456), 4326), 32749)),
  (124, 5, 'MH_06_0660', 'Selesai', DATE '2026-11-02', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481901701, -6.959137812), 4326), 32749)),
  (125, 5, 'MH_06_0664', 'Selesai', DATE '2026-11-05', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482348623, -6.958903947), 4326), 32749)),
  (126, 5, 'MH_06_0662', 'Selesai', DATE '2026-11-08', 'PIPA PVC PDAM 3''', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482638500, -6.959200002), 4326), 32749)),
  (127, 5, 'MH_06_0676', 'Selesai', DATE '2026-11-07', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480330349, -6.959486896), 4326), 32749)),
  (128, 5, 'MH_06_0678', 'Selesai', DATE '2026-11-08', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480794062, -6.959585541), 4326), 32749)),
  (129, 5, 'MH_06_0680', 'Selesai', DATE '2026-11-11', 'PIPA PVC 2,5″', 'Paving block', 'MANDALA', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481233623, -6.959890028), 4326), 32749)),
  (130, 5, 'MH_06_0682', 'Selesai', DATE '2026-11-11', 'Tidak ada utilitas', 'Paving block', 'SOBIRIN', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481658222, -6.960135386), 4326), 32749)),
  (131, 5, 'MH_06_0683', 'Selesai', DATE '2026-11-11', 'PIPA PVC 3/4″', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482122312, -6.960237386), 4326), 32749)),
  (132, 5, 'MH_06_0685', 'Selesai', DATE '2026-11-10', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482798854, -6.960477545), 4326), 32749)),
  (133, 5, 'MH_06_0196', 'Selesai', DATE '2026-11-19', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479222121, -6.959646021), 4326), 32749)),
  (134, 5, 'MH_06_0197', 'Selesai', DATE '2026-11-12', 'Tidak ada utilitas', 'Paving block', 'SOBIRIN', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479982708, -6.960064457), 4326), 32749)),
  (135, 5, 'MH_06_0198', 'Selesai', DATE '2026-11-12', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480580282, -6.960378110), 4326), 32749)),
  (136, 5, 'MH_06_0209', 'Selesai', DATE '2026-11-11', 'Tidak ada utilitas', 'Paving block', 'MANDALA', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480804968, -6.960082375), 4326), 32749)),
  (137, 5, 'MH_06_0200', 'Selesai', DATE '2026-11-19', 'Tidak ada utilitas', 'Paving block', 'MANDALA', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481087875, -6.960706073), 4326), 32749)),
  (138, 5, 'MH_06_0202', 'Selesai', DATE '2026-11-16', 'PDAM 2″', 'Paving block', 'MANDALA', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481607891, -6.960826823), 4326), 32749)),
  (139, 5, 'MH_06_0204', 'Selesai', DATE '2026-11-16', 'Tidak ada utilitas', 'Paving block', 'MANDALA', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482178691, -6.961015289), 4326), 32749)),
  (140, 5, 'MH_06_0207', 'Selesai', DATE '2026-11-19', 'Tidak ada utilitas', 'Paving block', 'MANDALA', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481040715, -6.961081288), 4326), 32749)),
  (141, 5, 'MH_06_0213', 'Selesai', DATE '2026-11-13', 'Tidak ada utilitas', 'Paving block', 'SOBIRIN', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.478950883, -6.960822267), 4326), 32749)),
  (142, 5, 'MH_06_0214', 'Selesai', DATE '2026-11-13', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479589307, -6.960951200), 4326), 32749)),
  (143, 5, 'MH_06_0217', 'Selesai', DATE '2026-11-14', 'Tidak ada utilitas', 'Paving block', 'SOBIRIN', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480263960, -6.961450907), 4326), 32749)),
  (144, 5, 'MH_06_0218', 'Selesai', DATE '2026-11-12', 'Tidak ada utilitas', 'Paving block', 'MANDALA', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480645681, -6.960152955), 4326), 32749)),
  (145, 5, 'MH_06_0222', 'Selesai', DATE '2026-11-14', 'Tidak ada utilitas', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481244186, -6.961564519), 4326), 32749)),
  (146, 5, 'MH_06_0228A', 'Selesai', DATE '2026-11-17', 'PIPA PVC 3″', 'Paving block', 'MANDALA', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481581920, -6.961576441), 4326), 32749)),
  (147, 5, 'MH_06_0205', 'Selesai', DATE '2026-11-17', 'Tidak ada utilitas', 'Paving block', 'SOBIRIN', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482063468, -6.961386938), 4326), 32749)),
  (148, 5, 'MH_06_0230', 'Selesai', DATE '2026-11-17', 'Tidak ada utilitas', 'Paving block', 'MANDALA', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482833353, -6.961982308), 4326), 32749)),
  (149, 5, NULL, 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.478740708, -6.962643071), 4326), 32749)),
  (150, 5, 'MH_06_0240', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479363276, -6.962736827), 4326), 32749)),
  (151, 5, 'MH_06_0263', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479711441, -6.962361392), 4326), 32749)),
  (152, 5, 'MH_06_0265', 'Selesai', DATE '2026-11-08', 'Tidak ada utilitas', 'Paving block', NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479614407, -6.961841922), 4326), 32749)),
  (153, 5, 'MH_06_0264', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479916940, -6.961725350), 4326), 32749)),
  (154, 5, 'MH_06_0260', 'Selesai', DATE '2026-11-19', 'PDAM HDPE 2″', 'Paving block', 'MUHAJIR', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479687887, -6.963444949), 4326), 32749)),
  (155, 5, 'MH_06_0243A', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480095280, -6.962586706), 4326), 32749)),
  (156, 5, 'MH_06_0248', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480106400, -6.961893562), 4326), 32749)),
  (157, 5, 'MH_06_0244', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480429355, -6.961810335), 4326), 32749)),
  (158, 5, 'MH_06_0249', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480210676, -6.962906813), 4326), 32749)),
  (159, 5, 'MH_06_0252', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480815877, -6.962807478), 4326), 32749)),
  (160, 5, 'MH_06_0259A', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481291632, -6.962619299), 4326), 32749)),
  (161, 5, 'MH_06_0255A', 'Selesai', DATE '2026-11-20', 'PIPA PVC PDAM 1″', 'Paving block', 'MUHAJIR', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481673125, -6.962930263), 4326), 32749)),
  (162, 5, 'MH_06_0256', 'Selesai', DATE '2026-11-20', 'PDAM HDPE 2″', 'Paving block', NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482139493, -6.963013288), 4326), 32749)),
  (163, 5, 'MH_06_0257', 'Selesai', DATE '2026-11-20', 'PDAM HDPE 2″', 'Paving block', NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.482263673, -6.963471718), 4326), 32749)),
  (164, 5, 'MH_06_0241D', 'Selesai', DATE '2026-11-19', 'PDAM HDPE 2″', 'Paving block', 'SOBIRIN', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479412067, -6.963208311), 4326), 32749)),
  (165, 5, 'MH_06_0226', 'Selesai', DATE '2026-11-20', 'PDAM HDPE 2″', 'Paving block', NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481779204, -6.962319773), 4326), 32749)),
  (166, 5, 'MH_06_0223', 'Selesai', DATE '2026-11-20', 'PDAM HDPE 2″', 'Paving block', NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481411094, -6.961817184), 4326), 32749)),
  (167, 5, 'MH_06_0224', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.481211933, -6.962230893), 4326), 32749)),
  (168, 5, 'MH_06_0246', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480611696, -6.961965143), 4326), 32749)),
  (169, 5, 'MH_06_0234', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.480870535, -6.962298966), 4326), 32749)),
  (170, 5, 'MH_06_0649A', 'Selesai', DATE '2026-10-22', 'PIPA ARTESIS PVC 2''', 'Paving block', 'JACKINDO', NULL, ST_Transform(ST_SetSRID(ST_MakePoint(110.479382638, -6.958976813), 4326), 32749)),
  (171, 6, 'MH_06_0633', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442507.8646, 9230239.5490), 32749)),
  (172, 6, 'MH_06_0648', 'Selesai', DATE '2026-11-19', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442558.4455, 9230276.5000), 32749)),
  (173, 6, 'MH_06_0631', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442534.2065, 9230126.1690), 32749)),
  (174, 6, 'MH_06_0639A', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442691.0049, 9230222.7230), 32749)),
  (175, 6, 'MH_06_0647A', 'Selesai', DATE '2026-11-16', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442863.4315, 9230147.5430), 32749)),
  (176, 6, 'MH_06_0597', 'Selesai', DATE '2026-11-18', 'PIPA PVC 2″', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442513.0850, 9230060.9350), 32749)),
  (177, 6, 'MH_06_0600', 'Selesai', DATE '2026-11-18', 'PDAM HDPE 4″', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442673.0531, 9230054.9790), 32749)),
  (178, 6, 'MH_06_0604', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442849.6345, 9230026.3110), 32749)),
  (179, 6, 'MH_06_0647A', 'Selesai', DATE '2026-11-17', 'PDAM HDPE 2″', 'Paving block', NULL, NULL, ST_SetSRID(ST_MakePoint(442854.7155, 9230098.7000), 32749)),
  (180, 6, 'MH_06_0608A', 'Selesai', DATE '2026-11-17', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442906.7912, 9230032.2780), 32749)),
  (181, 6, 'MH_06_0610', 'Selesai', DATE '2026-11-16', 'PIPA PVC 2″', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442937.8395, 9230113.9580), 32749)),
  (182, 6, 'MH_06_0612', 'Selesai', DATE '2026-11-08', 'Tidak ada utilitas', 'Paving block', NULL, NULL, ST_SetSRID(ST_MakePoint(443015.4160, 9230187.3750), 32749)),
  (183, 6, 'MH_06_0606', 'Selesai', DATE '2026-11-17', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442950.5655, 9229997.2790), 32749)),
  (184, 6, 'MH_06_0617A', 'Selesai', DATE '2026-11-14', 'Tidak ada utilitas', 'Paving block', 'MANDALA', NULL, ST_SetSRID(ST_MakePoint(442657.5705, 9230001.9340), 32749)),
  (185, 6, 'MH_06_0617', 'Selesai', DATE '2026-11-13', 'Tidak ada utilitas', 'Paving block', 'MANDALA', NULL, ST_SetSRID(ST_MakePoint(442641.0396, 9229943.1470), 32749)),
  (186, 6, 'MH_06_0630', 'Selesai', DATE '2026-11-13', 'PIPA PVC 2″, PIPA PVC 2,5″', 'Paving block', 'MANDALA', NULL, ST_SetSRID(ST_MakePoint(442623.6750, 9229890.5730), 32749)),
  (187, 6, 'MH_06_0615', 'Selesai', DATE '2026-11-13', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442833.9299, 9229921.4500), 32749)),
  (188, 6, 'MH_06_0618', 'Selesai', DATE '2026-11-13', 'PIPA PVC 2″', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442787.2845, 9229908.7140), 32749)),
  (189, 6, 'MH_06_0621', 'Selesai', DATE '2026-11-12', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442946.9870, 9229892.2100), 32749)),
  (190, 6, 'MH_06_0625', 'Selesai', DATE '2026-11-14', 'Tidak ada utilitas', 'Tanah', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(443041.2910, 9229976.3590), 32749)),
  (191, 6, 'MH_06_0629', 'Selesai', DATE '2026-11-14', 'Tidak ada utilitas', 'Tanah', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(443122.4515, 9230001.5600), 32749)),
  (192, 6, 'MH_06_0632A', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442422.8869, 9230256.4600), 32749)),
  (193, 6, 'MH_06_0311', 'Selesai', DATE '2026-11-12', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442963.3980, 9229870.3780), 32749)),
  (194, 6, 'MH_06_0310', 'Selesai', DATE '2026-11-11', 'KABEL NYA 1,5mm', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442938.5270, 9229799.4050), 32749)),
  (195, 6, 'MH_06_0310B', 'Selesai', DATE '2026-11-11', 'KABEL NYA 1,5mm', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442915.9970, 9229754.0210), 32749)),
  (196, 6, 'MH_06_0309A', 'Selesai', DATE '2026-11-12', 'Tidak ada utilitas', 'Paving block', 'MANDALA', NULL, ST_SetSRID(ST_MakePoint(442881.6486, 9229680.4210), 32749)),
  (197, 6, 'MH_06_0305', 'Selesai', DATE '2026-11-10', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(442975.9782, 9229734.6760), 32749)),
  (198, 6, 'MH_06_0284', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442868.1364, 9229609.0820), 32749)),
  (199, 6, 'MH_06_0308', 'Selesai', DATE '2026-11-10', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(443056.6022, 9229737.1510), 32749)),
  (200, 6, 'MH_06_0304', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442946.4620, 9229671.3750), 32749)),
  (201, 6, 'MH_06_0285', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442923.5070, 9229597.5530), 32749)),
  (202, 6, 'MH_06_0302C', 'Selesai', DATE '2026-11-07', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(443069.0280, 9229786.5490), 32749)),
  (203, 6, 'MH_06_0300', 'Selesai', DATE '2026-11-09', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(443063.2171, 9229696.3190), 32749)),
  (204, 6, 'MH_06_0299', 'Selesai', DATE '2026-11-09', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(443040.7438, 9229631.4620), 32749)),
  (205, 6, 'MH_06_0286', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(443007.2190, 9229567.4870), 32749)),
  (206, 6, 'MH_06_0298', 'Selesai', DATE '2026-11-05', 'Tidak ada utilitas', 'Tanah', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(443195.8030, 9229769.2930), 32749)),
  (207, 6, 'MH_06_0297', 'Selesai', DATE '2026-11-05', 'PIPA PVC 1 1/4″, PIPA PVC 1″', 'Tanah', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(443190.6330, 9229719.5890), 32749)),
  (208, 6, 'MH_06_0295', 'Selesai', DATE '2026-11-06', 'PIPA PVC 1 1/2″', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(443142.2040, 9229714.6710), 32749)),
  (209, 6, 'MH_06_0290', 'Selesai', DATE '2026-11-06', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(443129.0700, 9229637.8480), 32749)),
  (210, 6, 'MH_06_0292', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(443237.3550, 9229617.5490), 32749)),
  (211, 6, 'MH_06_0289', 'Selesai', DATE '2026-11-07', 'Tidak ada utilitas', 'Paving block', 'MUHAJIR', NULL, ST_SetSRID(ST_MakePoint(443112.4150, 9229574.5920), 32749)),
  (212, 6, 'MH_06_0287', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(443076.4070, 9229524.3190), 32749)),
  (213, 6, 'MH_06_0288B', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(443132.3668, 9229492.7110), 32749)),
  (214, 6, 'MH_06_0288B', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(443200.9892, 9229458.3600), 32749)),
  (215, 6, 'MH_06_0284A', 'Direncanakan', NULL, NULL, NULL, NULL, NULL, ST_SetSRID(ST_MakePoint(442779.8577, 9229622.8060), 32749))
ON CONFLICT (tp_id) DO UPDATE SET
    status        = CASE WHEN t.status = 'Direncanakan' THEN EXCLUDED.status ELSE t.status END,
    actual_date   = COALESCE(t.actual_date,   EXCLUDED.actual_date),
    mh_ref        = COALESCE(t.mh_ref,        EXCLUDED.mh_ref),
    utility_found = COALESCE(t.utility_found, EXCLUDED.utility_found),
    surface       = COALESCE(t.surface,       EXCLUDED.surface),
    mandor        = COALESCE(t.mandor,        EXCLUDED.mandor),
    doc_link      = COALESCE(t.doc_link,      EXCLUDED.doc_link),
    zone          = COALESCE(t.zone,          EXCLUDED.zone);
