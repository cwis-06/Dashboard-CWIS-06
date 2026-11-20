-- =====================================================================
-- OTOMASI MONITOR: perbaikan view pipa, pemeriksaan kualitas data (QA),
-- dan riwayat progres harian.
-- Dijalankan oleh setup_otomasi.bat (aman diulang). Isinya sama dengan yang
-- berlaku di database per 20 November 2026 (lihat sql/skema_db_aktual.sql).
--
--   * v_lateral_pipe   : tahap pipa dicocokkan ke ref_stage dengan metode pipa
--                        (Open Trench / Jacking) ATAU metode 'ALL'. Sebelumnya hanya
--                        metode persis, sehingga stage_label kosong bila ref_stage
--                        memakai 'ALL'.
--   * sewer.qa_report(): daftar masalah data. Level ERROR menghentikan
--                        update_dashboard.bat sebelum data diunggah.
--   * sewer.progress_snapshot + sewer.snapshot_progress(): satu baris per zona
--                        per hari. update_dashboard.bat memanggilnya setiap kali
--                        jalan dan mengekspornya ke data/progress_history.csv.
-- =====================================================================

SET search_path = sewer, public;

-- 1. View pipa lateral (kolom dan urutannya sama seperti sebelumnya)
CREATE OR REPLACE VIEW sewer.v_lateral_pipe AS
SELECT p.*,
       s.stage_label,
       COALESCE(s.cum_weight, 0) AS progress_pct
  FROM sewer.lateral_pipe p
  LEFT JOIN LATERAL (
        SELECT r.stage_label, r.cum_weight
          FROM sewer.ref_stage r
         WHERE r.asset_type = 'lateral_pipe'
           AND r.stage_code = p.stage_code
           AND r.method IN (p.method, 'ALL')
         ORDER BY (r.method = p.method) DESC
         LIMIT 1) s ON true;

-- 2. Pemeriksaan kualitas data
--    ERROR      : data salah, unggahan dihentikan.
--    PERINGATAN : perlu dirapikan, unggahan tetap jalan.
--    INFO       : kelengkapan data untuk monitoring (mis. tanggal rencana).
CREATE OR REPLACE FUNCTION sewer.qa_report()
RETURNS TABLE (level text, check_name text, n bigint, contoh text)
LANGUAGE sql STABLE AS $$
WITH
e1 AS (SELECT p.pipe_id AS id FROM sewer.lateral_pipe p
        WHERE NOT EXISTS (SELECT 1 FROM sewer.manhole m WHERE m.manhole_id = p.from_mh)
           OR NOT EXISTS (SELECT 1 FROM sewer.manhole m WHERE m.manhole_id = p.to_mh)),
e2 AS (SELECT p.pipe_id AS id FROM sewer.lateral_pipe p
        WHERE NOT EXISTS (SELECT 1 FROM sewer.ref_stage r
                           WHERE r.asset_type = 'lateral_pipe' AND r.stage_code = p.stage_code
                             AND r.method IN (p.method, 'ALL'))),
e3 AS (SELECT m.manhole_id AS id FROM sewer.manhole m
        WHERE NOT EXISTS (SELECT 1 FROM sewer.ref_stage r
                           WHERE r.asset_type = 'manhole' AND r.method = 'ALL'
                             AND r.stage_code = m.stage_code)),
e4 AS (SELECT pipe_id AS id FROM sewer.lateral_pipe WHERE geom IS NULL OR ST_IsEmpty(geom)
       UNION ALL
       SELECT manhole_id FROM sewer.manhole WHERE geom IS NULL OR ST_IsEmpty(geom)),
w1 AS (SELECT pipe_id AS id FROM sewer.lateral_pipe WHERE actual_date > current_date
       UNION ALL
       SELECT manhole_id FROM sewer.manhole WHERE actual_date > current_date),
w2 AS (SELECT pipe_id AS id FROM sewer.lateral_pipe
        WHERE stage_code IS DISTINCT FROM 'belum_mulai' AND actual_date IS NULL
       UNION ALL
       SELECT manhole_id FROM sewer.manhole
        WHERE stage_code IS DISTINCT FROM 'belum_mulai' AND actual_date IS NULL
          AND NOT COALESCE(is_reference, false)),
w3 AS (SELECT cp_id AS id FROM sewer.collecting_pipe WHERE NOT COALESCE(snapped, false)),
w4 AS (SELECT ic_id AS id FROM sewer.inspection_chamber WHERE ic_id LIKE '%TMP%'),
i1 AS (SELECT pipe_id AS id FROM sewer.lateral_pipe WHERE plan_date IS NULL),
i2 AS (SELECT manhole_id AS id FROM sewer.manhole
        WHERE plan_date IS NULL AND NOT COALESCE(is_reference, false))
SELECT 'ERROR', 'Pipa lateral: manhole hulu/hilir tidak ada di tabel manhole',
       (SELECT count(*) FROM e1), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM e1)
