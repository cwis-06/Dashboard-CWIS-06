-- =====================================================================
-- ASET BARU CWIS 06: House Inlet, Inspection Chamber, Pipa Collecting,
-- Pipa Persil, Zona, Batas RW  ->  tabel bersih dengan koordinat
-- PostgreSQL 12+ dengan PostGIS | SRID 32749 (UTM 49S) | WGS84 = 4326
--
-- Asumsi: layer mentah sudah diimpor ke schema "staging" dengan nama
--   staging.house_inlet_raw, staging.ic_raw, staging.collecting_pipe_raw,
--   staging."ZONA_CWIS_06_RAW", staging.batas_rw_raw   (kolom geometri: geom)
-- Jika schema atau nama tabelnya berbeda, jalankan LANGKAH 0 lalu ganti.
-- Jika muncul "column ... does not exist", nama kolom di tabel Anda
-- berbeda huruf besar/kecil: jalankan query kolom di LANGKAH 0.
-- Jalankan per langkah (blok demi blok).
-- =====================================================================

-- LANGKAH 0. Cek nama tabel dan kolom mentah
SELECT table_schema, table_name FROM information_schema.tables
 WHERE table_name ILIKE '%raw%' ORDER BY 1, 2;

SELECT table_name, ordinal_position AS no, '[' || column_name || ']' AS kolom, data_type
  FROM information_schema.columns
 WHERE table_schema = 'staging'
   AND table_name IN ('house_inlet_raw','ic_raw','collecting_pipe_raw','ZONA_CWIS_06_RAW','batas_rw_raw')
 ORDER BY table_name, ordinal_position;

-- LANGKAH 1. QA data mentah (semua hasil sebaiknya kosong)
SELECT 'HI id ganda' AS cek, field_1::text AS nilai, count(*) FROM staging.house_inlet_raw GROUP BY field_1 HAVING count(*) > 1
UNION ALL
SELECT 'IC id ganda', field_1::text, count(*) FROM staging.ic_raw GROUP BY field_1 HAVING count(*) > 1
UNION ALL
SELECT 'Collecting handle ganda', "EntityHandle"::text, count(*) FROM staging.collecting_pipe_raw GROUP BY "EntityHandle" HAVING count(*) > 1
UNION ALL
SELECT 'Poligon tidak valid', "Name"::text, 1 FROM staging."ZONA_CWIS_06_RAW" WHERE NOT ST_IsValid(geom)
UNION ALL
SELECT 'RW tidak valid', "Name"::text, 1 FROM staging.batas_rw_raw WHERE NOT ST_IsValid(geom);

