-- =====================================================================
-- WebGIS Monitoring Sewerage Installation Pipe - Banjardowo & Genuksari
-- PostgreSQL 12+ dengan PostGIS | SRID 32749 (UTM 49S)
--
-- Urutan pakai:
--   BAGIAN A  skema target (jalankan dulu)
--   BAGIAN B  QA data lama di schema "staging" (jalankan sebelum migrasi)
--   BAGIAN C  migrasi staging -> skema baru
--   BAGIAN D  pengecekan setelah migrasi
--
-- Sebelum Bagian B: impor layer lama ke schema "staging" lewat QGIS
-- (Database > DB Manager > Import Layer/File) dengan nama tabel
--   staging.manhole_raw dan staging.lateral_pipe_raw, kolom geometri "geom".
-- Nama kolom di Bagian B-C ditulis sesuai tabel atribut di QGIS. Jika ada
-- yang berbeda (nama kolom terpotong di tampilan), pesan error akan
-- menyebut nama kolomnya; tinggal disesuaikan.
-- =====================================================================


-- =====================================================================
-- BAGIAN A - SKEMA TARGET
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE SCHEMA IF NOT EXISTS sewer;
CREATE SCHEMA IF NOT EXISTS staging;
SET search_path = sewer, public;

-- A1. Referensi tahapan kerja dan bobot progres (kumulatif, 0-100)
--     Bobot di bawah hanya nilai awal; sesuaikan dengan bobot kontrak/RAB.
CREATE TABLE IF NOT EXISTS ref_stage (
    asset_type   text     NOT NULL CHECK (asset_type IN ('manhole','lateral_pipe')),
    method       text     NOT NULL DEFAULT 'ALL',   -- 'Jacking' | 'Open Trench' | 'ALL'
    stage_order  smallint NOT NULL,
    stage_code   text     NOT NULL,
    stage_label  text     NOT NULL,
    cum_weight   numeric(5,2) NOT NULL CHECK (cum_weight BETWEEN 0 AND 100),
    PRIMARY KEY (asset_type, method, stage_code),
    UNIQUE (asset_type, method, stage_order)
);

INSERT INTO ref_stage (asset_type, method, stage_order, stage_code, stage_label, cum_weight) VALUES
('manhole',      'ALL',         0, 'belum_mulai',  'Belum mulai',               0),
('manhole',      'ALL',         1, 'galian',       'Galian / shaft',           20),
('manhole',      'ALL',         2, 'base',         'Base / pondasi',           40),
('manhole',      'ALL',         3, 'dinding',      'Pemasangan ring / dinding',70),
('manhole',      'ALL',         4, 'finishing',    'Cover dan finishing',      90),
('manhole',      'ALL',         5, 'selesai',      'Selesai',                 100),
('lateral_pipe', 'Jacking',     0, 'belum_mulai',  'Belum mulai',               0),
('lateral_pipe', 'Jacking',     1, 'shaft_siap',   'Shaft AR/DR siap',         20),
('lateral_pipe', 'Jacking',     2, 'jacking',      'Proses jacking',           70),
('lateral_pipe', 'Jacking',     3, 'jointing',     'Jointing / grouting',      90),
('lateral_pipe', 'Jacking',     4, 'testing',      'Testing',                  95),
('lateral_pipe', 'Jacking',     5, 'selesai',      'Selesai',                 100),
('lateral_pipe', 'Open Trench', 0, 'belum_mulai',  'Belum mulai',               0),
('lateral_pipe', 'Open Trench', 1, 'galian',       'Galian',                   25),
('lateral_pipe', 'Open Trench', 2, 'bedding',      'Bedding',                  40),
('lateral_pipe', 'Open Trench', 3, 'pemasangan',   'Pemasangan pipa',          70),
('lateral_pipe', 'Open Trench', 4, 'backfill',     'Backfill',                 85),
('lateral_pipe', 'Open Trench', 5, 'reinstatement','Reinstatement',            95),
('lateral_pipe', 'Open Trench', 6, 'selesai',      'Selesai',                 100)
ON CONFLICT DO NOTHING;

