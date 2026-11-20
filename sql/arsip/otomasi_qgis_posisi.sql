-- =====================================================================
-- OTOMASI POSISI: titik digeser di QGIS, garis yang tersambung ikut bergeser
-- Dijalankan SETELAH otomasi_qgis.sql (aman diulang). setup_otomasi.bat
-- menjalankan kedua file ini berurutan.
--
-- Aturan:
--   * Ujung pipa lateral selalu menempel di pusat manhole hulu (from_mh) dan
--     hilir (to_mh). Geser manhole -> ujung pipa ikut, panjang dihitung ulang.
--   * Pipa collecting ikut bila IC atau manhole di ujungnya digeser.
--   * Pipa persil ikut bila HI, IC, atau manhole di ujungnya digeser.
--   * Panjang as-to-as dihitung ulang dari geometri bila garis berubah; panjang
--     bersih ikut bergeser sebesar selisihnya (pengurangan diameter manhole tetap).
--   * Tahap kerja hanya diperiksa saat tahap atau metode diubah, jadi data lama
--     yang tahapnya tidak cocok tidak menghalangi penyimpanan geser titik atau garis.
--   * Untuk memindahkan sebuah pipa, geser manholenya; ujung pipa tidak bisa
--     dilepas dari manhole.
-- =====================================================================

SET search_path = sewer, public;

-- 1. Pipa lateral
CREATE OR REPLACE FUNCTION sewer.trg_lp() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    g geometry; p geometry; newlen numeric;
BEGIN
    IF TG_OP = 'INSERT' AND (NEW.pipe_id IS NULL OR NEW.pipe_id LIKE 'NEW-%') THEN
        NEW.pipe_id := NEW.from_mh || '>' || NEW.to_mh;
    END IF;

    IF TG_OP = 'INSERT' OR NEW.geom IS DISTINCT FROM OLD.geom THEN
        g := ST_LineMerge(ST_Force2D(NEW.geom));
        IF GeometryType(g) <> 'LINESTRING' THEN
            RAISE EXCEPTION 'Garis pipa harus satu rangkaian yang tersambung (bukan beberapa potongan terpisah)';
        END IF;
        SELECT geom INTO p FROM sewer.manhole WHERE manhole_id = NEW.from_mh;
        IF p IS NOT NULL THEN g := ST_SetPoint(g, 0, p); END IF;
        SELECT geom INTO p FROM sewer.manhole WHERE manhole_id = NEW.to_mh;
        IF p IS NOT NULL THEN g := ST_SetPoint(g, ST_NPoints(g) - 1, p); END IF;
        NEW.geom := g;
        newlen := ST_Length(g)::numeric;
        IF TG_OP = 'UPDATE' AND OLD.length_as_to_as_m IS NOT NULL AND NEW.length_net_m IS NOT NULL THEN
            NEW.length_net_m := round(GREATEST(NEW.length_net_m + (newlen - OLD.length_as_to_as_m), 0), 3);
        END IF;
        NEW.length_as_to_as_m := round(newlen, 3);
    END IF;

    IF NEW.length_as_to_as_m IS NULL THEN
        NEW.length_as_to_as_m := round(ST_Length(NEW.geom)::numeric, 3);
    END IF;
    IF NEW.zone IS NULL THEN
        NEW.zone := sewer.zone_of(ST_LineInterpolatePoint(NEW.geom, 0.5));
    END IF;

    IF TG_OP = 'INSERT' OR NEW.stage_code IS DISTINCT FROM OLD.stage_code
                        OR NEW.method     IS DISTINCT FROM OLD.method THEN
        IF NOT EXISTS (SELECT 1 FROM sewer.ref_stage
                        WHERE asset_type = 'lateral_pipe' AND method = NEW.method
                          AND stage_code = NEW.stage_code) THEN
            RAISE EXCEPTION 'Tahap % tidak sah untuk pipa % (metode %). Pilihan: %',
                NEW.stage_code, NEW.pipe_id, NEW.method,
                (SELECT string_agg(stage_code, ', ' ORDER BY stage_order)
                   FROM sewer.ref_stage WHERE asset_type = 'lateral_pipe' AND method = NEW.method);
        END IF;
    END IF;
    RETURN NEW;
END $$;

-- 2. Manhole: validasi tahap hanya saat tahap berubah
CREATE OR REPLACE FUNCTION sewer.trg_mh() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.geom := ST_Force2D(NEW.geom);
    IF NEW.zone IS NULL THEN
        NEW.zone := sewer.zone_of(NEW.geom);
    END IF;
    IF TG_OP = 'INSERT' OR NEW.stage_code IS DISTINCT FROM OLD.stage_code THEN
        IF NOT EXISTS (SELECT 1 FROM sewer.ref_stage
                        WHERE asset_type = 'manhole' AND method = 'ALL'
                          AND stage_code = NEW.stage_code) THEN
            RAISE EXCEPTION 'Tahap % tidak sah untuk manhole %. Pilihan: %',
                NEW.stage_code, NEW.manhole_id,
                (SELECT string_agg(stage_code, ', ' ORDER BY stage_order)
                   FROM sewer.ref_stage WHERE asset_type = 'manhole' AND method = 'ALL');
        END IF;
    END IF;
    RETURN NEW;
END $$;