-- LANGKAH 2. Tabel bersih
CREATE TABLE IF NOT EXISTS sewer.zone_area (
    zone_no       smallint PRIMARY KEY,
    zone_name     text,
    area_attr_m2  numeric(14,2),                 -- luas dari atribut asli
    area_m2       numeric(14,2),                 -- luas dihitung dari geometri
    cx numeric(12,3), cy numeric(12,3),          -- titik label (UTM)
    clon numeric(10,7), clat numeric(10,7),      -- titik label (WGS84)
    geom          geometry(MultiPolygon, 32749) NOT NULL
);
CREATE TABLE IF NOT EXISTS sewer.rw_boundary (
    rw_label      text PRIMARY KEY,              -- contoh: RW 09 Genuksari
    rw_no         smallint, kelurahan text, rw_raw text,
    area_m2       numeric(14,2),
    cx numeric(12,3), cy numeric(12,3), clon numeric(10,7), clat numeric(10,7),
    geom          geometry(MultiPolygon, 32749) NOT NULL
);
CREATE TABLE IF NOT EXISTS sewer.house_inlet (
    hi_id         text PRIMARY KEY,              -- contoh: HI-00123
    hi_code       text,                          -- HIP potensi / HI disetujui tanpa pipa dalam / SR disetujui dengan pipa dalam
    hi_status     text,                          -- potensi | terkonfirmasi
    hi_kategori   text,
    has_inside_pipe boolean,                     -- true untuk SR
    in_scope      boolean,                       -- true untuk HI dan SR (target pemasangan)
    elevation     numeric(8,3),
    x numeric(12,3), y numeric(12,3), lon numeric(10,7), lat numeric(10,7),
    coord_ok      boolean,                       -- koordinat atribut = geometri
    zone_no       smallint, rw_label text,
    stage_code    text NOT NULL DEFAULT 'belum_mulai',
    updated_at    timestamptz NOT NULL DEFAULT now(),
    geom          geometry(Point, 32749) NOT NULL
);
CREATE TABLE IF NOT EXISTS sewer.inspection_chamber (
    ic_id         text PRIMARY KEY,              -- contoh: IC-0042
    ic_type       text,
    elevation     numeric(8,3),
    x numeric(12,3), y numeric(12,3), lon numeric(10,7), lat numeric(10,7),
    coord_ok      boolean,
    zone_no       smallint, rw_label text,
    stage_code    text NOT NULL DEFAULT 'belum_mulai',
    updated_at    timestamptz NOT NULL DEFAULT now(),
    geom          geometry(Point, 32749) NOT NULL
);
CREATE TABLE IF NOT EXISTS sewer.collecting_pipe (
    cp_id         text PRIMARY KEY,              -- CP- + EntityHandle CAD
    length_m      numeric(10,3),
    n_vertex      integer,
    start_x numeric(12,3), start_y numeric(12,3), end_x numeric(12,3), end_y numeric(12,3),
    start_lon numeric(10,7), start_lat numeric(10,7), end_lon numeric(10,7), end_lat numeric(10,7),
    from_type text, from_id text, from_gap_m numeric(8,3),   -- node terdekat di ujung awal (maks 5 m)
    to_type   text, to_id   text, to_gap_m   numeric(8,3),   -- node terdekat di ujung akhir
    snapped       boolean,                       -- kedua ujung menyentuh node (celah <= 0,5 m)
    zone_no       smallint, rw_label text,
    stage_code    text NOT NULL DEFAULT 'belum_mulai',
    updated_at    timestamptz NOT NULL DEFAULT now(),
    geom          geometry(LineString, 32749) NOT NULL
);
-- Pipa persil (HI ke IC/collecting/lateral): disiapkan kosong, struktur sama dengan collecting
CREATE TABLE IF NOT EXISTS sewer.persil_pipe (LIKE sewer.collecting_pipe INCLUDING ALL);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='sewer' AND table_name='persil_pipe' AND column_name='cp_id') THEN
    ALTER TABLE sewer.persil_pipe RENAME COLUMN cp_id TO pp_id;
  END IF;
END $$;
ALTER TABLE sewer.persil_pipe ADD COLUMN IF NOT EXISTS is_schematic boolean NOT NULL DEFAULT false;

-- Fungsi bantu: zona dan RW suatu geometri
CREATE OR REPLACE FUNCTION sewer.zone_of(g geometry) RETURNS smallint LANGUAGE sql STABLE AS
$$ SELECT zone_no FROM sewer.zone_area WHERE ST_Intersects(geom, g) ORDER BY zone_no LIMIT 1 $$;
CREATE OR REPLACE FUNCTION sewer.rw_of(g geometry) RETURNS text LANGUAGE sql STABLE AS
$$ SELECT rw_label FROM sewer.rw_boundary WHERE ST_Intersects(geom, g) ORDER BY rw_label LIMIT 1 $$;

-- LANGKAH 3. Muat data (aman diulang: tabel dikosongkan dulu; persil tidak disentuh)
TRUNCATE sewer.zone_area, sewer.rw_boundary, sewer.house_inlet, sewer.inspection_chamber, sewer.collecting_pipe;

-- 3a. Zona (poligon): koordinat titik label, luas dari geometri
INSERT INTO sewer.zone_area (zone_no, zone_name, area_attr_m2, area_m2, cx, cy, clon, clat, geom)
SELECT NULLIF(regexp_replace("Name", '\D', '', 'g'), '')::smallint,
       trim("Name"), "Area"::numeric, round(ST_Area(g)::numeric, 2),
       round(ST_X(ST_PointOnSurface(g))::numeric, 3), round(ST_Y(ST_PointOnSurface(g))::numeric, 3),
       round(ST_X(ST_Transform(ST_PointOnSurface(g), 4326))::numeric, 7),
       round(ST_Y(ST_Transform(ST_PointOnSurface(g), 4326))::numeric, 7), g
  FROM (SELECT *, ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Force2D(geom)), 3)) AS g
          FROM staging."ZONA_CWIS_06_RAW") s;

