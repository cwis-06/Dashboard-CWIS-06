-- =====================================================================
-- DIAGNOSA DATABASE (hanya membaca, tidak mengubah apa pun)
-- Dijalankan oleh cek_database.bat. Hasilnya ditulis ke diagnosa_hasil.txt.
-- =====================================================================
\pset pager off

\echo '== 1. Isi ref_stage'
SELECT asset_type, method, stage_order, stage_code, stage_label, cum_weight
  FROM sewer.ref_stage ORDER BY asset_type, method, stage_order;

\echo '== 2. Tahap yang dipakai pipa lateral dan kecocokannya dengan ref_stage'
SELECT p.method, p.stage_code, count(*) AS n,
       EXISTS (SELECT 1 FROM sewer.ref_stage r WHERE r.asset_type = 'lateral_pipe'
                  AND r.method = p.method AND r.stage_code = p.stage_code) AS cocok_metode,
       EXISTS (SELECT 1 FROM sewer.ref_stage r WHERE r.asset_type = 'lateral_pipe'
                  AND r.method = 'ALL' AND r.stage_code = p.stage_code) AS cocok_all
  FROM sewer.lateral_pipe p GROUP BY 1, 2 ORDER BY 1, 2;

\echo '== 3. Tahap yang dipakai manhole'
SELECT stage_code, count(*) FROM sewer.manhole GROUP BY 1 ORDER BY 1;

\echo '== 4. Definisi view v_lateral_pipe'
SELECT pg_get_viewdef('sewer.v_lateral_pipe'::regclass, true);
\echo '== 5. Definisi view v_manhole'
SELECT pg_get_viewdef('sewer.v_manhole'::regclass, true);

\echo '== 6. View yang bergantung ke v_lateral_pipe'
SELECT DISTINCT v.relname
  FROM pg_depend d
  JOIN pg_rewrite r ON r.oid = d.objid
  JOIN pg_class v ON v.oid = r.ev_class
 WHERE d.refobjid = 'sewer.v_lateral_pipe'::regclass AND v.oid <> d.refobjid;

\echo '== 7. Kolom tabel lateral_pipe'
SELECT column_name, data_type FROM information_schema.columns
 WHERE table_schema = 'sewer' AND table_name = 'lateral_pipe' ORDER BY ordinal_position;

\echo '== 8. Trigger di schema sewer dan staging'
SELECT event_object_schema AS sch, event_object_table AS tabel, trigger_name, action_timing,
       string_agg(event_manipulation, ',') AS kejadian
  FROM information_schema.triggers
 WHERE event_object_schema IN ('sewer', 'staging')
 GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3;

\echo '== 9. Fungsi dan prosedur'
SELECT n.nspname AS sch, p.proname, p.prokind
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('sewer', 'staging') ORDER BY 1, 2;

\echo '== 10. Isi fungsi trg_lp'
SELECT pg_get_functiondef('sewer.trg_lp'::regproc);

\echo '== 11. Tabel dan view di schema sewer'
SELECT table_name, table_type FROM information_schema.tables
 WHERE table_schema = 'sewer' ORDER BY 1;

\echo '== 12. Versi'
SELECT version();
SELECT postgis_full_version();
