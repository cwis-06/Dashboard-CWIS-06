-- =====================================================================
-- MIGRASI staging -> sewer (versi final, menggantikan Bagian C
-- di sewerage_webgis_schema.sql)
--
-- Jalankan BERURUTAN, satu langkah per eksekusi (blok demi blok).
-- Jika muncul error 25P02 (transaction is aborted), jalankan ROLLBACK;
-- sendirian, lalu mulai lagi dari langkah 1.
-- =====================================================================


-- ---------------------------------------------------------------------
-- LANGKAH 1. Fungsi bantu (cukup sekali)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION staging.to_num(t text) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
           WHEN replace(trim(t), ',', '.') ~ '^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)$'
           THEN replace(trim(t), ',', '.')::numeric
         END
$$;

CREATE OR REPLACE FUNCTION staging.to_dt(t text) RETURNS date
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
           WHEN trim(t) ~ '^\d{2}/\d{2}/\d{4}$' THEN to_date(trim(t), 'DD/MM/YYYY')
           WHEN trim(t) ~ '^\d{4}-\d{2}-\d{2}'  THEN left(trim(t), 10)::date
         END
$$;


-- ---------------------------------------------------------------------
-- LANGKAH 2. Izinkan kelas pipa Tertiary (aman dijalankan ulang)
-- ---------------------------------------------------------------------
ALTER TABLE sewer.lateral_pipe DROP CONSTRAINT IF EXISTS lateral_pipe_pipe_type_check;
ALTER TABLE sewer.lateral_pipe
  ADD CONSTRAINT lateral_pipe_pipe_type_check
  CHECK (pipe_type IN ('Primary','Secondary','Tertiary'));


-- ---------------------------------------------------------------------
-- LANGKAH 3. Kosongkan tabel tujuan (lewati jika memang masih kosong)
-- ---------------------------------------------------------------------
TRUNCATE sewer.lateral_pipe, sewer.manhole;


-- ---------------------------------------------------------------------
-- LANGKAH 4. INSERT MANHOLE (harus lebih dulu daripada pipa)
-- ---------------------------------------------------------------------
INSERT INTO sewer.manhole (
    manhole_id, manhole_no, mh_type, zone, location_name, existing_pavement,
    road_width_m, diameter_mm, depth_class, shaft,
    ground_elev, invert_elev, depth_m, elev_downstream,
    elev_upstream_1, elev_upstream_2, elev_upstream_3,
    q_design_m3day, velocity_ms, plan_date, actual_date, stage_code, geom)
SELECT
    trim("Manhole"),
    staging.to_num("MANHOLE_No."::text)::integer,
    trim("Type"),
    NULLIF(regexp_replace(COALESCE("MANHOLE_ZONE"::text, ''), '\D', '', 'g'), '')::smallint,
    "MANHOLE_Location",
    "MANHOLE_Existing Pavement",
    staging.to_num("MANHOLE_Width (m)"::text),
    -- "1200 3-4" -> diameter 1200 dan kelas kedalaman "3-4"
    staging.to_num(split_part(trim("MANHOLE_Diameter Manhole"), ' ', 1))::integer,
    NULLIF(trim(substr(trim("MANHOLE_Diameter Manhole"),
                       length(split_part(trim("MANHOLE_Diameter Manhole"), ' ', 1)) + 1)), ''),
    NULLIF(trim("MANHOLE_SHAFT"), ''),
    staging.to_num("MANHOLE_Ground Elevation (Z)"::text),
    staging.to_num("MANHOLE_Invert Manhole"::text),
    staging.to_num("MANHOLE_Depth"::text),
    staging.to_num("MANHOLE_Elevation Downstream"::text),
    staging.to_num("MANHOLE_Elevation UpStream 1"::text),
    staging.to_num("MANHOLE_Elevation UpStream 2"::text),
    staging.to_num("MANHOLE_Elevation UpStream 3"::text),
    staging.to_num("MANHOLE_Qdebit (M3/Day)"::text),
    staging.to_num("MANHOLE_V (m/dt)"::text),
    staging.to_dt("RENCANA_PEKERJAAN"::text),
    staging.to_dt("REALISASI PEKERJAAN"::text),
    -- ASUMSI: ada tanggal realisasi valid = selesai. Sesuaikan bila berbeda.
    CASE WHEN staging.to_dt("REALISASI PEKERJAAN"::text) IS NOT NULL
         THEN 'selesai' ELSE 'belum_mulai' END,
    ST_Force2D(geom)
  FROM staging.manhole_raw
 WHERE NULLIF(trim("Manhole"), '') IS NOT NULL
   AND geom IS NOT NULL;