-- 3b. Batas RW: angka Romawi dan Arab diseragamkan (RW I Banjardowo, RW 9 Genuksari -> RW 01, RW 09)
INSERT INTO sewer.rw_boundary (rw_label, rw_no, kelurahan, rw_raw, area_m2, cx, cy, clon, clat, geom)
SELECT 'RW ' || lpad(no::text, 2, '0') || ' ' || kel, no, kel, trim("Name"), round(ST_Area(g)::numeric, 2),
       round(ST_X(ST_PointOnSurface(g))::numeric, 3), round(ST_Y(ST_PointOnSurface(g))::numeric, 3),
       round(ST_X(ST_Transform(ST_PointOnSurface(g), 4326))::numeric, 7),
       round(ST_Y(ST_Transform(ST_PointOnSurface(g), 4326))::numeric, 7), g
  FROM (SELECT "Name", split_part(trim("Name"), ' ', 3) AS kel,
               CASE upper(split_part(trim("Name"), ' ', 2))
                    WHEN 'I' THEN 1 WHEN 'II' THEN 2 WHEN 'III' THEN 3 WHEN 'IV' THEN 4 WHEN 'V' THEN 5
                    WHEN 'VI' THEN 6 WHEN 'VII' THEN 7 WHEN 'VIII' THEN 8 WHEN 'IX' THEN 9 WHEN 'X' THEN 10
                    ELSE split_part(trim("Name"), ' ', 2)::int END AS no,
               ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Force2D(geom)), 3)) AS g
          FROM staging.batas_rw_raw) s;

-- 3c. House Inlet (titik): koordinat UTM dan WGS84 dari geometri, cek terhadap Easting/Northing atribut
INSERT INTO sewer.house_inlet (hi_id, hi_code, hi_status, hi_kategori, has_inside_pipe, in_scope, elevation, x, y, lon, lat, coord_ok, zone_no, rw_label, geom)
SELECT 'HI-' || lpad(field_1::text, 5, '0'), trim("Point"),
       CASE upper(trim("Point")) WHEN 'HIP' THEN 'potensi' ELSE 'terkonfirmasi' END,
       CASE upper(trim("Point")) WHEN 'SR' THEN 'SR, disetujui dengan pipa dalam rumah'
                                 WHEN 'HI' THEN 'HI, disetujui tanpa pipa dalam rumah'
                                 ELSE 'Potensi, belum disurvey' END,
       upper(trim("Point")) = 'SR', upper(trim("Point")) IN ('HI', 'SR'), "Elevation"::numeric,
       round(ST_X(g)::numeric, 3), round(ST_Y(g)::numeric, 3),
       round(ST_X(ST_Transform(g, 4326))::numeric, 7), round(ST_Y(ST_Transform(g, 4326))::numeric, 7),
       abs(ST_X(g) - "Easting") < 0.5 AND abs(ST_Y(g) - "Northing") < 0.5,
       sewer.zone_of(g), sewer.rw_of(g), g
  FROM (SELECT *, ST_Force2D(geom) AS g FROM staging.house_inlet_raw) s;

-- 3d. Inspection Chamber (kolom field_1..field_5 = id, easting, northing, elevasi, tipe)
INSERT INTO sewer.inspection_chamber (ic_id, ic_type, elevation, x, y, lon, lat, coord_ok, zone_no, rw_label, geom)
SELECT 'IC-' || lpad(field_1::text, 4, '0'), trim(field_5::text), field_4::numeric,
       round(ST_X(g)::numeric, 3), round(ST_Y(g)::numeric, 3),
       round(ST_X(ST_Transform(g, 4326))::numeric, 7), round(ST_Y(ST_Transform(g, 4326))::numeric, 7),
       abs(ST_X(g) - field_2::numeric) < 0.5 AND abs(ST_Y(g) - field_3::numeric) < 0.5,
       sewer.zone_of(g), sewer.rw_of(g), g
  FROM (SELECT *, ST_Force2D(geom) AS g FROM staging.ic_raw) s;

-- 3e. Node jaringan untuk mencari sambungan ujung pipa (IC, manhole, pipa lateral)
CREATE OR REPLACE VIEW sewer.v_net_nodes AS
SELECT 'IC'::text AS node_type, ic_id AS node_id, geom FROM sewer.inspection_chamber
UNION ALL SELECT 'MH', manhole_id, geom FROM sewer.manhole
UNION ALL SELECT 'LP', pipe_id, geom FROM sewer.lateral_pipe;

