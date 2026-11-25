-- =====================================================================
-- SINKRON TEST PIT: Google Sheet -> PostGIS (sewer.test_pit)
-- Dipasang oleh setup_otomasi.bat (aman diulang).
-- Dipakai oleh update_dashboard.bat langkah [2/7]:
--   1. sinkron\ambil_sheet_testpit.ps1 mengunduh tab TEST PIT sebagai CSV
--   2. isinya dimasukkan ke staging.tp_sheet
--   3. SELECT * FROM sewer.sinkron_test_pit();  -> memperbarui sewer.test_pit
-- Aturan:
--   * Kunci pencocokan: nomor test pit (TP 01 = 1).
--   * Status hanya NAIK: Direncanakan -> Ditunda -> Digali -> Selesai.
--     Status di Sheet yang lebih rendah dari database tidak menurunkan status.
--   * Tanggal, utilitas, permukaan, mandor, link BA: isi Sheet yang tidak kosong
--     menimpa database. Sel kosong di Sheet tidak menghapus isi database.
--   * Manhole acuan dan zona hanya diisi bila di database masih kosong.
--   * Posisi titik TIDAK pernah diubah.
--   * Nomor test pit baru: ditambahkan di posisi manhole acuannya. Bila manhole
--     tidak ditemukan, baris dilewati dan dilaporkan.
-- =====================================================================
SET search_path = sewer, public;
SET client_min_messages = warning;

CREATE SCHEMA IF NOT EXISTS staging;
CREATE TABLE IF NOT EXISTS staging.tp_sheet (
    tp text, zona text, mh text, utilitas text, permukaan text,
    status text, tanggal text, link text, mandor text
);
COMMENT ON TABLE staging.tp_sheet IS 'Isi mentah tab TEST PIT dari Google Sheet; dikosongkan dan diisi ulang setiap update_dashboard.bat';