-- A2. Manhole
CREATE TABLE IF NOT EXISTS manhole (
    manhole_id        text PRIMARY KEY,                 -- contoh: MHJ_06_0163
    manhole_no        integer,
    mh_type           text,                             -- Primary / Secondary
    zone              smallint,
    location_name     text,
    existing_pavement text,
    road_width_m      numeric(7,3),
    diameter_mm       integer,
    depth_class       text,                             -- mis. '3-4' (m)
    shaft             text CHECK (shaft IN ('AR','DR')),
    ground_elev       numeric(9,5),
    invert_elev       numeric(9,5),
    depth_m           numeric(9,5),
    elev_downstream   numeric(9,5),
    elev_upstream_1   numeric(9,5),
    elev_upstream_2   numeric(9,5),
    elev_upstream_3   numeric(9,5),
    q_design_m3day    numeric(14,3),
    velocity_ms       numeric(9,6),
    plan_date         date,                             -- RENCANA_PEKERJAAN
    actual_date       date,                             -- REALISASI PEKERJAAN
    stage_code        text NOT NULL DEFAULT 'belum_mulai',
    updated_at        timestamptz NOT NULL DEFAULT now(),
    geom              geometry(Point, 32749) NOT NULL
);
CREATE INDEX IF NOT EXISTS manhole_geom_gix  ON manhole USING gist (geom);
CREATE INDEX IF NOT EXISTS manhole_zone_idx  ON manhole (zone);
CREATE INDEX IF NOT EXISTS manhole_stage_idx ON manhole (stage_code);

-- A3. Lateral pipe (relasi hulu-hilir eksplisit ke manhole)
CREATE TABLE IF NOT EXISTS lateral_pipe (
    pipe_id           text PRIMARY KEY,                 -- from_mh || '>' || to_mh
    from_mh           text NOT NULL REFERENCES manhole(manhole_id),
    to_mh             text NOT NULL REFERENCES manhole(manhole_id),
    pipe_type         text CHECK (pipe_type IN ('Primary','Secondary','Tertiary')),  -- kelas pipa (hierarki)
    method            text NOT NULL CHECK (method IN ('Jacking','Open Trench')),
    material          text,
    diameter_mm       integer,
    depth_class       text,
    zone              smallint,
    location_name     text,
    existing_pavement text,
    road_width_m      numeric(7,3),
    length_as_to_as_m numeric(10,3),                    -- titik pusat MH ke titik pusat MH
    length_net_m      numeric(10,3),                    -- panjang bersih pipa
    length_m          numeric(10,3) GENERATED ALWAYS AS
                      (COALESCE(length_net_m, length_as_to_as_m)) STORED,
    up_gl             numeric(9,5),
    up_ie             numeric(9,5),
    up_depth          numeric(9,5),
    lw_gl             numeric(9,5),
    lw_ie             numeric(9,5),
    lw_depth          numeric(9,5),
    drop_m            numeric(9,5),
    slope_pct         numeric(9,5),
    q_design_m3day    numeric(14,3),
    v_full_ms         numeric(9,6),
    shaft             text CHECK (shaft IN ('AR','DR')),
    plan_date         date,
    actual_date       date,
    stage_code        text NOT NULL DEFAULT 'belum_mulai',
    updated_at        timestamptz NOT NULL DEFAULT now(),
    geom              geometry(LineString, 32749) NOT NULL,
    CHECK (from_mh <> to_mh)
);
CREATE INDEX IF NOT EXISTS lateral_pipe_geom_gix  ON lateral_pipe USING gist (geom);
CREATE INDEX IF NOT EXISTS lateral_pipe_from_idx  ON lateral_pipe (from_mh);
CREATE INDEX IF NOT EXISTS lateral_pipe_to_idx    ON lateral_pipe (to_mh);
CREATE INDEX IF NOT EXISTS lateral_pipe_zone_idx  ON lateral_pipe (zone, method);
CREATE INDEX IF NOT EXISTS lateral_pipe_stage_idx ON lateral_pipe (stage_code);