-- 3f. Pipa collecting (garis): koordinat awal dan akhir, panjang, node terdekat di kedua ujung
INSERT INTO sewer.collecting_pipe (
    cp_id, length_m, n_vertex, start_x, start_y, end_x, end_y, start_lon, start_lat, end_lon, end_lat,
    from_type, from_id, from_gap_m, to_type, to_id, to_gap_m, snapped, zone_no, rw_label, geom)
SELECT 'CP-' || s."EntityHandle", round(ST_Length(s.g)::numeric, 3), ST_NPoints(s.g),
       round(ST_X(ST_StartPoint(s.g))::numeric, 3), round(ST_Y(ST_StartPoint(s.g))::numeric, 3),
       round(ST_X(ST_EndPoint(s.g))::numeric, 3),   round(ST_Y(ST_EndPoint(s.g))::numeric, 3),
       round(ST_X(ST_Transform(ST_StartPoint(s.g), 4326))::numeric, 7), round(ST_Y(ST_Transform(ST_StartPoint(s.g), 4326))::numeric, 7),
       round(ST_X(ST_Transform(ST_EndPoint(s.g), 4326))::numeric, 7),   round(ST_Y(ST_Transform(ST_EndPoint(s.g), 4326))::numeric, 7),
       a.node_type, a.node_id, round(a.d::numeric, 3), b.node_type, b.node_id, round(b.d::numeric, 3),
       COALESCE(a.d <= 0.5, false) AND COALESCE(b.d <= 0.5, false),
       sewer.zone_of(ST_LineInterpolatePoint(s.g, 0.5)), sewer.rw_of(ST_LineInterpolatePoint(s.g, 0.5)), s.g
  FROM (SELECT *, ST_LineMerge(ST_Force2D(geom)) AS g FROM staging.collecting_pipe_raw) s
  LEFT JOIN LATERAL (SELECT node_type, node_id, ST_Distance(n.geom, ST_StartPoint(s.g)) AS d
                       FROM sewer.v_net_nodes n WHERE ST_DWithin(n.geom, ST_StartPoint(s.g), 5)
                      ORDER BY d, CASE n.node_type WHEN 'IC' THEN 1 WHEN 'MH' THEN 2 ELSE 3 END LIMIT 1) a ON true
  LEFT JOIN LATERAL (SELECT node_type, node_id, ST_Distance(n.geom, ST_EndPoint(s.g)) AS d
                       FROM sewer.v_net_nodes n WHERE ST_DWithin(n.geom, ST_EndPoint(s.g), 5)
                      ORDER BY d, CASE n.node_type WHEN 'IC' THEN 1 WHEN 'MH' THEN 2 ELSE 3 END LIMIT 1) b ON true;

-- LANGKAH 4. Indeks spasial
CREATE INDEX IF NOT EXISTS zone_area_gix   ON sewer.zone_area   USING gist (geom);
CREATE INDEX IF NOT EXISTS rw_boundary_gix ON sewer.rw_boundary USING gist (geom);
CREATE INDEX IF NOT EXISTS house_inlet_gix ON sewer.house_inlet USING gist (geom);
CREATE INDEX IF NOT EXISTS inspection_chamber_gix ON sewer.inspection_chamber USING gist (geom);
CREATE INDEX IF NOT EXISTS collecting_pipe_gix    ON sewer.collecting_pipe    USING gist (geom);
CREATE INDEX IF NOT EXISTS persil_pipe_gix        ON sewer.persil_pipe        USING gist (geom);
ANALYZE sewer.house_inlet; ANALYZE sewer.inspection_chamber; ANALYZE sewer.collecting_pipe;
COMMIT;

-- LANGKAH 5. Ringkasan dan QA hasil
SELECT 'house_inlet' AS tabel, count(*) AS n FROM sewer.house_inlet
UNION ALL SELECT 'inspection_chamber', count(*) FROM sewer.inspection_chamber
UNION ALL SELECT 'collecting_pipe', count(*) FROM sewer.collecting_pipe
UNION ALL SELECT 'zone_area', count(*) FROM sewer.zone_area
UNION ALL SELECT 'rw_boundary', count(*) FROM sewer.rw_boundary;