-- Teks status bebas di Sheet -> status baku
CREATE OR REPLACE FUNCTION sewer.tp_status_sheet(s text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN s IS NULL OR btrim(s) = ''                  THEN NULL
        WHEN lower(s) ~ 'belum|rencana'                  THEN 'Direncanakan'
        WHEN lower(s) ~ 'selesai|sudah|done'             THEN 'Selesai'
        WHEN lower(s) ~ 'tunda|pending|batal|hold'       THEN 'Ditunda'
        WHEN lower(s) ~ 'gali|proses|berjalan|progres'   THEN 'Digali'
        ELSE 'Direncanakan' END
$$;

-- Urutan status untuk aturan "hanya naik"
CREATE OR REPLACE FUNCTION sewer.tp_rank(s text) RETURNS integer LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE s WHEN 'Selesai' THEN 3 WHEN 'Digali' THEN 2 WHEN 'Ditunda' THEN 1 ELSE 0 END
$$;

-- Nomor -> 'TP 01' (sama dengan tp_id)
CREATE OR REPLACE FUNCTION sewer.tp_label(n integer) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT 'TP ' || CASE WHEN n < 10 THEN '0' ELSE '' END || n
$$;

-- Tanggal dari Sheet: 26/07/2026 atau 2026-07-26. Yang tidak terbaca -> NULL
CREATE OR REPLACE FUNCTION sewer.tgl_sheet(s text) RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    s := btrim(COALESCE(s, ''));
    IF s ~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN RETURN to_date(s, 'DD/MM/YYYY'); END IF;
    IF s ~ '^\d{4}-\d{2}-\d{2}'      THEN RETURN left(s, 10)::date; END IF;
    RETURN NULL;
EXCEPTION WHEN others THEN
    RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION sewer.sinkron_test_pit()
RETURNS TABLE (hasil text, jumlah integer, contoh text) LANGUAGE plpgsql AS $$
DECLARE n_upd integer; n_ins integer;
BEGIN
    PERFORM set_config('client_min_messages', 'warning', true);   -- sembunyikan NOTICE
    DROP TABLE IF EXISTS pg_temp.tp_src, pg_temp.tp_plan;

    -- 1. Rapikan isi Sheet (satu baris per nomor TP; baris pertama yang dipakai)
    CREATE TEMP TABLE tp_src AS
    SELECT DISTINCT ON (no) *
      FROM (SELECT NULLIF(substring(tp from '\d{1,5}'), '')::integer                 AS no,
                   NULLIF(substring(zona from '\d{1,2}'), '')::smallint              AS zona,
                   NULLIF(upper(btrim(mh)), '')                                      AS mh,
                   CASE WHEN upper(btrim(utilitas)) IN ('TIDAK ADA UTILITAS', 'TIDAK ADA', '-')
                        THEN 'Tidak ada utilitas'
                        ELSE NULLIF(replace(btrim(utilitas), '"', '″'), '') END      AS util,
                   CASE WHEN btrim(COALESCE(permukaan, '')) IN ('', '-') THEN NULL
                        ELSE upper(left(btrim(permukaan), 1)) || lower(substr(btrim(permukaan), 2)) END AS surf,
                   sewer.tp_status_sheet(status)                                     AS st,
                   sewer.tgl_sheet(tanggal)                                          AS tgl,
                   NULLIF(btrim(tanggal), '')                                        AS tgl_teks,
                   NULLIF(regexp_replace(btrim(link), '\?usp=[^&]*$', ''), '')       AS link,
                   NULLIF(upper(btrim(mandor)), '')                                  AS mandor
              FROM staging.tp_sheet) s
     WHERE no IS NOT NULL
     ORDER BY no;

    -- 2. Rencana perubahan untuk titik yang sudah ada
    CREATE TEMP TABLE tp_plan AS
    SELECT t.tp_no, t.tp_id, t.status AS st_lama, s.st AS st_sheet,
           CASE WHEN s.st IS NOT NULL AND sewer.tp_rank(s.st) > sewer.tp_rank(t.status)
                THEN s.st ELSE t.status END                 AS st_baru,
           COALESCE(s.tgl,    t.actual_date)                AS tgl,
           COALESCE(s.util,   t.utility_found)              AS util,
           COALESCE(s.surf,   t.surface)                    AS surf,
           COALESCE(s.mandor, t.mandor)                     AS mandor,
           COALESCE(s.link,   t.doc_link)                   AS link,
           COALESCE(t.mh_ref, s.mh)                         AS mh,
           COALESCE(t.zone,   s.zona)                       AS zona,
           (t.actual_date, t.utility_found, t.surface, t.mandor, t.doc_link, t.mh_ref, t.zone, t.status)
             IS DISTINCT FROM
           (COALESCE(s.tgl, t.actual_date), COALESCE(s.util, t.utility_found), COALESCE(s.surf, t.surface),
            COALESCE(s.mandor, t.mandor), COALESCE(s.link, t.doc_link), COALESCE(t.mh_ref, s.mh),
            COALESCE(t.zone, s.zona),
            CASE WHEN s.st IS NOT NULL AND sewer.tp_rank(s.st) > sewer.tp_rank(t.status) THEN s.st ELSE t.status END)
                                                            AS berubah
      FROM sewer.test_pit t JOIN tp_src s ON s.no = t.tp_no;

    UPDATE sewer.test_pit t
       SET status = p.st_baru, actual_date = p.tgl, utility_found = p.util, surface = p.surf,
           mandor = p.mandor, doc_link = p.link, mh_ref = p.mh, zone = p.zona
      FROM tp_plan p
     WHERE t.tp_no = p.tp_no AND p.berubah;
    GET DIAGNOSTICS n_upd = ROW_COUNT;

    -- 3. Nomor TP baru yang manhole acuannya ada di database
    INSERT INTO sewer.test_pit (tp_no, zone, mh_ref, status, actual_date, utility_found, surface, mandor, doc_link)
    SELECT s.no, s.zona, s.mh, COALESCE(s.st, 'Direncanakan'), s.tgl, s.util, s.surf, s.mandor, s.link
      FROM tp_src s
     WHERE NOT EXISTS (SELECT 1 FROM sewer.test_pit t WHERE t.tp_no = s.no)
       AND s.mh IS NOT NULL
       AND EXISTS (SELECT 1 FROM sewer.manhole m
                    WHERE substring(m.manhole_id from '(\d{4}[A-Z]?)$') = substring(s.mh from '(\d{4}[A-Z]?)$'));
    GET DIAGNOSTICS n_ins = ROW_COUNT;

    -- 4. Laporan
    RETURN QUERY SELECT 'Baris test pit terbaca dari Sheet', count(*)::integer, NULL::text FROM tp_src;
    RETURN QUERY SELECT 'Status berubah', count(*)::integer,
                        left(string_agg(tp_id || ' ' || st_lama || ' -> ' || st_baru, ', ' ORDER BY tp_no), 300)
                   FROM tp_plan WHERE st_baru <> st_lama;
    RETURN QUERY SELECT 'Titik diperbarui (semua kolom)', n_upd, NULL::text;
    RETURN QUERY SELECT 'Titik baru ditambahkan', n_ins,
                        left(string_agg(sewer.tp_label(s.no), ', ' ORDER BY s.no), 300)
                   FROM tp_src s JOIN sewer.test_pit t ON t.tp_no = s.no
                  WHERE NOT EXISTS (SELECT 1 FROM tp_plan p WHERE p.tp_no = s.no);
    RETURN QUERY SELECT 'PERIKSA: TP baru dilewati (manhole tidak ditemukan)', count(*)::integer,
                        left(string_agg(sewer.tp_label(s.no) || ' (' || COALESCE(s.mh, 'manhole kosong') || ')', ', ' ORDER BY s.no), 300)
                   FROM tp_src s WHERE NOT EXISTS (SELECT 1 FROM sewer.test_pit t WHERE t.tp_no = s.no);
    RETURN QUERY SELECT 'PERIKSA: status Sheet lebih rendah dari database (tidak diubah)', count(*)::integer,
                        left(string_agg(tp_id || ' Sheet ' || st_sheet || ', database ' || st_lama, ', ' ORDER BY tp_no), 300)
                   FROM tp_plan WHERE st_sheet IS NOT NULL AND sewer.tp_rank(st_sheet) < sewer.tp_rank(st_lama);
    RETURN QUERY SELECT 'PERIKSA: tanggal tidak terbaca (pakai format 26/07/2026)', count(*)::integer,
                        left(string_agg(sewer.tp_label(no) || ' "' || tgl_teks || '"', ', ' ORDER BY no), 300)
                   FROM tp_src WHERE tgl_teks IS NOT NULL AND tgl IS NULL;
END $$;

COMMENT ON FUNCTION sewer.sinkron_test_pit() IS 'Memperbarui sewer.test_pit dari staging.tp_sheet (tab TEST PIT di Google Sheet). Lihat panduan/01_sinkron_test_pit.md';