UNION ALL
SELECT 'ERROR', 'Pipa lateral: stage_code tidak terdaftar di ref_stage',
       (SELECT count(*) FROM e2), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM e2)
UNION ALL
SELECT 'ERROR', 'Manhole: stage_code tidak terdaftar di ref_stage',
       (SELECT count(*) FROM e3), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM e3)
UNION ALL
SELECT 'ERROR', 'Pipa atau manhole tanpa geometri',
       (SELECT count(*) FROM e4), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM e4)
UNION ALL
SELECT 'PERINGATAN', 'Tanggal aktual di masa depan',
       (SELECT count(*) FROM w1), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM w1)
UNION ALL
SELECT 'PERINGATAN', 'Sudah ada tahap kerja tetapi actual_date kosong',
       (SELECT count(*) FROM w2), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM w2)
UNION ALL
SELECT 'PERINGATAN', 'Pipa collecting belum tersambung (snapped = false)',
       (SELECT count(*) FROM w3), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM w3)
UNION ALL
SELECT 'PERINGATAN', 'Inspection chamber masih memakai ID sementara (TMP)',
       (SELECT count(*) FROM w4), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM w4)
UNION ALL
SELECT 'INFO', 'Pipa lateral tanpa plan_date (jadwal rencana belum lengkap)',
       (SELECT count(*) FROM i1), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM i1)
UNION ALL
SELECT 'INFO', 'Manhole tanpa plan_date',
       (SELECT count(*) FROM i2), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM i2)
$$;

-- 3. Riwayat progres harian per zona (baris zona 'SEMUA' = total paket)
CREATE TABLE IF NOT EXISTS sewer.progress_snapshot (
    snap_date    date         NOT NULL,
    zone         text         NOT NULL,
    pipe_n       integer,
    pipe_len_m   numeric(12,2),
    pipe_done_m  numeric(12,2),
    pipe_pct     numeric(6,2),
    pipe_selesai integer,
    mh_n         integer,
    mh_selesai   integer,
    mh_pct       numeric(6,2),
    updated_at   timestamptz  NOT NULL DEFAULT now(),
    PRIMARY KEY (snap_date, zone)
);
COMMENT ON TABLE sewer.progress_snapshot IS
    'Satu baris per zona per hari, diisi sewer.snapshot_progress() dari update_dashboard.bat. Jalan berulang di hari yang sama menimpa baris hari itu.';

CREATE OR REPLACE PROCEDURE sewer.snapshot_progress() LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO sewer.progress_snapshot AS t
           (snap_date, zone, pipe_n, pipe_len_m, pipe_done_m, pipe_pct, pipe_selesai,
            mh_n, mh_selesai, mh_pct)
    WITH pz AS (
        SELECT COALESCE(zone::text, '-') AS z,
               COALESCE(length_m, 0)::numeric AS l,
               COALESCE(progress_pct, 0)::numeric AS pc
          FROM sewer.v_lateral_pipe),
    p AS (
        SELECT z, count(*) AS n, sum(l) AS len, sum(l * pc / 100) AS done,
               count(*) FILTER (WHERE pc >= 100) AS sel
          FROM pz GROUP BY z
        UNION ALL
        SELECT 'SEMUA', count(*), sum(l), sum(l * pc / 100), count(*) FILTER (WHERE pc >= 100)
          FROM pz),
    mz AS (
        SELECT COALESCE(zone::text, '-') AS z, COALESCE(progress_pct, 0)::numeric AS pc
          FROM sewer.v_manhole
         WHERE NOT COALESCE(is_reference, false)),
    m AS (
        SELECT z, count(*) AS n, count(*) FILTER (WHERE pc >= 100) AS sel, avg(pc) AS pct
          FROM mz GROUP BY z
        UNION ALL
        SELECT 'SEMUA', count(*), count(*) FILTER (WHERE pc >= 100), avg(pc)
          FROM mz)
    SELECT current_date, COALESCE(p.z, m.z),
           COALESCE(p.n, 0), round(COALESCE(p.len, 0), 2), round(COALESCE(p.done, 0), 2),
           round(100 * p.done / NULLIF(p.len, 0), 2), COALESCE(p.sel, 0),
           COALESCE(m.n, 0), COALESCE(m.sel, 0), round(m.pct, 2)
      FROM p FULL JOIN m ON m.z = p.z
    ON CONFLICT (snap_date, zone) DO UPDATE
       SET pipe_n = EXCLUDED.pipe_n, pipe_len_m = EXCLUDED.pipe_len_m,
           pipe_done_m = EXCLUDED.pipe_done_m, pipe_pct = EXCLUDED.pipe_pct,
           pipe_selesai = EXCLUDED.pipe_selesai, mh_n = EXCLUDED.mh_n,
           mh_selesai = EXCLUDED.mh_selesai, mh_pct = EXCLUDED.mh_pct,
           updated_at = now();
END $$;