-- 3. Manhole digeser -> pipa lateral dan collecting yang tersambung ikut
CREATE OR REPLACE FUNCTION sewer.trg_mh_follow() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE sewer.lateral_pipe SET geom = ST_SetPoint(geom, 0, NEW.geom)
     WHERE from_mh = NEW.manhole_id;
    UPDATE sewer.lateral_pipe SET geom = ST_SetPoint(geom, ST_NPoints(geom) - 1, NEW.geom)
     WHERE to_mh = NEW.manhole_id;
    UPDATE sewer.collecting_pipe SET geom = ST_SetPoint(geom, 0, NEW.geom)
     WHERE from_type = 'MH' AND from_id = NEW.manhole_id;
    UPDATE sewer.collecting_pipe SET geom = ST_SetPoint(geom, ST_NPoints(geom) - 1, NEW.geom)
     WHERE to_type = 'MH' AND to_id = NEW.manhole_id;
    UPDATE sewer.persil_pipe SET geom = ST_SetPoint(geom, 0, NEW.geom)
     WHERE from_type = 'MH' AND from_id = NEW.manhole_id;
    UPDATE sewer.persil_pipe SET geom = ST_SetPoint(geom, ST_NPoints(geom) - 1, NEW.geom)
     WHERE to_type = 'MH' AND to_id = NEW.manhole_id;
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_mh_follow ON sewer.manhole;
CREATE TRIGGER trg_mh_follow AFTER UPDATE OF geom ON sewer.manhole
    FOR EACH ROW WHEN (OLD.geom IS DISTINCT FROM NEW.geom)
    EXECUTE FUNCTION sewer.trg_mh_follow();

-- 4. Inspection chamber digeser -> pipa collecting dan persil yang tersambung ikut
CREATE OR REPLACE FUNCTION sewer.trg_ic_follow() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE sewer.collecting_pipe SET geom = ST_SetPoint(geom, 0, NEW.geom)
     WHERE from_type = 'IC' AND from_id = NEW.ic_id;
    UPDATE sewer.collecting_pipe SET geom = ST_SetPoint(geom, ST_NPoints(geom) - 1, NEW.geom)
     WHERE to_type = 'IC' AND to_id = NEW.ic_id;
    UPDATE sewer.persil_pipe SET geom = ST_SetPoint(geom, 0, NEW.geom)
     WHERE from_type = 'IC' AND from_id = NEW.ic_id;
    UPDATE sewer.persil_pipe SET geom = ST_SetPoint(geom, ST_NPoints(geom) - 1, NEW.geom)
     WHERE to_type = 'IC' AND to_id = NEW.ic_id;
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_ic_follow ON sewer.inspection_chamber;
CREATE TRIGGER trg_ic_follow AFTER UPDATE OF geom ON sewer.inspection_chamber
    FOR EACH ROW WHEN (OLD.geom IS DISTINCT FROM NEW.geom)
    EXECUTE FUNCTION sewer.trg_ic_follow();

-- 5. House inlet digeser -> pipa persil yang tersambung ikut
CREATE OR REPLACE FUNCTION sewer.trg_hi_follow() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE sewer.persil_pipe SET geom = ST_SetPoint(geom, 0, NEW.geom)
     WHERE from_type = 'HI' AND from_id = NEW.hi_id;
    UPDATE sewer.persil_pipe SET geom = ST_SetPoint(geom, ST_NPoints(geom) - 1, NEW.geom)
     WHERE to_type = 'HI' AND to_id = NEW.hi_id;
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_hi_follow ON sewer.house_inlet;
CREATE TRIGGER trg_hi_follow AFTER UPDATE OF geom ON sewer.house_inlet
    FOR EACH ROW WHEN (OLD.geom IS DISTINCT FROM NEW.geom)
    EXECUTE FUNCTION sewer.trg_hi_follow();

-- 6. Pipa lateral berubah bentuk -> ujung pipa collecting dan persil yang menempel
--    di badan pipa itu ikut, pada posisi relatif yang sama sepanjang garis
CREATE OR REPLACE FUNCTION sewer.trg_lp_follow() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE sewer.collecting_pipe c
       SET geom = ST_SetPoint(c.geom, 0,
                  ST_LineInterpolatePoint(NEW.geom, ST_LineLocatePoint(OLD.geom, ST_StartPoint(c.geom))))
     WHERE c.from_type = 'LP' AND c.from_id = OLD.pipe_id;
    UPDATE sewer.collecting_pipe c
       SET geom = ST_SetPoint(c.geom, ST_NPoints(c.geom) - 1,
                  ST_LineInterpolatePoint(NEW.geom, ST_LineLocatePoint(OLD.geom, ST_EndPoint(c.geom))))
     WHERE c.to_type = 'LP' AND c.to_id = OLD.pipe_id;
    UPDATE sewer.persil_pipe c
       SET geom = ST_SetPoint(c.geom, 0,
                  ST_LineInterpolatePoint(NEW.geom, ST_LineLocatePoint(OLD.geom, ST_StartPoint(c.geom))))
     WHERE c.from_type = 'LP' AND c.from_id = OLD.pipe_id;
    UPDATE sewer.persil_pipe c
       SET geom = ST_SetPoint(c.geom, ST_NPoints(c.geom) - 1,
                  ST_LineInterpolatePoint(NEW.geom, ST_LineLocatePoint(OLD.geom, ST_EndPoint(c.geom))))
     WHERE c.to_type = 'LP' AND c.to_id = OLD.pipe_id;
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_lp_follow ON sewer.lateral_pipe;
CREATE TRIGGER trg_lp_follow AFTER UPDATE OF geom ON sewer.lateral_pipe
    FOR EACH ROW WHEN (OLD.geom IS DISTINCT FROM NEW.geom)
    EXECUTE FUNCTION sewer.trg_lp_follow();
