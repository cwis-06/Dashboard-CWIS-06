-- =====================================================================
-- BORE LOG / SOIL BORING CWIS-06 (layer baru)
-- Sumber: sheet "DOKUMEN TESTPIT & GEORADAR & BORELOG", tab BORE LOG
-- (20 November 2026). Hanya baris yang punya nomor manhole yang dimasukkan
-- (BH 01-05, 07-11, 14-16, 18-22; BH 06 diganti BH 46 sesuai laporan WA, ditambah BH 47, MH 0772A, MH 0775). BH 23 dan seterusnya belum punya manhole/lokasi;
-- tambahkan nanti lewat QGIS (cukup isi bh_no dan mh_ref, titik terisi dari manhole).
-- BH 18 dan BH 20: koordinat di sheet sama dengan titik lain (salah salin),
-- jadi diambil dari posisi manhole. BH 21, 22 tanpa koordinat: dari manhole.
-- Dijalankan setup_otomasi.bat. Aman diulang (isian yang sudah ada tidak ditimpa).
-- =====================================================================
SET search_path = sewer, public;

CREATE TABLE IF NOT EXISTS sewer.bore_log (
    bh_id        text PRIMARY KEY,                -- 'BH 01'; dibentuk otomatis dari bh_no
    bh_no        integer UNIQUE,                  -- kosong bila nomor BH belum diketahui
    zone         smallint,
    mh_ref       text,
    surface      text,
    status       text NOT NULL DEFAULT 'Direncanakan',   -- Direncanakan / Selesai
    exec_date    date,                            -- tanggal pelaksanaan
    workers      smallint,                        -- jumlah pekerja
    soil_type    text,                            -- jenis tanah hasil bore log
    depth_m      numeric(6,2),                    -- kedalaman bor
    gwl_m        numeric(6,2),                    -- muka air tanah
    doc_link     text,                            -- link dokumen bore log
    gpr_link     text,                            -- link dokumen GPR
    note         text,
    x numeric(12,3), y numeric(12,3), lon numeric(10,7), lat numeric(10,7),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    geom         geometry(Point, 32749)
);
ALTER TABLE sewer.bore_log ALTER COLUMN bh_no DROP NOT NULL;
CREATE INDEX IF NOT EXISTS bore_log_gix ON sewer.bore_log USING gist (geom);
COMMENT ON TABLE sewer.bore_log IS 'Titik bore log / soil boring. Titik kosong diisi dari posisi manhole mh_ref.';

CREATE OR REPLACE FUNCTION sewer.trg_bh() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.bh_no IS NULL AND NEW.bh_id ~* '^BH ?\d+$' THEN
        NEW.bh_no := regexp_replace(NEW.bh_id, '\D', '', 'g')::integer;
    END IF;
    IF NEW.bh_no IS NOT NULL THEN
        NEW.bh_id := 'BH ' || CASE WHEN NEW.bh_no < 10 THEN '0' ELSE '' END || NEW.bh_no;
    ELSIF NEW.bh_id IS NULL AND NEW.mh_ref IS NOT NULL THEN
        NEW.bh_id := 'BH di MH ' || substring(NEW.mh_ref from '(\d{4}[A-Z]?)$');   -- nomor BH belum diketahui
    END IF;
    IF NEW.bh_id IS NULL THEN RAISE EXCEPTION 'Isi bh_no, atau mh_ref bila nomor BH belum diketahui'; END IF;
    NEW.status := COALESCE(NULLIF(trim(NEW.status), ''), 'Direncanakan');
    IF NEW.geom IS NULL AND NEW.mh_ref IS NOT NULL THEN
        SELECT m.geom INTO NEW.geom FROM sewer.manhole m
         WHERE substring(m.manhole_id from '(\d{4}[A-Z]?)$') = substring(NEW.mh_ref from '(\d{4}[A-Z]?)$')
         LIMIT 1;
    END IF;
    IF NEW.geom IS NULL THEN
        RAISE EXCEPTION '% tanpa lokasi: isi titik di peta atau mh_ref yang ada di tabel manhole', NEW.bh_id;
    END IF;
    NEW.geom := ST_Force2D(NEW.geom);
    IF NEW.zone IS NULL THEN NEW.zone := sewer.zone_of(NEW.geom); END IF;
    NEW.x   := round(ST_X(NEW.geom)::numeric, 3);
    NEW.y   := round(ST_Y(NEW.geom)::numeric, 3);
    NEW.lon := round(ST_X(ST_Transform(NEW.geom, 4326))::numeric, 7);
    NEW.lat := round(ST_Y(ST_Transform(NEW.geom, 4326))::numeric, 7);
    IF TG_OP = 'UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_bh_derive ON sewer.bore_log;