-- A4. Log progres harian (sumber riwayat dan grafik tren)
CREATE TABLE IF NOT EXISTS progress_log (
    log_id      bigserial PRIMARY KEY,
    asset_type  text NOT NULL CHECK (asset_type IN ('manhole','lateral_pipe')),
    asset_id    text NOT NULL,
    log_date    date NOT NULL DEFAULT current_date,
    stage_code  text NOT NULL,
    note        text,
    photo_url   text,
    reported_by text,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS progress_log_asset_idx ON progress_log (asset_type, asset_id, log_date);
CREATE INDEX IF NOT EXISTS progress_log_date_idx  ON progress_log (log_date);

-- Trigger: updated_at otomatis bila atribut diedit (mis. dari QGIS/QField)
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_manhole_touch ON manhole;
CREATE TRIGGER trg_manhole_touch BEFORE UPDATE ON manhole
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS trg_lateral_pipe_touch ON lateral_pipe;
CREATE TRIGGER trg_lateral_pipe_touch BEFORE UPDATE ON lateral_pipe
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- Trigger: setiap baris progress_log memperbarui tahap terkini pada aset
CREATE OR REPLACE FUNCTION apply_progress() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_method text;
BEGIN
    IF NEW.asset_type = 'manhole' THEN
        v_method := 'ALL';
    ELSE
        SELECT method INTO v_method FROM sewer.lateral_pipe WHERE pipe_id = NEW.asset_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Pipa % tidak ditemukan', NEW.asset_id;
        END IF;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM sewer.ref_stage
                    WHERE asset_type = NEW.asset_type
                      AND method = v_method
                      AND stage_code = NEW.stage_code) THEN
        RAISE EXCEPTION 'Tahap % tidak valid untuk % (metode %)',
            NEW.stage_code, NEW.asset_type, v_method;
    END IF;

    IF NEW.asset_type = 'manhole' THEN
        UPDATE sewer.manhole
           SET stage_code  = NEW.stage_code,
               actual_date = CASE WHEN NEW.stage_code = 'selesai' THEN NEW.log_date ELSE actual_date END
         WHERE manhole_id = NEW.asset_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Manhole % tidak ditemukan', NEW.asset_id;
        END IF;
    ELSE
        UPDATE sewer.lateral_pipe
           SET stage_code  = NEW.stage_code,
               actual_date = CASE WHEN NEW.stage_code = 'selesai' THEN NEW.log_date ELSE actual_date END
         WHERE pipe_id = NEW.asset_id;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_progress_apply ON progress_log;
CREATE TRIGGER trg_progress_apply BEFORE INSERT ON progress_log
    FOR EACH ROW EXECUTE FUNCTION apply_progress();

-- A5. View untuk dashboard
CREATE OR REPLACE VIEW v_manhole AS
SELECT m.*,
       s.stage_label,
       COALESCE(s.cum_weight, 0) AS progress_pct
  FROM manhole m
  LEFT JOIN ref_stage s
         ON s.asset_type = 'manhole' AND s.method = 'ALL' AND s.stage_code = m.stage_code;

CREATE OR REPLACE VIEW v_lateral_pipe AS
SELECT p.*,
       s.stage_label,
       COALESCE(s.cum_weight, 0) AS progress_pct
  FROM lateral_pipe p
  LEFT JOIN ref_stage s
         ON s.asset_type = 'lateral_pipe' AND s.method = p.method AND s.stage_code = p.stage_code;

-- Ringkasan pipa per zona / tipe / metode (progres berbobot panjang)
CREATE OR REPLACE VIEW v_pipe_summary AS
SELECT zone, pipe_type, method,
       count(*)                                              AS n_total,
       count(*) FILTER (WHERE stage_code = 'selesai')        AS n_selesai,
       round(sum(length_m)::numeric, 1)                      AS length_plan_m,
       round(sum(length_m * progress_pct / 100)::numeric, 1) AS length_progress_m,
       round(100 * sum(length_m * progress_pct / 100)
                 / NULLIF(sum(length_m), 0), 1)              AS progress_pct
  FROM v_lateral_pipe
 GROUP BY zone, pipe_type, method;

-- Ringkasan manhole per zona
CREATE OR REPLACE VIEW v_manhole_summary AS
SELECT zone,
       count(*)                                       AS n_total,
       count(*) FILTER (WHERE stage_code = 'selesai') AS n_selesai,
       round(avg(progress_pct), 1)                    AS progress_pct
  FROM v_manhole
 GROUP BY zone;

