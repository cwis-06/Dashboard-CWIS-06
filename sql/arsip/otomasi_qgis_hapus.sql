-- =====================================================================
-- OTOMASI HAPUS: menghapus manhole yang masih dipakai pipa
-- Dijalankan setelah otomasi_qgis.sql (aman diulang). setup_otomasi.bat
-- menjalankan semua file otomasi_qgis*.sql berurutan.
--
--   * Manhole yang masih dipakai pipa lateral tetap TIDAK bisa dihapus (itu
--     pengaman supaya pipa tidak kehilangan ujungnya), tetapi pesan error di
--     QGIS sekarang menyebut pipa mana yang masih memakainya.
--   * Fungsi sewer.hapus_manhole() menghapus manhole beserta pipa lateral yang
--     memakainya dalam satu langkah, bila memang itu yang dimaksud.
-- =====================================================================

SET search_path = sewer, public;

CREATE OR REPLACE FUNCTION sewer.trg_mh_delete() RETURNS trigger LANGUAGE plpgsql AS $$
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
DROP TRIGGER IF EXISTS trg_mh_delete ON sewer.manhole;
CREATE TRIGGER trg_mh_delete BEFORE DELETE ON sewer.manhole
    FOR EACH ROW EXECUTE FUNCTION sewer.trg_mh_delete();

-- Hapus manhole dan (bila p_hapus_pipa = true) semua pipa lateral yang memakainya.
-- Contoh: SELECT sewer.hapus_manhole('MHJ_06_0284B', true);
CREATE OR REPLACE FUNCTION sewer.hapus_manhole(p_id text, p_hapus_pipa boolean DEFAULT false)
RETURNS text LANGUAGE plpgsql AS $$
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