CREATE TRIGGER trg_bh_derive BEFORE INSERT OR UPDATE ON sewer.bore_log
    FOR EACH ROW EXECUTE FUNCTION sewer.trg_bh();

INSERT INTO sewer.bore_log AS t
       (bh_no, zone, mh_ref, surface, status, exec_date, workers, doc_link, geom) VALUES
  (1, 2, 'MH_06_0752', 'Paving block', 'Selesai', DATE '2026-06-23', 4, 'https://drive.google.com/drive/folders/17Ry5QvzIwIDKFzfg6aQfVunuHOUh3ill', ST_SetSRID(ST_MakePoint(442176.399, 9231246.663), 32749)),
  (2, 2, 'MH_06_0751', 'Paving block', 'Selesai', DATE '2026-06-25', 4, 'https://drive.google.com/drive/folders/1ArK409q2tzkMdfwNtJwRxZIe1MGcEfbq', ST_SetSRID(ST_MakePoint(442220.443, 9231213.614), 32749)),
  (3, 2, 'MH_06_0747', 'Paving block', 'Selesai', DATE '2026-06-19', 4, 'https://drive.google.com/drive/folders/1tI5kmM_TW5gmyd2sXCskJHVd108ggHQa', ST_SetSRID(ST_MakePoint(442245.430, 9231198.271), 32749)),
  (4, 2, 'MH_06_0746', 'Paving block', 'Selesai', DATE '2026-06-25', 4, 'https://drive.google.com/drive/folders/1vCy4ETns4830pcaznNNwpgF0l9d4gYAE', ST_SetSRID(ST_MakePoint(442270.261, 9231183.166), 32749)),
  (5, 2, 'MH_06_0745', 'Paving block', 'Selesai', DATE '2026-06-26', 5, 'https://drive.google.com/drive/folders/167ozpRCncsabdjXsYGigFHwMdnEO5evb', ST_SetSRID(ST_MakePoint(442304.189, 9231167.401), 32749)),
  (7, 2, 'MH_06_0744', 'Paving block', 'Selesai', DATE '2026-06-27', 4, 'https://drive.google.com/drive/folders/1BIAtpsacxQTLrbM4kS1Hax_nFAcTbbES', ST_SetSRID(ST_MakePoint(442355.406, 9231159.935), 32749)),
  (8, 2, 'MH_06_0742', 'Paving block', 'Selesai', DATE '2026-06-28', 4, 'https://drive.google.com/drive/folders/1jVzHsN7bACQet6tQdEW4uQtQgco6DTEL', ST_SetSRID(ST_MakePoint(442413.351, 9231158.560), 32749)),
  (9, 2, 'MH_06_0741', 'Paving block', 'Selesai', DATE '2026-06-30', 4, 'https://drive.google.com/drive/folders/12ys704Dt-FbzWIk9JidT3NuD9Rw1fOn6', ST_SetSRID(ST_MakePoint(442461.462, 9231145.661), 32749)),
  (10, 2, 'MH_06_0740', 'Paving block', 'Selesai', DATE '2026-07-03', 4, 'https://drive.google.com/drive/folders/1B7uS3lPPZowJ7Dt0cZbWT1zGq3xLF4Rf', ST_SetSRID(ST_MakePoint(442492.295, 9231123.453), 32749)),
  (11, 2, 'MH_06_0739', 'Paving block', 'Selesai', DATE '2026-07-01', 4, 'https://drive.google.com/drive/folders/18w3c8EXe96baJHqi6i3Q-7xHq1Ifao7-', ST_SetSRID(ST_MakePoint(442542.993, 9231108.112), 32749)),
  (14, 1, 'MH_06_0158', 'Cor beton', 'Selesai', DATE '2026-07-14', 5, 'https://drive.google.com/drive/folders/1eY2zg0ttn8vTJUEY94ox5cmPFNcSFbcG', ST_SetSRID(ST_MakePoint(442619.948, 9231362.338), 32749)),
  (15, 1, 'MH_06_0159', 'Cor beton', 'Selesai', DATE '2026-08-19', 4, 'https://drive.google.com/drive/folders/1bwFKqPBe8F8wdeUIfGhWvSs3j7CuP6k-', ST_SetSRID(ST_MakePoint(442612.965, 9231313.001), 32749)),
  (16, 1, 'MH_06_0160', 'Cor beton', 'Selesai', DATE '2026-07-15', 4, 'https://drive.google.com/drive/folders/16joXnvUPN8NPzekr-P5Avrz9lj6cFDJi', ST_SetSRID(ST_MakePoint(442607.285, 9231273.143), 32749)),
  (18, 1, 'MH_06_0162', 'Cor beton', 'Selesai', DATE '2026-07-16', 3, 'https://drive.google.com/drive/folders/1P5_TwBK70fmGOrQBq5WuwLkKGqInQYml', NULL),
  (19, 1, 'MH_06_0163', 'Cor beton', 'Selesai', DATE '2026-07-18', 3, 'https://drive.google.com/drive/folders/13w3IwBMKYrxxC9Cn64pgF4IQV-RET9li', ST_SetSRID(ST_MakePoint(442585.737, 9231092.835), 32749)),
  (20, 1, 'MH_06_0189', 'Cor beton', 'Selesai', DATE '2026-07-16', 3, 'https://drive.google.com/drive/folders/18XV0doH_tK2Ymcbs1Y88noRjKSAriCPM', NULL),
  (21, 1, 'MH_06_0190', 'Cor beton', 'Selesai', DATE '2026-07-20', 5, 'https://drive.google.com/drive/folders/1sSVSAP1peF8Y8_pdD-Z1J1clINMqzajN', NULL),
  (22, 1, 'MH_06_0191', 'Cor beton', 'Direncanakan', NULL, NULL, NULL, NULL)