-- Tren harian dari log progres
CREATE OR REPLACE VIEW v_progress_daily AS
SELECT log_date, asset_type,
       count(*)                                       AS n_update,
       count(*) FILTER (WHERE stage_code = 'selesai') AS n_selesai
  FROM progress_log
 GROUP BY log_date, asset_type;


-- =====================================================================
-- BAGIAN B - QA DATA LAMA (jalankan satu per satu, perbaiki di QGIS)
-- =====================================================================

-- B1. Pipa yang manhole hulu ("Text") atau hilirnya tidak ada di tabel manhole
--     (kolom "Text" diasumsikan = manhole hulu; konfirmasi dulu)
SELECT p.fid, p."Text" AS from_mh, p."PIPE_Downstream Manhole" AS to_mh
  FROM staging.lateral_pipe_raw p
  LEFT JOIN staging.manhole_raw a ON a."Manhole" = p."Text"
  LEFT JOIN staging.manhole_raw b ON b."Manhole" = p."PIPE_Downstream Manhole"
 WHERE a."Manhole" IS NULL OR b."Manhole" IS NULL;

-- B2. ID manhole ganda
SELECT "Manhole", count(*) AS n
  FROM staging.manhole_raw
 GROUP BY "Manhole" HAVING count(*) > 1;

-- B3. Baris hampir kosong (sisa digitasi/impor CAD)
SELECT fid, "Manhole", "Type"
  FROM staging.manhole_raw
 WHERE "MANHOLE_Ground Elevation (Z)" IS NULL;

SELECT fid, "Text", "ZONE"
  FROM staging.lateral_pipe_raw
 WHERE "PIPE_L Pipe" IS NULL;

-- B4. Panjang atribut vs panjang geometri (selisih > 0,5 m)
SELECT fid, "Text", "Length_Pipe",
       round(ST_Length(geom)::numeric, 2) AS len_geom
  FROM staging.lateral_pipe_raw
 WHERE abs("Length_Pipe"::numeric - ST_Length(geom)::numeric) > 0.5;

-- B5. Rekap panjang per tipe dan metode (untuk mencocokkan dengan 16,5 km)
SELECT "Pipe_Type", "PIPE_Method",
       count(*)                                  AS n,
       round(sum("Length_Pipe")::numeric, 1)     AS as_to_as_m,
       round(sum("PIPE_L Pipe")::numeric, 1)     AS net_m
  FROM staging.lateral_pipe_raw
 GROUP BY ROLLUP ("Pipe_Type", "PIPE_Method")
 ORDER BY 1, 2;


-- =====================================================================
-- BAGIAN C - MIGRASI (setelah B1-B3 bersih)
-- Asumsi: geometri staging sudah ber-SRID 32749. Jika tidak, ganti
-- ST_Force2D(geom) dengan ST_Transform(ST_Force2D(geom), 32749).
-- =====================================================================

INSERT INTO sewer.manhole (
    manhole_id, manhole_no, mh_type, zone, location_name, existing_pavement,
    road_width_m, diameter_mm, depth_class, shaft,
    ground_elev, invert_elev, depth_m, elev_downstream,
    elev_upstream_1, elev_upstream_2, elev_upstream_3,
    q_design_m3day, velocity_ms, plan_date, actual_date, stage_code, geom)
SELECT
    "Manhole",
    "MANHOLE_No."::integer,
    "Type",
    NULLIF(regexp_replace(COALESCE("MANHOLE_ZONE"::text, ''), '\D', '', 'g'), '')::smallint,
    "MANHOLE_Location",
    "MANHOLE_Existing Pavement",
    "MANHOLE_Width (m)",
    -- "1200 3-4" -> diameter 1200 dan kelas kedalaman "3-4"
    NULLIF(split_part("MANHOLE_Diameter Manhole", ' ', 1), '')::integer,
    NULLIF(trim(substr("MANHOLE_Diameter Manhole",
                       length(split_part("MANHOLE_Diameter Manhole", ' ', 1)) + 1)), ''),
    "MANHOLE_SHAFT",
    "MANHOLE_Ground Elevation (Z)",
    "MANHOLE_Invert Manhole",
    "MANHOLE_Depth",
    "MANHOLE_Elevation Downstream",
    "MANHOLE_Elevation UpStream 1",
    "MANHOLE_Elevation UpStream 2",
    "MANHOLE_Elevation UpStream 3",
    NULLIF("MANHOLE_Qdebit (M3/Day)"::text, '')::numeric,
    "MANHOLE_V (m/dt)",
    "RENCANA_PEKERJAAN"::date,
    "REALISASI PEKERJAAN"::date,
    -- ASUMSI: ada tanggal realisasi = selesai. Sesuaikan bila berbeda.
    CASE WHEN "REALISASI PEKERJAAN" IS NOT NULL THEN 'selesai' ELSE 'belum_mulai' END,
    ST_Force2D(geom)
  FROM staging.manhole_raw
 WHERE "Manhole" IS NOT NULL;

