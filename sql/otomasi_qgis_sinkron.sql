-- =====================================================================
-- OTOMASI SINKRON: isian di staging.manhole_raw langsung masuk ke sewer
-- Dijalankan setelah progress_manhole.sql dan otomasi_qgis.sql (aman diulang).
--
-- Bila Anda mengisi progres lewat layer manhole_raw di QGIS, saat Save Edits:
--   * kolom STATUS, RENCANA_PEKERJAAN, REALISASI PEKERJAAN
--       -> sewer.manhole.stage_code, plan_date, actual_date (tanggal mulai kerja)
--   * kolom progress_pct dan work_stage
--       -> sewer.manhole_work (baris dibuat, diubah, atau dihapus bila dikosongkan)
-- Sinkron hanya jalan untuk kolom yang BERUBAH, jadi mengedit kolom lain di
-- manhole_raw (atau mengedit langsung tabel sewer.manhole) tidak saling menimpa.
-- =====================================================================

-- 1. STATUS dan tanggal -> sewer.manhole
CREATE OR REPLACE FUNCTION staging.trg_manhole_raw_status() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_id    text := trim(NEW."Manhole");
    v_stage text;
BEGIN
    IF v_id IS NULL OR v_id = '' THEN
        RETURN NEW;
    END IF;
    v_stage := CASE
        WHEN upper(regexp_replace(trim(NEW."STATUS"::text), '[\s_]+', '-', 'g')) IN ('ON-GOING','ONGOING') THEN 'on_going'
        WHEN upper(trim(NEW."STATUS"::text)) IN ('SELESAI','FINISH','DONE','COMPLETE')                     THEN 'selesai'
        ELSE 'belum_mulai'
    END;
    UPDATE sewer.manhole
       SET stage_code  = v_stage,
           plan_date   = staging.to_dt(NEW."RENCANA_PEKERJAAN"::text),
           actual_date = staging.to_dt(NEW."REALISASI PEKERJAAN"::text)
     WHERE manhole_id = v_id;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_manhole_raw_status ON staging.manhole_raw;
CREATE TRIGGER trg_manhole_raw_status
    AFTER INSERT OR UPDATE OF "STATUS", "RENCANA_PEKERJAAN", "REALISASI PEKERJAAN"
    ON staging.manhole_raw
    FOR EACH ROW EXECUTE FUNCTION staging.trg_manhole_raw_status();

-- 2. progress_pct dan work_stage -> sewer.manhole_work
CREATE OR REPLACE FUNCTION staging.trg_manhole_raw_progress() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_id text := trim(NEW."Manhole");
    v_ws text := NULLIF(trim(NEW.work_stage), '');
BEGIN
    IF v_id IS NULL OR v_id = '' OR NOT EXISTS (SELECT 1 FROM sewer.manhole WHERE manhole_id = v_id) THEN
        RETURN NEW;
    END IF;
    IF COALESCE(NEW.progress_pct, 0) > 0 OR v_ws IS NOT NULL THEN
        INSERT INTO sewer.manhole_work (manhole_id, progress_pct, work_stage)
        VALUES (v_id, NEW.progress_pct, v_ws)
        ON CONFLICT (manhole_id) DO UPDATE
           SET progress_pct = EXCLUDED.progress_pct,
               work_stage   = EXCLUDED.work_stage;
    ELSE
        DELETE FROM sewer.manhole_work WHERE manhole_id = v_id;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_manhole_raw_progress ON staging.manhole_raw;
CREATE TRIGGER trg_manhole_raw_progress
    AFTER INSERT OR UPDATE OF progress_pct, work_stage
    ON staging.manhole_raw
    FOR EACH ROW EXECUTE FUNCTION staging.trg_manhole_raw_progress();