ON CONFLICT (bh_id) DO UPDATE SET
    status    = CASE WHEN t.status = 'Direncanakan' THEN EXCLUDED.status ELSE t.status END,
    exec_date = COALESCE(t.exec_date, EXCLUDED.exec_date),
    workers   = COALESCE(t.workers,   EXCLUDED.workers),
    surface   = COALESCE(t.surface,   EXCLUDED.surface),
    doc_link  = COALESCE(t.doc_link,  EXCLUDED.doc_link),
    mh_ref    = COALESCE(t.mh_ref,    EXCLUDED.mh_ref);

-- Tambahan dari laporan WhatsApp grup "CWIS 06 SITE KSO" (diekspor 20 November 2026).
-- Mengikuti WhatsApp: MH 0755 = BH 46 (di sheet tercatat BH 06, jadi BH 06 dihapus
-- bila masih berstatus Direncanakan). MH 0772A dan MH 0775 sudah di-borlog tetapi
-- nomor BH-nya tidak disebut, jadi ID-nya 'BH di MH 0772A' / 'BH di MH 0775';
-- isi bh_no di QGIS bila nomornya sudah diketahui.
DELETE FROM sewer.bore_log WHERE bh_no = 6 AND status = 'Direncanakan';
INSERT INTO sewer.bore_log AS t (bh_no, zone, mh_ref, status, exec_date, note) VALUES
  (46,   2,    'MH_06_0755',  'Selesai', DATE '2026-09-15', 'WA SITE KSO 15/09/2026: setting alat, pagar, uji kebisingan dan getaran BH 46 MH 0755.'),
  (47,   2,    'MH_06_0753',  'Selesai', DATE '2026-09-16', 'WA SITE KSO 16/09/2026: rambu, pagar, dan proses soil boring BH 47 MH 0753.'),
  (NULL, 2,    'MH_06_0772A', 'Selesai', DATE '2026-09-12', 'WA SITE KSO 9-11/09/2026: proses soil boring MH 0772; 12/09/2026: penandatanganan BA borelog di MH 0772A.'),
  (NULL, NULL, 'MH_06_0775',  'Selesai', DATE '2026-09-15', 'WA SITE KSO 15/09/2026: borlog on-going 10 m di MH 0775.')
ON CONFLICT (bh_id) DO UPDATE SET
    status    = CASE WHEN t.status = 'Direncanakan' THEN EXCLUDED.status ELSE t.status END,
    exec_date = COALESCE(t.exec_date, EXCLUDED.exec_date),
    mh_ref    = COALESCE(t.mh_ref,    EXCLUDED.mh_ref),
    note      = COALESCE(t.note,      EXCLUDED.note);