INSERT INTO sewer.lateral_pipe (
    pipe_id, from_mh, to_mh, pipe_type, method, material, diameter_mm, depth_class,
    zone, location_name, existing_pavement, road_width_m,
    length_as_to_as_m, length_net_m,
    up_gl, up_ie, up_depth, lw_gl, lw_ie, lw_depth, drop_m, slope_pct,
    q_design_m3day, v_full_ms, shaft, stage_code, geom)
SELECT
    "Text" || '>' || "PIPE_Downstream Manhole",
    "Text",
    "PIPE_Downstream Manhole",
    "Pipe_Type",
    "PIPE_Method",
    "Pipe_Material",
    "PIPE_D Pipe"::integer,
    NULLIF(trim(substr("PIPE_PIPE CLASS.",
                       length(split_part("PIPE_PIPE CLASS.", ' ', 1)) + 1)), ''),
    NULLIF(regexp_replace(COALESCE("ZONE"::text, ''), '\D', '', 'g'), '')::smallint,
    "PIPE_Location",
    "PIPE_Existing Pavement",
    "PIPE_Width (m)",
    NULLIF("LENGTH_AstoAs"::text, '')::numeric,
    "PIPE_L Pipe",
    "PIPE_Up.GL", "PIPE_Up.IE", "PIPE_Up.Depth",
    "PIPE_Lw.GL", "PIPE_Lw. IE", "PIPE_Lw.Depth",
    "PIPE_Drop",
    "PIPE_Slope",
    NULLIF("PIPE_Q Design"::text, '')::numeric,
    "PIPE_Kec Penuh (m/dt)",
    "PIPE_Shaft",
    'belum_mulai',
    ST_LineMerge(ST_Force2D(geom))
  FROM staging.lateral_pipe_raw
 WHERE "Text" IS NOT NULL
   AND "PIPE_Downstream Manhole" IS NOT NULL;


-- =====================================================================
-- BAGIAN D - PENGECEKAN SETELAH MIGRASI
-- =====================================================================
SELECT (SELECT count(*) FROM sewer.manhole)      AS n_manhole,
       (SELECT count(*) FROM sewer.lateral_pipe) AS n_pipe;

SELECT * FROM sewer.v_pipe_summary    ORDER BY zone, pipe_type, method;
SELECT * FROM sewer.v_manhole_summary ORDER BY zone;

-- Aset dengan stage_code yang tidak terdaftar di ref_stage
SELECT 'manhole' AS asset_type, manhole_id AS asset_id, stage_code
  FROM sewer.manhole m
 WHERE NOT EXISTS (SELECT 1 FROM sewer.ref_stage s
                    WHERE s.asset_type = 'manhole' AND s.method = 'ALL'
                      AND s.stage_code = m.stage_code)
UNION ALL
SELECT 'lateral_pipe', pipe_id, stage_code
  FROM sewer.lateral_pipe p
 WHERE NOT EXISTS (SELECT 1 FROM sewer.ref_stage s
                    WHERE s.asset_type = 'lateral_pipe' AND s.method = p.method
                      AND s.stage_code = p.stage_code);

-- Contoh input progres (ganti ID dengan ID nyata), lalu cek v_pipe_summary:
-- INSERT INTO sewer.progress_log (asset_type, asset_id, stage_code, note, reported_by)
-- VALUES ('manhole', 'MHJ_06_0001', 'galian', 'Galian shaft selesai', 'Pengawas A');
