--
-- PostgreSQL database dump
--

-- Dumped from database version 15.2
-- Dumped by pg_dump version 15.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: sewer; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA sewer;


--
-- Name: staging; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA staging;


--
-- Name: apply_progress(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.apply_progress() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: hapus_manhole(text, boolean); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.hapus_manhole(p_id text, p_hapus_pipa boolean DEFAULT false) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE n integer := 0;
BEGIN
    IF p_hapus_pipa THEN
        DELETE FROM sewer.lateral_pipe WHERE from_mh = p_id OR to_mh = p_id;
        GET DIAGNOSTICS n = ROW_COUNT;
    END IF;
    DELETE FROM sewer.manhole WHERE manhole_id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Manhole % tidak ditemukan', p_id;
    END IF;
    RETURN format('Manhole %s dihapus; %s pipa lateral ikut dihapus', p_id, n);
END $$;


--
-- Name: qa_report(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.qa_report() RETURNS TABLE(level text, check_name text, n bigint, contoh text)
    LANGUAGE sql STABLE
    AS $$
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
SELECT 'INFO', 'Pipa lateral tanpa plan_date (kurva S belum bisa dibuat)',
       (SELECT count(*) FROM i1), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM i1)
UNION ALL
SELECT 'INFO', 'Manhole tanpa plan_date',
       (SELECT count(*) FROM i2), (SELECT array_to_string((array_agg(id ORDER BY id))[1:5], ', ') FROM i2)
$$;


--
-- Name: refresh_all(); Type: PROCEDURE; Schema: sewer; Owner: -
--

CREATE PROCEDURE sewer.refresh_all()
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE sewer.house_inlet        SET hi_code = hi_code;
    UPDATE sewer.inspection_chamber SET ic_type = ic_type;
    UPDATE sewer.collecting_pipe    SET cp_id   = cp_id;
    UPDATE sewer.persil_pipe        SET pp_id   = pp_id;
END $$;


--
-- Name: rw_of(public.geometry); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.rw_of(g public.geometry) RETURNS text
    LANGUAGE sql STABLE
    AS $$ SELECT rw_label FROM sewer.rw_boundary WHERE ST_Intersects(geom, g) ORDER BY rw_label LIMIT 1 $$;


--
-- Name: snapshot_progress(); Type: PROCEDURE; Schema: sewer; Owner: -
--

CREATE PROCEDURE sewer.snapshot_progress()
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: sync_from_staging(); Type: PROCEDURE; Schema: sewer; Owner: -
--

CREATE PROCEDURE sewer.sync_from_staging()
    LANGUAGE plpgsql
    AS $_$
DECLARE
  mh_cols text[] := ARRAY['manhole_no','mh_type','zone','location_name','existing_pavement',
    'road_width_m','diameter_mm','depth_class','shaft','ground_elev','invert_elev','depth_m',
    'elev_downstream','elev_upstream_1','elev_upstream_2','elev_upstream_3','q_design_m3day',
    'velocity_ms','plan_date','actual_date','stage_code','geom'];
  pp_cols text[] := ARRAY['from_mh','to_mh','pipe_type','method','material','diameter_mm',
    'depth_class','zone','location_name','existing_pavement','road_width_m','length_as_to_as_m',
    'length_net_m','up_gl','up_ie','up_depth','lw_gl','lw_ie','lw_depth','drop_m','slope_pct',
    'q_design_m3day','v_full_ms','shaft','geom'];
  c_set text; c_l text; c_r text; c_list text;
  mh_ins int; mh_upd int; pp_ins int; pp_upd int; wk_chg int := 0; n int;
BEGIN
  ---------------------------------------------------------------- manhole
  DROP TABLE IF EXISTS _mh;
  CREATE TEMP TABLE _mh ON COMMIT DROP AS SELECT * FROM sewer.manhole WITH NO DATA;

  INSERT INTO _mh (manhole_id, manhole_no, mh_type, zone, location_name, existing_pavement,
      road_width_m, diameter_mm, depth_class, shaft, ground_elev, invert_elev, depth_m,
      elev_downstream, elev_upstream_1, elev_upstream_2, elev_upstream_3, q_design_m3day,
      velocity_ms, plan_date, actual_date, stage_code, geom)
  SELECT DISTINCT ON (trim("Manhole"))
      trim("Manhole"),
      staging.to_num("MANHOLE_No."::text)::integer,
      trim("Type"),
      NULLIF(regexp_replace(COALESCE("MANHOLE_ZONE"::text, ''), '\D', '', 'g'), '')::smallint,
      "MANHOLE_Location",
      "MANHOLE_Existing Pavement",
      staging.to_num("MANHOLE_Width (m)"::text),
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
      CASE
        WHEN upper(regexp_replace(trim("STATUS"::text), '[\s_]+', '-', 'g')) IN ('ON-GOING','ONGOING') THEN 'on_going'
        WHEN upper(trim("STATUS"::text)) IN ('SELESAI','FINISH','FINISHED','DONE','COMPLETE','COMPLETED') THEN 'selesai'
        ELSE 'belum_mulai'
      END,
      ST_Force2D(geom)
    FROM staging.manhole_raw
   WHERE NULLIF(trim("Manhole"), '') IS NOT NULL AND geom IS NOT NULL
   ORDER BY trim("Manhole"), fid DESC;

  SELECT string_agg(format('%1$I = s.%1$I', c), ', '), string_agg('m.' || quote_ident(c), ', '),
         string_agg('s.' || quote_ident(c), ', '),     string_agg(quote_ident(c), ', ')
    INTO c_set, c_l, c_r, c_list
    FROM unnest(mh_cols) AS c;

  EXECUTE format('UPDATE sewer.manhole m SET %s FROM _mh s
                   WHERE m.manhole_id = s.manhole_id AND (%s) IS DISTINCT FROM (%s)', c_set, c_l, c_r);
  GET DIAGNOSTICS mh_upd = ROW_COUNT;

  EXECUTE format('INSERT INTO sewer.manhole (manhole_id, %s)
                  SELECT s.manhole_id, %s FROM _mh s
                   WHERE NOT EXISTS (SELECT 1 FROM sewer.manhole m WHERE m.manhole_id = s.manhole_id)',
                 c_list, c_r);
  GET DIAGNOSTICS mh_ins = ROW_COUNT;

  ---------------------------------------------- progres manual manhole
  INSERT INTO sewer.manhole_work (manhole_id, progress_pct, work_stage)
  SELECT DISTINCT ON (trim(r."Manhole")) trim(r."Manhole"), r.progress_pct, NULLIF(trim(r.work_stage), '')
    FROM staging.manhole_raw r
    JOIN sewer.manhole m ON m.manhole_id = trim(r."Manhole")
   WHERE r.progress_pct > 0 OR NULLIF(trim(r.work_stage), '') IS NOT NULL
   ORDER BY trim(r."Manhole"), r.fid DESC
  ON CONFLICT (manhole_id) DO UPDATE
     SET progress_pct = EXCLUDED.progress_pct, work_stage = EXCLUDED.work_stage
   WHERE (sewer.manhole_work.progress_pct, sewer.manhole_work.work_stage)
         IS DISTINCT FROM (EXCLUDED.progress_pct, EXCLUDED.work_stage);
  GET DIAGNOSTICS n = ROW_COUNT;  wk_chg := wk_chg + n;

  -- raw dikosongkan (0 dan tanpa pekerjaan) -> hapus isian manual, kembali ke progres tahap
  DELETE FROM sewer.manhole_work w
   WHERE w.manhole_id IN (SELECT trim("Manhole") FROM staging.manhole_raw WHERE "Manhole" IS NOT NULL)
     AND w.manhole_id NOT IN (SELECT trim("Manhole") FROM staging.manhole_raw
                               WHERE "Manhole" IS NOT NULL
                                 AND (progress_pct > 0 OR NULLIF(trim(work_stage), '') IS NOT NULL));
  GET DIAGNOSTICS n = ROW_COUNT;  wk_chg := wk_chg + n;

  ------------------------------------------------------- pipa lateral
  DROP TABLE IF EXISTS _pp;
  CREATE TEMP TABLE _pp ON COMMIT DROP AS SELECT * FROM sewer.lateral_pipe WITH NO DATA;

  INSERT INTO _pp (pipe_id, from_mh, to_mh, pipe_type, method, material, diameter_mm, depth_class,
      zone, location_name, existing_pavement, road_width_m, length_as_to_as_m, length_net_m,
      up_gl, up_ie, up_depth, lw_gl, lw_ie, lw_depth, drop_m, slope_pct,
      q_design_m3day, v_full_ms, shaft, geom)
  SELECT DISTINCT ON (trim(r."Text") || '>' || trim(r."PIPE_Downstream Manhole"))
      trim(r."Text") || '>' || trim(r."PIPE_Downstream Manhole"),
      trim(r."Text"),
      trim(r."PIPE_Downstream Manhole"),
      NULLIF(trim(r."Pipe_Type "), ''),
      trim(r."PIPE_Method"),
      r."Pipe_Material",
      staging.to_num(r."PIPE_D Pipe"::text)::integer,
      NULLIF(trim(substr(trim(r."PIPE_PIPE CLASS."),
                         length(split_part(trim(r."PIPE_PIPE CLASS."), ' ', 1)) + 1)), ''),
      NULLIF(regexp_replace(COALESCE(r."ZONE"::text, ''), '\D', '', 'g'), '')::smallint,
      r."PIPE_Location",
      r."PIPE_Existing Pavement",
      staging.to_num(r."PIPE_Width (m)"::text),
      staging.to_num(r."LENGTH_AstoAs"::text),
      staging.to_num(r."PIPE_L Pipe"::text),
      staging.to_num(r."PIPE_Up.GL"::text),
      staging.to_num(r."PIPE_Up.IE"::text),
      staging.to_num(r."PIPE_Up.Depth"::text),
      staging.to_num(r."PIPE_Lw.GL"::text),
      staging.to_num(r."PIPE_Lw. IE"::text),
      staging.to_num(r."PIPE_Lw.Depth"::text),
      staging.to_num(r."PIPE_Drop"::text),
      staging.to_num(r."PIPE_Slope"::text),
      staging.to_num(r."PIPE_Q Design"::text),
      staging.to_num(r."PIPE_Kec Penuh (m/dt)"::text),
      NULLIF(trim(r."PIPE_Shaft"), ''),
      ST_LineMerge(ST_Force2D(r.geom))
    FROM staging.lateral_pipe_raw r
   WHERE NULLIF(trim(r."Text"), '') IS NOT NULL
     AND NULLIF(trim(r."PIPE_Downstream Manhole"), '') IS NOT NULL
     AND r.geom IS NOT NULL
     AND EXISTS (SELECT 1 FROM sewer.manhole a WHERE a.manhole_id = trim(r."Text"))
     AND EXISTS (SELECT 1 FROM sewer.manhole b WHERE b.manhole_id = trim(r."PIPE_Downstream Manhole"))
   ORDER BY trim(r."Text") || '>' || trim(r."PIPE_Downstream Manhole"), r.fid DESC;

  SELECT string_agg(format('%1$I = s.%1$I', c), ', '), string_agg('m.' || quote_ident(c), ', '),
         string_agg('s.' || quote_ident(c), ', '),     string_agg(quote_ident(c), ', ')
    INTO c_set, c_l, c_r, c_list
    FROM unnest(pp_cols) AS c;

  EXECUTE format('UPDATE sewer.lateral_pipe m SET %s FROM _pp s
                   WHERE m.pipe_id = s.pipe_id AND (%s) IS DISTINCT FROM (%s)', c_set, c_l, c_r);
  GET DIAGNOSTICS pp_upd = ROW_COUNT;

  EXECUTE format('INSERT INTO sewer.lateral_pipe (pipe_id, %s)
                  SELECT s.pipe_id, %s FROM _pp s
                   WHERE NOT EXISTS (SELECT 1 FROM sewer.lateral_pipe m WHERE m.pipe_id = s.pipe_id)',
                 c_list, c_r);
  GET DIAGNOSTICS pp_ins = ROW_COUNT;

  RAISE NOTICE 'Sinkron selesai. Manhole: % baru, % diubah. Pipa: % baru, % diubah. Progres manual berubah: %',
               mh_ins, mh_upd, pp_ins, pp_upd, wk_chg;
END
$_$;


--
-- Name: terapkan_urutan_zona2(smallint); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.terapkan_urutan_zona2(p_alt smallint) RETURNS text
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: touch_manhole_work(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.touch_manhole_work() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;


--
-- Name: touch_updated_at(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


--
-- Name: trg_hi(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.trg_hi() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE c text;
BEGIN
    c := upper(trim(NEW.hi_code));
    IF c IS NULL OR c NOT IN ('HIP', 'HI', 'SR') THEN
        RAISE EXCEPTION 'Kode house inlet harus HIP, HI, atau SR (diisi: %)', NEW.hi_code;
    END IF;
    NEW.hi_code         := c;
    NEW.geom            := ST_Force2D(NEW.geom);
    NEW.hi_status       := CASE WHEN c = 'HIP' THEN 'potensi' ELSE 'terkonfirmasi' END;
    NEW.hi_kategori     := CASE c WHEN 'SR' THEN 'SR, disetujui dengan pipa dalam rumah'
                                  WHEN 'HI' THEN 'HI, disetujui tanpa pipa dalam rumah'
                                  ELSE 'Potensi, belum disurvey' END;
    NEW.has_inside_pipe := (c = 'SR');
    NEW.in_scope        := c IN ('HI', 'SR');
    NEW.x   := round(ST_X(NEW.geom)::numeric, 3);
    NEW.y   := round(ST_Y(NEW.geom)::numeric, 3);
    NEW.lon := round(ST_X(ST_Transform(NEW.geom, 4326))::numeric, 7);
    NEW.lat := round(ST_Y(ST_Transform(NEW.geom, 4326))::numeric, 7);
    NEW.coord_ok := true;
    NEW.zone_no  := sewer.zone_of(NEW.geom);
    NEW.rw_label := sewer.rw_of(NEW.geom);
    IF TG_OP = 'UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;


--
-- Name: trg_hi_follow(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.trg_hi_follow() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE sewer.persil_pipe SET geom = ST_SetPoint(geom, 0, NEW.geom)
     WHERE from_type = 'HI' AND from_id = NEW.hi_id;
    UPDATE sewer.persil_pipe SET geom = ST_SetPoint(geom, ST_NPoints(geom) - 1, NEW.geom)
     WHERE to_type = 'HI' AND to_id = NEW.hi_id;
    RETURN NULL;
END $$;


--
-- Name: trg_ic(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.trg_ic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.ic_type := COALESCE(NULLIF(trim(NEW.ic_type), ''), 'IC');
    NEW.geom := ST_Force2D(NEW.geom);
    NEW.x   := round(ST_X(NEW.geom)::numeric, 3);
    NEW.y   := round(ST_Y(NEW.geom)::numeric, 3);
    NEW.lon := round(ST_X(ST_Transform(NEW.geom, 4326))::numeric, 7);
    NEW.lat := round(ST_Y(ST_Transform(NEW.geom, 4326))::numeric, 7);
    NEW.coord_ok := true;
    NEW.zone_no  := sewer.zone_of(NEW.geom);
    NEW.rw_label := sewer.rw_of(NEW.geom);
    IF TG_OP = 'UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;


--
-- Name: trg_ic_follow(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.trg_ic_follow() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: trg_line(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.trg_line() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    g geometry; s geometry; e geometry; m geometry;
    a record; b record;
BEGIN
    g := ST_LineMerge(ST_Force2D(NEW.geom));
    IF GeometryType(g) <> 'LINESTRING' THEN
        RAISE EXCEPTION 'Garis harus satu rangkaian yang tersambung (bukan beberapa potongan terpisah)';
    END IF;
    NEW.geom := g;
    s := ST_StartPoint(g);
    e := ST_EndPoint(g);
    m := ST_LineInterpolatePoint(g, 0.5);
    NEW.length_m  := round(ST_Length(g)::numeric, 3);
    NEW.n_vertex  := ST_NPoints(g);
    NEW.start_x   := round(ST_X(s)::numeric, 3);
    NEW.start_y   := round(ST_Y(s)::numeric, 3);
    NEW.end_x     := round(ST_X(e)::numeric, 3);
    NEW.end_y     := round(ST_Y(e)::numeric, 3);
    NEW.start_lon := round(ST_X(ST_Transform(s, 4326))::numeric, 7);
    NEW.start_lat := round(ST_Y(ST_Transform(s, 4326))::numeric, 7);
    NEW.end_lon   := round(ST_X(ST_Transform(e, 4326))::numeric, 7);
    NEW.end_lat   := round(ST_Y(ST_Transform(e, 4326))::numeric, 7);
    IF TG_TABLE_NAME = 'persil_pipe' THEN
        SELECT n.node_type, n.node_id, ST_Distance(n.geom, s) AS d INTO a
          FROM sewer.v_net_nodes_p n WHERE ST_DWithin(n.geom, s, 5) ORDER BY d, CASE n.node_type WHEN 'HI' THEN 0 WHEN 'IC' THEN 1 WHEN 'MH' THEN 2 ELSE 3 END LIMIT 1;
        SELECT n.node_type, n.node_id, ST_Distance(n.geom, e) AS d INTO b
          FROM sewer.v_net_nodes_p n WHERE ST_DWithin(n.geom, e, 5) ORDER BY d, CASE n.node_type WHEN 'HI' THEN 0 WHEN 'IC' THEN 1 WHEN 'MH' THEN 2 ELSE 3 END LIMIT 1;
    ELSE
        SELECT n.node_type, n.node_id, ST_Distance(n.geom, s) AS d INTO a
          FROM sewer.v_net_nodes n WHERE ST_DWithin(n.geom, s, 5) ORDER BY d, CASE n.node_type WHEN 'HI' THEN 0 WHEN 'IC' THEN 1 WHEN 'MH' THEN 2 ELSE 3 END LIMIT 1;
        SELECT n.node_type, n.node_id, ST_Distance(n.geom, e) AS d INTO b
          FROM sewer.v_net_nodes n WHERE ST_DWithin(n.geom, e, 5) ORDER BY d, CASE n.node_type WHEN 'HI' THEN 0 WHEN 'IC' THEN 1 WHEN 'MH' THEN 2 ELSE 3 END LIMIT 1;
    END IF;
    NEW.from_type := a.node_type;  NEW.from_id := a.node_id;  NEW.from_gap_m := round(a.d::numeric, 3);
    NEW.to_type   := b.node_type;  NEW.to_id   := b.node_id;  NEW.to_gap_m   := round(b.d::numeric, 3);
    NEW.snapped   := COALESCE(a.d <= 0.5, false) AND COALESCE(b.d <= 0.5, false);
    NEW.zone_no   := sewer.zone_of(m);
    NEW.rw_label  := sewer.rw_of(m);
    IF TG_OP = 'UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;


--
-- Name: trg_lp(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.trg_lp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' AND (NEW.pipe_id IS NULL OR NEW.pipe_id LIKE 'NEW-%') THEN
        NEW.pipe_id := NEW.from_mh || '>' || NEW.to_mh;
    END IF;
    NEW.geom := ST_LineMerge(ST_Force2D(NEW.geom));
    IF NEW.length_as_to_as_m IS NULL THEN
        NEW.length_as_to_as_m := round(ST_Length(NEW.geom)::numeric, 3);
    END IF;
    IF NEW.zone IS NULL THEN
        NEW.zone := sewer.zone_of(ST_LineInterpolatePoint(NEW.geom, 0.5));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM sewer.ref_stage
                    WHERE asset_type = 'lateral_pipe' AND method = 'ALL'
                      AND stage_code = NEW.stage_code) THEN
        RAISE EXCEPTION 'Tahap % tidak sah untuk pipa % (metode %). Pilihan: %',
            NEW.stage_code, NEW.pipe_id, NEW.method,
            (SELECT string_agg(stage_code, ', ' ORDER BY stage_order)
               FROM sewer.ref_stage WHERE asset_type = 'lateral_pipe' AND method = 'ALL');
    END IF;
    RETURN NEW;
END $$;


--
-- Name: trg_lp_follow(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.trg_lp_follow() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: trg_mh(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.trg_mh() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.geom := ST_Force2D(NEW.geom);
    IF NEW.zone IS NULL THEN
        NEW.zone := sewer.zone_of(NEW.geom);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM sewer.ref_stage
                    WHERE asset_type = 'manhole' AND method = 'ALL'
                      AND stage_code = NEW.stage_code) THEN
        RAISE EXCEPTION 'Tahap % tidak sah untuk manhole %. Pilihan: %',
            NEW.stage_code, NEW.manhole_id,
            (SELECT string_agg(stage_code, ', ' ORDER BY stage_order)
               FROM sewer.ref_stage WHERE asset_type = 'manhole' AND method = 'ALL');
    END IF;
    RETURN NEW;
END $$;


--
-- Name: trg_mh_delete(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.trg_mh_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE daftar text;
BEGIN
    SELECT string_agg(pipe_id, ', ' ORDER BY pipe_id) INTO daftar
      FROM sewer.lateral_pipe
     WHERE from_mh = OLD.manhole_id OR to_mh = OLD.manhole_id;
    IF daftar IS NOT NULL THEN
        RAISE EXCEPTION 'Manhole % masih dipakai pipa lateral: %. Hapus pipa itu lebih dulu dan simpan, atau pindahkan hulu atau hilirnya ke manhole lain.',
            OLD.manhole_id, daftar;
    END IF;
    RETURN OLD;
END $$;


--
-- Name: trg_mh_follow(); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.trg_mh_follow() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: zone_of(public.geometry); Type: FUNCTION; Schema: sewer; Owner: -
--

CREATE FUNCTION sewer.zone_of(g public.geometry) RETURNS smallint
    LANGUAGE sql STABLE
    AS $$ SELECT zone_no FROM sewer.zone_area WHERE ST_Intersects(geom, g) ORDER BY zone_no LIMIT 1 $$;


--
-- Name: to_dt(text); Type: FUNCTION; Schema: staging; Owner: -
--

CREATE FUNCTION staging.to_dt(t text) RETURNS date
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT CASE
           WHEN trim(t) ~ '^\d{2}/\d{2}/\d{4}$' THEN to_date(trim(t), 'DD/MM/YYYY')
           WHEN trim(t) ~ '^\d{4}-\d{2}-\d{2}'  THEN left(trim(t), 10)::date
         END
$_$;


--
-- Name: to_num(text); Type: FUNCTION; Schema: staging; Owner: -
--

CREATE FUNCTION staging.to_num(t text) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
  SELECT CASE
           WHEN replace(trim(t), ',', '.') ~ '^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)$'
           THEN replace(trim(t), ',', '.')::numeric
         END
$_$;


--
-- Name: trg_manhole_raw_progress(); Type: FUNCTION; Schema: staging; Owner: -
--

CREATE FUNCTION staging.trg_manhole_raw_progress() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: trg_manhole_raw_status(); Type: FUNCTION; Schema: staging; Owner: -
--

CREATE FUNCTION staging.trg_manhole_raw_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: seq_cp; Type: SEQUENCE; Schema: sewer; Owner: -
--

CREATE SEQUENCE sewer.seq_cp
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: collecting_pipe; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.collecting_pipe (
    cp_id text DEFAULT ('CP-N'::text || lpad((nextval('sewer.seq_cp'::regclass))::text, 4, '0'::text)) NOT NULL,
    length_m numeric(10,3),
    n_vertex integer,
    start_x numeric(12,3),
    start_y numeric(12,3),
    end_x numeric(12,3),
    end_y numeric(12,3),
    start_lon numeric(10,7),
    start_lat numeric(10,7),
    end_lon numeric(10,7),
    end_lat numeric(10,7),
    from_type text,
    from_id text,
    from_gap_m numeric(8,3),
    to_type text,
    to_id text,
    to_gap_m numeric(8,3),
    snapped boolean,
    zone_no smallint,
    rw_label text,
    stage_code text DEFAULT 'belum_mulai'::text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    geom public.geometry(LineString,32749) NOT NULL
);


--
-- Name: seq_hi; Type: SEQUENCE; Schema: sewer; Owner: -
--

CREATE SEQUENCE sewer.seq_hi
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: house_inlet; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.house_inlet (
    hi_id text DEFAULT ('HI-'::text || lpad((nextval('sewer.seq_hi'::regclass))::text, 5, '0'::text)) NOT NULL,
    hi_code text,
    elevation numeric(8,3),
    x numeric(12,3),
    y numeric(12,3),
    lon numeric(10,7),
    lat numeric(10,7),
    coord_ok boolean,
    zone_no smallint,
    rw_label text,
    stage_code text DEFAULT 'belum_mulai'::text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    geom public.geometry(Point,32749) NOT NULL,
    hi_status text,
    hi_kategori text,
    has_inside_pipe boolean,
    in_scope boolean
);


--
-- Name: seq_ic; Type: SEQUENCE; Schema: sewer; Owner: -
--

CREATE SEQUENCE sewer.seq_ic
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inspection_chamber; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.inspection_chamber (
    ic_id text DEFAULT ('IC-'::text || lpad((nextval('sewer.seq_ic'::regclass))::text, 4, '0'::text)) NOT NULL,
    ic_type text,
    elevation numeric(8,3),
    x numeric(12,3),
    y numeric(12,3),
    lon numeric(10,7),
    lat numeric(10,7),
    coord_ok boolean,
    zone_no smallint,
    rw_label text,
    stage_code text DEFAULT 'belum_mulai'::text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    geom public.geometry(Point,32749) NOT NULL
);


--
-- Name: seq_lp; Type: SEQUENCE; Schema: sewer; Owner: -
--

CREATE SEQUENCE sewer.seq_lp
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lateral_pipe; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.lateral_pipe (
    pipe_id text DEFAULT ('NEW-'::text || (nextval('sewer.seq_lp'::regclass))::text) NOT NULL,
    from_mh text NOT NULL,
    to_mh text NOT NULL,
    pipe_type text,
    method text NOT NULL,
    material text,
    diameter_mm integer,
    depth_class text,
    zone smallint,
    location_name text,
    existing_pavement text,
    road_width_m numeric(7,3),
    length_as_to_as_m numeric(10,3),
    length_net_m numeric(10,3),
    length_m numeric(10,3) GENERATED ALWAYS AS (COALESCE(length_net_m, length_as_to_as_m)) STORED,
    up_gl numeric(9,5),
    up_ie numeric(9,5),
    up_depth numeric(9,5),
    lw_gl numeric(9,5),
    lw_ie numeric(9,5),
    lw_depth numeric(9,5),
    drop_m numeric(9,5),
    slope_pct numeric(9,5),
    q_design_m3day numeric(14,3),
    v_full_ms numeric(9,6),
    shaft text,
    plan_date date,
    actual_date date,
    stage_code text DEFAULT 'belum_mulai'::text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    geom public.geometry(LineString,32749) NOT NULL,
    CONSTRAINT lateral_pipe_check CHECK ((from_mh <> to_mh)),
    CONSTRAINT lateral_pipe_method_check CHECK ((method = ANY (ARRAY['Jacking'::text, 'Open Trench'::text]))),
    CONSTRAINT lateral_pipe_pipe_type_check CHECK ((pipe_type = ANY (ARRAY['Primary'::text, 'Secondary'::text, 'Tertiary'::text]))),
    CONSTRAINT lateral_pipe_shaft_check CHECK ((shaft = ANY (ARRAY['AR'::text, 'DR'::text])))
);


--
-- Name: manhole; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.manhole (
    manhole_id text NOT NULL,
    manhole_no integer,
    mh_type text,
    zone smallint,
    location_name text,
    existing_pavement text,
    road_width_m numeric(7,3),
    diameter_mm integer,
    depth_class text,
    shaft text,
    ground_elev numeric(9,5),
    invert_elev numeric(9,5),
    depth_m numeric(9,5),
    elev_downstream numeric(9,5),
    elev_upstream_1 numeric(9,5),
    elev_upstream_2 numeric(9,5),
    elev_upstream_3 numeric(9,5),
    q_design_m3day numeric(14,3),
    velocity_ms numeric(9,6),
    plan_date date,
    actual_date date,
    stage_code text DEFAULT 'belum_mulai'::text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    geom public.geometry(Point,32749) NOT NULL,
    is_reference boolean DEFAULT false NOT NULL,
    progress_pct numeric(5,2) DEFAULT 0 NOT NULL,
    CONSTRAINT manhole_progress_chk CHECK (((progress_pct >= (0)::numeric) AND (progress_pct <= (100)::numeric))),
    CONSTRAINT manhole_shaft_check CHECK ((shaft = ANY (ARRAY['AR'::text, 'DR'::text])))
);


--
-- Name: manhole_work; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.manhole_work (
    manhole_id text NOT NULL,
    progress_pct numeric(5,2),
    work_stage text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT manhole_work_progress_pct_check CHECK (((progress_pct >= (0)::numeric) AND (progress_pct <= (100)::numeric))),
    CONSTRAINT manhole_work_work_stage_check CHECK ((work_stage = ANY (ARRAY['Galian Shaft'::text, 'Pekerjaan Jacking'::text, 'Pemasangan Pipa'::text, 'Pengembalian Galian'::text, 'House Keeping'::text])))
);


--
-- Name: COLUMN manhole_work.progress_pct; Type: COMMENT; Schema: sewer; Owner: -
--

COMMENT ON COLUMN sewer.manhole_work.progress_pct IS 'Progres manual 0-100 (%). NULL = pakai progres dari tahap (stage_code).';


--
-- Name: pengaturan; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.pengaturan (
    kunci text NOT NULL,
    nilai text
);


--
-- Name: seq_pp; Type: SEQUENCE; Schema: sewer; Owner: -
--

CREATE SEQUENCE sewer.seq_pp
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: persil_pipe; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.persil_pipe (
    pp_id text DEFAULT ('PP-N'::text || lpad((nextval('sewer.seq_pp'::regclass))::text, 4, '0'::text)) NOT NULL,
    length_m numeric(10,3),
    n_vertex integer,
    start_x numeric(12,3),
    start_y numeric(12,3),
    end_x numeric(12,3),
    end_y numeric(12,3),
    start_lon numeric(10,7),
    start_lat numeric(10,7),
    end_lon numeric(10,7),
    end_lat numeric(10,7),
    from_type text,
    from_id text,
    from_gap_m numeric(8,3),
    to_type text,
    to_id text,
    to_gap_m numeric(8,3),
    snapped boolean,
    zone_no smallint,
    rw_label text,
    stage_code text DEFAULT 'belum_mulai'::text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    geom public.geometry(LineString,32749) NOT NULL,
    is_schematic boolean DEFAULT false NOT NULL
);


--
-- Name: progress_log; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.progress_log (
    log_id bigint NOT NULL,
    asset_type text NOT NULL,
    asset_id text NOT NULL,
    log_date date DEFAULT CURRENT_DATE NOT NULL,
    stage_code text NOT NULL,
    note text,
    photo_url text,
    reported_by text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT progress_log_asset_type_check CHECK ((asset_type = ANY (ARRAY['manhole'::text, 'lateral_pipe'::text])))
);


--
-- Name: progress_log_log_id_seq; Type: SEQUENCE; Schema: sewer; Owner: -
--

CREATE SEQUENCE sewer.progress_log_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: progress_log_log_id_seq; Type: SEQUENCE OWNED BY; Schema: sewer; Owner: -
--

ALTER SEQUENCE sewer.progress_log_log_id_seq OWNED BY sewer.progress_log.log_id;


--
-- Name: progress_snapshot; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.progress_snapshot (
    snap_date date NOT NULL,
    zone text NOT NULL,
    pipe_n integer,
    pipe_len_m numeric(12,2),
    pipe_done_m numeric(12,2),
    pipe_pct numeric(6,2),
    pipe_selesai integer,
    mh_n integer,
    mh_selesai integer,
    mh_pct numeric(6,2),
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE progress_snapshot; Type: COMMENT; Schema: sewer; Owner: -
--

COMMENT ON TABLE sewer.progress_snapshot IS 'Satu baris per zona per hari, diisi sewer.snapshot_progress() dari update_dashboard.bat. Jalan berulang di hari yang sama menimpa baris hari itu.';


--
-- Name: ref_stage; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.ref_stage (
    asset_type text NOT NULL,
    method text DEFAULT 'ALL'::text NOT NULL,
    stage_order smallint NOT NULL,
    stage_code text NOT NULL,
    stage_label text NOT NULL,
    cum_weight numeric(5,2) NOT NULL,
    CONSTRAINT ref_stage_asset_type_check CHECK ((asset_type = ANY (ARRAY['manhole'::text, 'lateral_pipe'::text]))),
    CONSTRAINT ref_stage_cum_weight_check CHECK (((cum_weight >= (0)::numeric) AND (cum_weight <= (100)::numeric)))
);


--
-- Name: ref_work_stage; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.ref_work_stage (
    stage_code text NOT NULL,
    stage_label text NOT NULL,
    work_stage text,
    default_pct integer DEFAULT 0 NOT NULL,
    sort_order integer
);


--
-- Name: rw_boundary; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.rw_boundary (
    rw_label text NOT NULL,
    rw_no smallint,
    kelurahan text,
    rw_raw text,
    area_m2 numeric(14,2),
    cx numeric(12,3),
    cy numeric(12,3),
    clon numeric(10,7),
    clat numeric(10,7),
    geom public.geometry(MultiPolygon,32749) NOT NULL
);


--
-- Name: urutan_zona2; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.urutan_zona2 (
    alternatif smallint NOT NULL,
    jenis text NOT NULL,
    urutan smallint NOT NULL,
    kode text NOT NULL,
    asset_id text NOT NULL,
    keterangan text,
    plan_start date NOT NULL,
    plan_finish date NOT NULL,
    CONSTRAINT urutan_zona2_jenis_check CHECK ((jenis = ANY (ARRAY['shaft'::text, 'jacking'::text])))
);


--
-- Name: TABLE urutan_zona2; Type: COMMENT; Schema: sewer; Owner: -
--

COMMENT ON TABLE sewer.urutan_zona2 IS 'Urutan shaft dan jacking Zona 2 dari gambar Alternatif 1 dan 2. Tanggal dihitung dengan pola MSP (21 hari per shaft, 21 hari per dorongan). Boleh diedit langsung; terapkan ke plan_date dengan SELECT sewer.terapkan_urutan_zona2(n).';


--
-- Name: v_lateral_pipe; Type: VIEW; Schema: sewer; Owner: -
--

CREATE VIEW sewer.v_lateral_pipe AS
 SELECT p.pipe_id,
    p.from_mh,
    p.to_mh,
    p.pipe_type,
    p.method,
    p.material,
    p.diameter_mm,
    p.depth_class,
    p.zone,
    p.location_name,
    p.existing_pavement,
    p.road_width_m,
    p.length_as_to_as_m,
    p.length_net_m,
    p.length_m,
    p.up_gl,
    p.up_ie,
    p.up_depth,
    p.lw_gl,
    p.lw_ie,
    p.lw_depth,
    p.drop_m,
    p.slope_pct,
    p.q_design_m3day,
    p.v_full_ms,
    p.shaft,
    p.plan_date,
    p.actual_date,
    p.stage_code,
    p.updated_at,
    p.geom,
    s.stage_label,
    COALESCE(s.cum_weight, (0)::numeric) AS progress_pct
   FROM (sewer.lateral_pipe p
     LEFT JOIN LATERAL ( SELECT r.stage_label,
            r.cum_weight
           FROM sewer.ref_stage r
          WHERE ((r.asset_type = 'lateral_pipe'::text) AND (r.stage_code = p.stage_code) AND (r.method = ANY (ARRAY[p.method, 'ALL'::text])))
          ORDER BY (r.method = p.method) DESC
         LIMIT 1) s ON (true));


--
-- Name: v_manhole; Type: VIEW; Schema: sewer; Owner: -
--

CREATE VIEW sewer.v_manhole AS
 SELECT m.manhole_id,
    m.manhole_no,
    m.mh_type,
    m.zone,
    m.location_name,
    m.existing_pavement,
    m.road_width_m,
    m.diameter_mm,
    m.depth_class,
    m.shaft,
    m.ground_elev,
    m.invert_elev,
    m.depth_m,
    m.elev_downstream,
    m.elev_upstream_1,
    m.elev_upstream_2,
    m.elev_upstream_3,
    m.q_design_m3day,
    m.velocity_ms,
    m.plan_date,
    m.actual_date,
    m.stage_code,
    m.updated_at,
    m.geom,
    m.is_reference,
    s.stage_label,
    COALESCE(NULLIF(m.progress_pct, (0)::numeric), s.cum_weight, (0)::numeric) AS progress_pct,
    w.work_stage
   FROM ((sewer.manhole m
     LEFT JOIN sewer.ref_stage s ON (((s.asset_type = 'manhole'::text) AND (s.method = 'ALL'::text) AND (s.stage_code = m.stage_code))))
     LEFT JOIN sewer.manhole_work w ON ((w.manhole_id = m.manhole_id)));


--
-- Name: v_manhole_summary; Type: VIEW; Schema: sewer; Owner: -
--

CREATE VIEW sewer.v_manhole_summary AS
 SELECT v_manhole.zone,
    count(*) AS n_total,
    count(*) FILTER (WHERE (v_manhole.stage_code = 'selesai'::text)) AS n_selesai,
    round(avg(v_manhole.progress_pct), 1) AS progress_pct
   FROM sewer.v_manhole
  WHERE (NOT v_manhole.is_reference)
  GROUP BY v_manhole.zone;


--
-- Name: v_net_nodes; Type: VIEW; Schema: sewer; Owner: -
--

CREATE VIEW sewer.v_net_nodes AS
 SELECT 'IC'::text AS node_type,
    inspection_chamber.ic_id AS node_id,
    inspection_chamber.geom
   FROM sewer.inspection_chamber
UNION ALL
 SELECT 'MH'::text AS node_type,
    manhole.manhole_id AS node_id,
    manhole.geom
   FROM sewer.manhole
UNION ALL
 SELECT 'LP'::text AS node_type,
    lateral_pipe.pipe_id AS node_id,
    lateral_pipe.geom
   FROM sewer.lateral_pipe;


--
-- Name: v_net_nodes_p; Type: VIEW; Schema: sewer; Owner: -
--

CREATE VIEW sewer.v_net_nodes_p AS
 SELECT v_net_nodes.node_type,
    v_net_nodes.node_id,
    v_net_nodes.geom
   FROM sewer.v_net_nodes
UNION ALL
 SELECT 'HI'::text AS node_type,
    house_inlet.hi_id AS node_id,
    house_inlet.geom
   FROM sewer.house_inlet;


--
-- Name: v_pipe_summary; Type: VIEW; Schema: sewer; Owner: -
--

CREATE VIEW sewer.v_pipe_summary AS
 SELECT v_lateral_pipe.zone,
    v_lateral_pipe.pipe_type,
    v_lateral_pipe.method,
    count(*) AS n_total,
    count(*) FILTER (WHERE (v_lateral_pipe.stage_code = 'selesai'::text)) AS n_selesai,
    round(sum(v_lateral_pipe.length_m), 1) AS length_plan_m,
    round(sum(((v_lateral_pipe.length_m * v_lateral_pipe.progress_pct) / (100)::numeric)), 1) AS length_progress_m,
    round((((100)::numeric * sum(((v_lateral_pipe.length_m * v_lateral_pipe.progress_pct) / (100)::numeric))) / NULLIF(sum(v_lateral_pipe.length_m), (0)::numeric)), 1) AS progress_pct
   FROM sewer.v_lateral_pipe
  GROUP BY v_lateral_pipe.zone, v_lateral_pipe.pipe_type, v_lateral_pipe.method;


--
-- Name: v_progress_daily; Type: VIEW; Schema: sewer; Owner: -
--

CREATE VIEW sewer.v_progress_daily AS
 SELECT progress_log.log_date,
    progress_log.asset_type,
    count(*) AS n_update,
    count(*) FILTER (WHERE (progress_log.stage_code = 'selesai'::text)) AS n_selesai
   FROM sewer.progress_log
  GROUP BY progress_log.log_date, progress_log.asset_type;


--
-- Name: zone_area; Type: TABLE; Schema: sewer; Owner: -
--

CREATE TABLE sewer.zone_area (
    zone_no smallint NOT NULL,
    zone_name text,
    area_attr_m2 numeric(14,2),
    area_m2 numeric(14,2),
    cx numeric(12,3),
    cy numeric(12,3),
    clon numeric(10,7),
    clat numeric(10,7),
    geom public.geometry(MultiPolygon,32749) NOT NULL
);


--
-- Name: ZONA_CWIS_06_RAW; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging."ZONA_CWIS_06_RAW" (
    id integer NOT NULL,
    geom public.geometry(MultiPolygonZ,32749),
    fid bigint,
    "Name" character varying(254),
    "Area" double precision
);


--
-- Name: ZONA_CWIS_06_RAW_id_seq; Type: SEQUENCE; Schema: staging; Owner: -
--

CREATE SEQUENCE staging."ZONA_CWIS_06_RAW_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ZONA_CWIS_06_RAW_id_seq; Type: SEQUENCE OWNED BY; Schema: staging; Owner: -
--

ALTER SEQUENCE staging."ZONA_CWIS_06_RAW_id_seq" OWNED BY staging."ZONA_CWIS_06_RAW".id;


--
-- Name: batas_rw_raw; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging.batas_rw_raw (
    id integer NOT NULL,
    geom public.geometry(MultiPolygonZ,32749),
    fid bigint,
    "Name" character varying(254)
);


--
-- Name: batas_rw_raw_id_seq; Type: SEQUENCE; Schema: staging; Owner: -
--

CREATE SEQUENCE staging.batas_rw_raw_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: batas_rw_raw_id_seq; Type: SEQUENCE OWNED BY; Schema: staging; Owner: -
--

ALTER SEQUENCE staging.batas_rw_raw_id_seq OWNED BY staging.batas_rw_raw.id;


--
-- Name: collecting_pipe_raw; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging.collecting_pipe_raw (
    id integer NOT NULL,
    geom public.geometry(LineStringZ,32749),
    fid bigint,
    "Layer" character varying,
    "PaperSpace" boolean,
    "SubClasses" character varying,
    "Linetype" character varying,
    "EntityHandle" character varying,
    "Text" character varying
);


--
-- Name: collecting_pipe_raw_id_seq; Type: SEQUENCE; Schema: staging; Owner: -
--

CREATE SEQUENCE staging.collecting_pipe_raw_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: collecting_pipe_raw_id_seq; Type: SEQUENCE OWNED BY; Schema: staging; Owner: -
--

ALTER SEQUENCE staging.collecting_pipe_raw_id_seq OWNED BY staging.collecting_pipe_raw.id;


--
-- Name: house_inlet_raw; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging.house_inlet_raw (
    id integer NOT NULL,
    geom public.geometry(PointZM,32749),
    fid bigint,
    field_1 integer,
    "Point" character varying,
    "Northing" double precision,
    "Easting" double precision,
    "Elevation" double precision
);


--
-- Name: house_inlet_raw_id_seq; Type: SEQUENCE; Schema: staging; Owner: -
--

CREATE SEQUENCE staging.house_inlet_raw_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: house_inlet_raw_id_seq; Type: SEQUENCE OWNED BY; Schema: staging; Owner: -
--

ALTER SEQUENCE staging.house_inlet_raw_id_seq OWNED BY staging.house_inlet_raw.id;


--
-- Name: ic_raw; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging.ic_raw (
    id integer NOT NULL,
    geom public.geometry(PointZM,32749),
    fid bigint,
    field_1 integer,
    field_2 double precision,
    field_3 double precision,
    field_4 double precision,
    field_5 character varying
);


--
-- Name: ic_raw_id_seq; Type: SEQUENCE; Schema: staging; Owner: -
--

CREATE SEQUENCE staging.ic_raw_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ic_raw_id_seq; Type: SEQUENCE OWNED BY; Schema: staging; Owner: -
--

ALTER SEQUENCE staging.ic_raw_id_seq OWNED BY staging.ic_raw.id;


--
-- Name: lateral_pipe_raw; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging.lateral_pipe_raw (
    id integer NOT NULL,
    geom public.geometry(LineStringZ,32749),
    fid bigint,
    "Text" character varying,
    "ZONE" character varying(20),
    "Pipe_Material" character varying,
    "Length_Pipe" double precision,
    "Pipe_Type " character varying,
    "PIPE_Method" character varying,
    "LENGTH_AstoAs" double precision,
    "STATUS_MC0" character varying(50),
    "Start_Y" double precision,
    "End_Y" double precision,
    "End_X" double precision,
    "Start_X" double precision,
    "PIPE_ZONE" integer,
    "PIPE_No." integer,
    "PIPE_Location" character varying,
    "PIPE_Existing Pavement" character varying,
    "PIPE_Width (m)" double precision,
    "PIPE_Methode" character varying,
    "PIPE_Downstream Manhole" character varying,
    "PIPE_D Pipe" integer,
    "PIPE_L Pipe" double precision,
    "PIPE_Up.GL" double precision,
    "PIPE_Up.IE" double precision,
    "PIPE_Up.Depth" double precision,
    "PIPE_Lw.GL" double precision,
    "PIPE_Lw. IE" double precision,
    "PIPE_Lw.Depth" double precision,
    "PIPE_Drop" double precision,
    "PIPE_Slope" double precision,
    "PIPE_Q Design" character varying,
    "PIPE_Shaft" character varying,
    "PIPE_Kec Penuh (m/dt)" double precision,
    "PIPE_PIPE CLASS." character varying,
    "PIPE_LENGTH (M)" double precision
);


--
-- Name: lateral_pipe_raw_id_seq; Type: SEQUENCE; Schema: staging; Owner: -
--

CREATE SEQUENCE staging.lateral_pipe_raw_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lateral_pipe_raw_id_seq; Type: SEQUENCE OWNED BY; Schema: staging; Owner: -
--

ALTER SEQUENCE staging.lateral_pipe_raw_id_seq OWNED BY staging.lateral_pipe_raw.id;


--
-- Name: manhole_raw; Type: TABLE; Schema: staging; Owner: -
--

CREATE TABLE staging.manhole_raw (
    id integer NOT NULL,
    geom public.geometry(PointM,32749),
    fid bigint,
    "Manhole" character varying,
    "X" double precision,
    "Y" double precision,
    "Type" character varying,
    "RENCANA_PEKERJAAN" date,
    "STATUS" character varying(50),
    "REALISASI PEKERJAAN" date,
    "Z DSM" double precision,
    "MANHOLE_No." integer,
    "MANHOLE_Location" character varying,
    "MANHOLE_Existing Pavement" character varying,
    "MANHOLE_Width (m)" double precision,
    "MANHOLE_Elevation UpStream 3" double precision,
    "MANHOLE_Elevation UpStream 2" double precision,
    "MANHOLE_Elevation UpStream 1" double precision,
    "MANHOLE_Elevation Downstream" double precision,
    "MANHOLE_Ground Elevation (Z)" double precision,
    "MANHOLE_Diameter Manhole" character varying,
    "MANHOLE_ZONE" integer,
    "MANHOLE_Qdebit (M3/Day)" character varying,
    "MANHOLE_V (m/dt)" double precision,
    "MANHOLE_SHAFT" character varying,
    progress_pct numeric(5,2) DEFAULT 0 NOT NULL,
    work_stage text,
    CONSTRAINT manhole_raw_progress_chk CHECK (((progress_pct >= (0)::numeric) AND (progress_pct <= (100)::numeric))),
    CONSTRAINT manhole_raw_work_stage_chk CHECK (((work_stage IS NULL) OR (work_stage = ANY (ARRAY['Galian Shaft'::text, 'Pekerjaan Jacking'::text, 'Pemasangan Pipa'::text, 'Pengembalian Galian'::text, 'House Keeping'::text]))))
);


--
-- Name: COLUMN manhole_raw.progress_pct; Type: COMMENT; Schema: staging; Owner: -
--

COMMENT ON COLUMN staging.manhole_raw.progress_pct IS 'Progres pekerjaan 0-100 (%)';


--
-- Name: COLUMN manhole_raw.work_stage; Type: COMMENT; Schema: staging; Owner: -
--

COMMENT ON COLUMN staging.manhole_raw.work_stage IS 'Pekerjaan yang sedang dilaksanakan';


--
-- Name: manhole_raw_id_seq; Type: SEQUENCE; Schema: staging; Owner: -
--

CREATE SEQUENCE staging.manhole_raw_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: manhole_raw_id_seq; Type: SEQUENCE OWNED BY; Schema: staging; Owner: -
--

ALTER SEQUENCE staging.manhole_raw_id_seq OWNED BY staging.manhole_raw.id;


--
-- Name: progress_log log_id; Type: DEFAULT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.progress_log ALTER COLUMN log_id SET DEFAULT nextval('sewer.progress_log_log_id_seq'::regclass);


--
-- Name: ZONA_CWIS_06_RAW id; Type: DEFAULT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging."ZONA_CWIS_06_RAW" ALTER COLUMN id SET DEFAULT nextval('staging."ZONA_CWIS_06_RAW_id_seq"'::regclass);


--
-- Name: batas_rw_raw id; Type: DEFAULT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.batas_rw_raw ALTER COLUMN id SET DEFAULT nextval('staging.batas_rw_raw_id_seq'::regclass);


--
-- Name: collecting_pipe_raw id; Type: DEFAULT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.collecting_pipe_raw ALTER COLUMN id SET DEFAULT nextval('staging.collecting_pipe_raw_id_seq'::regclass);


--
-- Name: house_inlet_raw id; Type: DEFAULT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.house_inlet_raw ALTER COLUMN id SET DEFAULT nextval('staging.house_inlet_raw_id_seq'::regclass);


--
-- Name: ic_raw id; Type: DEFAULT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.ic_raw ALTER COLUMN id SET DEFAULT nextval('staging.ic_raw_id_seq'::regclass);


--
-- Name: lateral_pipe_raw id; Type: DEFAULT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.lateral_pipe_raw ALTER COLUMN id SET DEFAULT nextval('staging.lateral_pipe_raw_id_seq'::regclass);


--
-- Name: manhole_raw id; Type: DEFAULT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.manhole_raw ALTER COLUMN id SET DEFAULT nextval('staging.manhole_raw_id_seq'::regclass);


--
-- Name: collecting_pipe collecting_pipe_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.collecting_pipe
    ADD CONSTRAINT collecting_pipe_pkey PRIMARY KEY (cp_id);


--
-- Name: house_inlet house_inlet_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.house_inlet
    ADD CONSTRAINT house_inlet_pkey PRIMARY KEY (hi_id);


--
-- Name: inspection_chamber inspection_chamber_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.inspection_chamber
    ADD CONSTRAINT inspection_chamber_pkey PRIMARY KEY (ic_id);


--
-- Name: lateral_pipe lateral_pipe_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.lateral_pipe
    ADD CONSTRAINT lateral_pipe_pkey PRIMARY KEY (pipe_id);


--
-- Name: manhole manhole_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.manhole
    ADD CONSTRAINT manhole_pkey PRIMARY KEY (manhole_id);


--
-- Name: manhole_work manhole_work_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.manhole_work
    ADD CONSTRAINT manhole_work_pkey PRIMARY KEY (manhole_id);


--
-- Name: pengaturan pengaturan_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.pengaturan
    ADD CONSTRAINT pengaturan_pkey PRIMARY KEY (kunci);


--
-- Name: persil_pipe persil_pipe_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.persil_pipe
    ADD CONSTRAINT persil_pipe_pkey PRIMARY KEY (pp_id);


--
-- Name: progress_log progress_log_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.progress_log
    ADD CONSTRAINT progress_log_pkey PRIMARY KEY (log_id);


--
-- Name: progress_snapshot progress_snapshot_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.progress_snapshot
    ADD CONSTRAINT progress_snapshot_pkey PRIMARY KEY (snap_date, zone);


--
-- Name: ref_stage ref_stage_asset_type_method_stage_order_key; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.ref_stage
    ADD CONSTRAINT ref_stage_asset_type_method_stage_order_key UNIQUE (asset_type, method, stage_order);


--
-- Name: ref_stage ref_stage_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.ref_stage
    ADD CONSTRAINT ref_stage_pkey PRIMARY KEY (asset_type, method, stage_code);


--
-- Name: ref_work_stage ref_work_stage_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.ref_work_stage
    ADD CONSTRAINT ref_work_stage_pkey PRIMARY KEY (stage_code);


--
-- Name: rw_boundary rw_boundary_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.rw_boundary
    ADD CONSTRAINT rw_boundary_pkey PRIMARY KEY (rw_label);


--
-- Name: urutan_zona2 urutan_zona2_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.urutan_zona2
    ADD CONSTRAINT urutan_zona2_pkey PRIMARY KEY (alternatif, jenis, urutan);


--
-- Name: zone_area zone_area_pkey; Type: CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.zone_area
    ADD CONSTRAINT zone_area_pkey PRIMARY KEY (zone_no);


--
-- Name: ZONA_CWIS_06_RAW ZONA_CWIS_06_RAW_pkey; Type: CONSTRAINT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging."ZONA_CWIS_06_RAW"
    ADD CONSTRAINT "ZONA_CWIS_06_RAW_pkey" PRIMARY KEY (id);


--
-- Name: batas_rw_raw batas_rw_raw_pkey; Type: CONSTRAINT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.batas_rw_raw
    ADD CONSTRAINT batas_rw_raw_pkey PRIMARY KEY (id);


--
-- Name: collecting_pipe_raw collecting_pipe_raw_pkey; Type: CONSTRAINT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.collecting_pipe_raw
    ADD CONSTRAINT collecting_pipe_raw_pkey PRIMARY KEY (id);


--
-- Name: house_inlet_raw house_inlet_raw_pkey; Type: CONSTRAINT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.house_inlet_raw
    ADD CONSTRAINT house_inlet_raw_pkey PRIMARY KEY (id);


--
-- Name: ic_raw ic_raw_pkey; Type: CONSTRAINT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.ic_raw
    ADD CONSTRAINT ic_raw_pkey PRIMARY KEY (id);


--
-- Name: lateral_pipe_raw lateral_pipe_raw_pkey; Type: CONSTRAINT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.lateral_pipe_raw
    ADD CONSTRAINT lateral_pipe_raw_pkey PRIMARY KEY (id);


--
-- Name: manhole_raw manhole_raw_pkey; Type: CONSTRAINT; Schema: staging; Owner: -
--

ALTER TABLE ONLY staging.manhole_raw
    ADD CONSTRAINT manhole_raw_pkey PRIMARY KEY (id);


--
-- Name: collecting_pipe_gix; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX collecting_pipe_gix ON sewer.collecting_pipe USING gist (geom);


--
-- Name: house_inlet_gix; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX house_inlet_gix ON sewer.house_inlet USING gist (geom);


--
-- Name: inspection_chamber_gix; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX inspection_chamber_gix ON sewer.inspection_chamber USING gist (geom);


--
-- Name: lateral_pipe_from_idx; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX lateral_pipe_from_idx ON sewer.lateral_pipe USING btree (from_mh);


--
-- Name: lateral_pipe_geom_gix; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX lateral_pipe_geom_gix ON sewer.lateral_pipe USING gist (geom);


--
-- Name: lateral_pipe_stage_idx; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX lateral_pipe_stage_idx ON sewer.lateral_pipe USING btree (stage_code);


--
-- Name: lateral_pipe_to_idx; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX lateral_pipe_to_idx ON sewer.lateral_pipe USING btree (to_mh);


--
-- Name: lateral_pipe_zone_idx; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX lateral_pipe_zone_idx ON sewer.lateral_pipe USING btree (zone, method);


--
-- Name: manhole_geom_gix; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX manhole_geom_gix ON sewer.manhole USING gist (geom);


--
-- Name: manhole_stage_idx; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX manhole_stage_idx ON sewer.manhole USING btree (stage_code);


--
-- Name: manhole_zone_idx; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX manhole_zone_idx ON sewer.manhole USING btree (zone);


--
-- Name: persil_pipe_gix; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX persil_pipe_gix ON sewer.persil_pipe USING gist (geom);


--
-- Name: progress_log_asset_idx; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX progress_log_asset_idx ON sewer.progress_log USING btree (asset_type, asset_id, log_date);


--
-- Name: progress_log_date_idx; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX progress_log_date_idx ON sewer.progress_log USING btree (log_date);


--
-- Name: rw_boundary_gix; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX rw_boundary_gix ON sewer.rw_boundary USING gist (geom);


--
-- Name: zone_area_gix; Type: INDEX; Schema: sewer; Owner: -
--

CREATE INDEX zone_area_gix ON sewer.zone_area USING gist (geom);


--
-- Name: sidx_ZONA_CWIS_06_RAW_geom; Type: INDEX; Schema: staging; Owner: -
--

CREATE INDEX "sidx_ZONA_CWIS_06_RAW_geom" ON staging."ZONA_CWIS_06_RAW" USING gist (geom);


--
-- Name: sidx_batas_rw_raw_geom; Type: INDEX; Schema: staging; Owner: -
--

CREATE INDEX sidx_batas_rw_raw_geom ON staging.batas_rw_raw USING gist (geom);


--
-- Name: sidx_collecting_pipe_raw_geom; Type: INDEX; Schema: staging; Owner: -
--

CREATE INDEX sidx_collecting_pipe_raw_geom ON staging.collecting_pipe_raw USING gist (geom);


--
-- Name: sidx_house_inlet_raw_geom; Type: INDEX; Schema: staging; Owner: -
--

CREATE INDEX sidx_house_inlet_raw_geom ON staging.house_inlet_raw USING gist (geom);


--
-- Name: sidx_ic_raw_geom; Type: INDEX; Schema: staging; Owner: -
--

CREATE INDEX sidx_ic_raw_geom ON staging.ic_raw USING gist (geom);


--
-- Name: collecting_pipe trg_cp_derive; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_cp_derive BEFORE INSERT OR UPDATE ON sewer.collecting_pipe FOR EACH ROW EXECUTE FUNCTION sewer.trg_line();


--
-- Name: house_inlet trg_hi_derive; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_hi_derive BEFORE INSERT OR UPDATE ON sewer.house_inlet FOR EACH ROW EXECUTE FUNCTION sewer.trg_hi();


--
-- Name: house_inlet trg_hi_follow; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_hi_follow AFTER UPDATE OF geom ON sewer.house_inlet FOR EACH ROW WHEN ((old.geom IS DISTINCT FROM new.geom)) EXECUTE FUNCTION sewer.trg_hi_follow();


--
-- Name: inspection_chamber trg_ic_derive; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_ic_derive BEFORE INSERT OR UPDATE ON sewer.inspection_chamber FOR EACH ROW EXECUTE FUNCTION sewer.trg_ic();


--
-- Name: inspection_chamber trg_ic_follow; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_ic_follow AFTER UPDATE OF geom ON sewer.inspection_chamber FOR EACH ROW WHEN ((old.geom IS DISTINCT FROM new.geom)) EXECUTE FUNCTION sewer.trg_ic_follow();


--
-- Name: lateral_pipe trg_lateral_pipe_touch; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_lateral_pipe_touch BEFORE UPDATE ON sewer.lateral_pipe FOR EACH ROW EXECUTE FUNCTION sewer.touch_updated_at();


--
-- Name: lateral_pipe trg_lp_derive; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_lp_derive BEFORE INSERT OR UPDATE ON sewer.lateral_pipe FOR EACH ROW EXECUTE FUNCTION sewer.trg_lp();


--
-- Name: lateral_pipe trg_lp_follow; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_lp_follow AFTER UPDATE OF geom ON sewer.lateral_pipe FOR EACH ROW WHEN ((old.geom IS DISTINCT FROM new.geom)) EXECUTE FUNCTION sewer.trg_lp_follow();


--
-- Name: manhole trg_manhole_touch; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_manhole_touch BEFORE UPDATE ON sewer.manhole FOR EACH ROW EXECUTE FUNCTION sewer.touch_updated_at();


--
-- Name: manhole_work trg_manhole_work_touch; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_manhole_work_touch BEFORE UPDATE ON sewer.manhole_work FOR EACH ROW EXECUTE FUNCTION sewer.touch_manhole_work();


--
-- Name: manhole trg_mh_check; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_mh_check BEFORE INSERT OR UPDATE ON sewer.manhole FOR EACH ROW EXECUTE FUNCTION sewer.trg_mh();


--
-- Name: manhole trg_mh_delete; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_mh_delete BEFORE DELETE ON sewer.manhole FOR EACH ROW EXECUTE FUNCTION sewer.trg_mh_delete();


--
-- Name: manhole trg_mh_follow; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_mh_follow AFTER UPDATE OF geom ON sewer.manhole FOR EACH ROW WHEN ((old.geom IS DISTINCT FROM new.geom)) EXECUTE FUNCTION sewer.trg_mh_follow();


--
-- Name: persil_pipe trg_pp_derive; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_pp_derive BEFORE INSERT OR UPDATE ON sewer.persil_pipe FOR EACH ROW EXECUTE FUNCTION sewer.trg_line();


--
-- Name: progress_log trg_progress_apply; Type: TRIGGER; Schema: sewer; Owner: -
--

CREATE TRIGGER trg_progress_apply BEFORE INSERT ON sewer.progress_log FOR EACH ROW EXECUTE FUNCTION sewer.apply_progress();


--
-- Name: manhole_raw trg_manhole_raw_progress; Type: TRIGGER; Schema: staging; Owner: -
--

CREATE TRIGGER trg_manhole_raw_progress AFTER INSERT OR UPDATE OF progress_pct, work_stage ON staging.manhole_raw FOR EACH ROW EXECUTE FUNCTION staging.trg_manhole_raw_progress();


--
-- Name: manhole_raw trg_manhole_raw_status; Type: TRIGGER; Schema: staging; Owner: -
--

CREATE TRIGGER trg_manhole_raw_status AFTER INSERT OR UPDATE OF "STATUS", "RENCANA_PEKERJAAN", "REALISASI PEKERJAAN" ON staging.manhole_raw FOR EACH ROW EXECUTE FUNCTION staging.trg_manhole_raw_status();


--
-- Name: lateral_pipe lateral_pipe_from_mh_fkey; Type: FK CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.lateral_pipe
    ADD CONSTRAINT lateral_pipe_from_mh_fkey FOREIGN KEY (from_mh) REFERENCES sewer.manhole(manhole_id);


--
-- Name: lateral_pipe lateral_pipe_to_mh_fkey; Type: FK CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.lateral_pipe
    ADD CONSTRAINT lateral_pipe_to_mh_fkey FOREIGN KEY (to_mh) REFERENCES sewer.manhole(manhole_id);


--
-- Name: manhole_work manhole_work_manhole_id_fkey; Type: FK CONSTRAINT; Schema: sewer; Owner: -
--

ALTER TABLE ONLY sewer.manhole_work
    ADD CONSTRAINT manhole_work_manhole_id_fkey FOREIGN KEY (manhole_id) REFERENCES sewer.manhole(manhole_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

--
-- PostgreSQL database dump
--

-- Dumped from database version 15.2
-- Dumped by pg_dump version 15.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: ref_stage; Type: TABLE DATA; Schema: sewer; Owner: postgres
--

INSERT INTO sewer.ref_stage VALUES ('manhole', 'ALL', 1, 'galian_shaft', 'Galian Shaft', 25.00);
INSERT INTO sewer.ref_stage VALUES ('manhole', 'ALL', 2, 'jacking', 'Jacking', 50.00);
INSERT INTO sewer.ref_stage VALUES ('manhole', 'ALL', 3, 'pemasangan_manhole', 'Pemasangan Manhole', 75.00);
INSERT INTO sewer.ref_stage VALUES ('manhole', 'ALL', 4, 'pekerjaan_selesai', 'Pekerjaan Selesai', 100.00);
INSERT INTO sewer.ref_stage VALUES ('lateral_pipe', 'ALL', 1, 'galian_shaft', 'Galian Shaft', 25.00);
INSERT INTO sewer.ref_stage VALUES ('lateral_pipe', 'ALL', 2, 'jacking', 'Jacking', 50.00);
INSERT INTO sewer.ref_stage VALUES ('lateral_pipe', 'ALL', 3, 'pemasangan_manhole', 'Pemasangan Manhole', 75.00);
INSERT INTO sewer.ref_stage VALUES ('lateral_pipe', 'ALL', 4, 'pekerjaan_selesai', 'Pekerjaan Selesai', 100.00);
INSERT INTO sewer.ref_stage VALUES ('manhole', 'ALL', 0, 'belum_mulai', 'Belum Mulai', 0.00);
INSERT INTO sewer.ref_stage VALUES ('lateral_pipe', 'ALL', 0, 'belum_mulai', 'Belum Mulai', 0.00);


--
-- Data for Name: ref_work_stage; Type: TABLE DATA; Schema: sewer; Owner: postgres
--

INSERT INTO sewer.ref_work_stage VALUES ('belum_mulai', 'Belum Mulai', 'Belum Mulai', 0, 1);
INSERT INTO sewer.ref_work_stage VALUES ('galian_shaft', 'Galian Shaft', 'Galian Shaft', 20, 2);


--
-- PostgreSQL database dump complete
--