-- ---------------------------------------------------------------------
-- LANGKAH 5. INSERT PIPA LATERAL
-- ---------------------------------------------------------------------
INSERT INTO sewer.lateral_pipe (
    pipe_id, from_mh, to_mh, pipe_type, method, material, diameter_mm, depth_class,
    zone, location_name, existing_pavement, road_width_m,
    length_as_to_as_m, length_net_m,
    up_gl, up_ie, up_depth, lw_gl, lw_ie, lw_depth, drop_m, slope_pct,
    q_design_m3day, v_full_ms, shaft, stage_code, geom)
SELECT
    trim("Text") || '>' || trim("PIPE_Downstream Manhole"),
    trim("Text"),
    trim("PIPE_Downstream Manhole"),
    NULLIF(trim("Pipe_Type "), ''),          -- ada spasi di belakang nama kolom
    trim("PIPE_Method"),
    "Pipe_Material",
    staging.to_num("PIPE_D Pipe"::text)::integer,
    NULLIF(trim(substr(trim("PIPE_PIPE CLASS."),
                       length(split_part(trim("PIPE_PIPE CLASS."), ' ', 1)) + 1)), ''),
    NULLIF(regexp_replace(COALESCE("ZONE"::text, ''), '\D', '', 'g'), '')::smallint,
    "PIPE_Location",
    "PIPE_Existing Pavement",
    staging.to_num("PIPE_Width (m)"::text),
    staging.to_num("LENGTH_AstoAs"::text),
    staging.to_num("PIPE_L Pipe"::text),
    staging.to_num("PIPE_Up.GL"::text),
    staging.to_num("PIPE_Up.IE"::text),
    staging.to_num("PIPE_Up.Depth"::text),
    staging.to_num("PIPE_Lw.GL"::text),
    staging.to_num("PIPE_Lw. IE"::text),
    staging.to_num("PIPE_Lw.Depth"::text),
    staging.to_num("PIPE_Drop"::text),
    staging.to_num("PIPE_Slope"::text),
    staging.to_num("PIPE_Q Design"::text),
    staging.to_num("PIPE_Kec Penuh (m/dt)"::text),
    NULLIF(trim("PIPE_Shaft"), ''),
    'belum_mulai',
    ST_LineMerge(ST_Force2D(geom))
  FROM staging.lateral_pipe_raw
 WHERE NULLIF(trim("Text"), '') IS NOT NULL
   AND NULLIF(trim("PIPE_Downstream Manhole"), '') IS NOT NULL
   AND geom IS NOT NULL;


-- ---------------------------------------------------------------------
-- LANGKAH 6. Simpan permanen
-- (jika auto-commit aktif, muncul peringatan "no transaction in progress";
--  itu tidak berbahaya)
-- ---------------------------------------------------------------------
COMMIT;


-- ---------------------------------------------------------------------
-- LANGKAH 7. Verifikasi
-- ---------------------------------------------------------------------
SELECT (SELECT count(*) FROM sewer.manhole)      AS n_manhole,
       (SELECT count(*) FROM sewer.lateral_pipe) AS n_pipe;

SELECT pipe_type, method, count(*) AS n,
       round(sum(length_as_to_as_m), 1) AS as_to_as_m,
       round(sum(length_net_m), 1)      AS net_m
  FROM sewer.lateral_pipe
 GROUP BY ROLLUP (pipe_type, method)
 ORDER BY 1, 2;

ANALYZE sewer.ref_stage;
ANALYZE sewer.manhole;
ANALYZE sewer.lateral_pipe;
ANALYZE sewer.progress_log;