-- Titik di luar semua zona atau RW (batas poligon bermasalah atau titik di luar area)
SELECT 'HI' AS aset, hi_id AS id, hi_code AS kode FROM sewer.house_inlet WHERE zone_no IS NULL OR rw_label IS NULL
UNION ALL SELECT 'IC', ic_id, ic_type FROM sewer.inspection_chamber WHERE zone_no IS NULL OR rw_label IS NULL;

-- Koordinat atribut tidak sama dengan geometri
SELECT 'HI' AS aset, hi_id AS id FROM sewer.house_inlet WHERE NOT coord_ok
UNION ALL SELECT 'IC', ic_id FROM sewer.inspection_chamber WHERE NOT coord_ok;

-- Pipa collecting yang ujungnya belum menyentuh node (celah terbesar di atas)
SELECT cp_id, length_m, from_type, from_gap_m, to_type, to_gap_m
  FROM sewer.collecting_pipe WHERE NOT snapped
 ORDER BY GREATEST(COALESCE(from_gap_m, 99), COALESCE(to_gap_m, 99)) DESC;

-- Luas zona: atribut vs geometri
SELECT zone_name, area_attr_m2, area_m2, round(area_m2 - area_attr_m2, 1) AS selisih FROM sewer.zone_area ORDER BY zone_no;

-- HI per zona dan kategori (SR dan HI = target pemasangan, HIP = potensi)
SELECT zone_no, hi_code, count(*) FROM sewer.house_inlet GROUP BY ROLLUP (zone_no, hi_code) ORDER BY 1, 2;

-- PATCH: jika tabel house_inlet sudah terlanjur dibuat tanpa kolom kategori, jalankan ini (tanpa mengulang langkah 3)
-- ALTER TABLE sewer.house_inlet ADD COLUMN IF NOT EXISTS hi_status text, ADD COLUMN IF NOT EXISTS hi_kategori text,
--   ADD COLUMN IF NOT EXISTS has_inside_pipe boolean, ADD COLUMN IF NOT EXISTS in_scope boolean;
-- UPDATE sewer.house_inlet SET
--   hi_status = CASE upper(hi_code) WHEN 'HIP' THEN 'potensi' ELSE 'terkonfirmasi' END,
--   hi_kategori = CASE upper(hi_code) WHEN 'SR' THEN 'SR, disetujui dengan pipa dalam rumah'
--                 WHEN 'HI' THEN 'HI, disetujui tanpa pipa dalam rumah' ELSE 'Potensi, belum disurvey' END,
--   has_inside_pipe = upper(hi_code) = 'SR', in_scope = upper(hi_code) IN ('HI', 'SR');

/* =====================================================================
   OPSIONAL: pipa persil INDIKATIF (garis lurus HI ke IC terdekat <= 40 m).
   Ini BUKAN data lapangan; hanya untuk visualisasi sementara dan ditandai
   is_schematic = true. Hapus begitu data persil asli ada:
       DELETE FROM sewer.persil_pipe WHERE is_schematic;
   Hanya HI dan SR (in_scope) yang dihubungkan; HIP masih potensi.
   Jalankan hanya jika Anda memang menginginkannya.

INSERT INTO sewer.persil_pipe (pp_id, length_m, n_vertex, start_x, start_y, end_x, end_y,
       from_type, from_id, to_type, to_id, to_gap_m, snapped, zone_no, rw_label, is_schematic, geom)
SELECT 'PP-' || h.hi_id, round(ST_Length(x.l)::numeric, 3), 2,
       round(ST_X(ST_StartPoint(x.l))::numeric, 3), round(ST_Y(ST_StartPoint(x.l))::numeric, 3),
       round(ST_X(ST_EndPoint(x.l))::numeric, 3),   round(ST_Y(ST_EndPoint(x.l))::numeric, 3),
       'HI', h.hi_id, 'IC', c.ic_id, 0, true, h.zone_no, h.rw_label, true, x.l
  FROM sewer.house_inlet h
  CROSS JOIN LATERAL (SELECT ic_id, geom FROM sewer.inspection_chamber
                       WHERE ST_DWithin(geom, h.geom, 40) ORDER BY geom <-> h.geom LIMIT 1) c
  CROSS JOIN LATERAL (SELECT ST_MakeLine(h.geom, c.geom) AS l) x
 WHERE h.in_scope;
   ===================================================================== */
