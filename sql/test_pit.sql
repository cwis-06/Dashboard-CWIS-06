-- =====================================================================
-- TITIK TEST PIT CWIS-06 (150 titik, TP 66 sampai TP 215)
-- Sumber: TESPIT_ZONA_4_DAN_5.gpkg (105 titik, zona 4 dan 5) dan
--         TESPIT_ZONA_6.gpkg (45 titik, zona 6), diterima 20 November 2026.
-- Dijalankan oleh setup_otomasi.bat. Aman diulang: titik yang sudah ada
-- TIDAK ditimpa, jadi perubahan dari QGIS (status, kedalaman, dll.) tetap.
-- Diekspor update_dashboard.bat ke data/test_pit.geojson (layer "Test pit").
-- =====================================================================
SET search_path = sewer, public;

CREATE TABLE IF NOT EXISTS sewer.test_pit (
    tp_id          text PRIMARY KEY,               -- 'TP 66'; diisi otomatis dari tp_no
    tp_no          integer NOT NULL UNIQUE,        -- nomor test pit (ketik ini saat menambah titik)
    zone           smallint,                       -- zona pekerjaan; kosong = diisi dari poligon zona
    location_name  text,                           -- kosong = nama jalan pipa lateral terdekat (<= 30 m)
    status         text NOT NULL DEFAULT 'Direncanakan',  -- Direncanakan / Digali / Selesai
    depth_m        numeric(6,2),                   -- kedalaman galian
    ground_elev    numeric(8,3),                   -- muka tanah (GL)
    utility_found  text,                           -- utilitas yang ditemukan
    plan_date      date,
    actual_date    date,
    note           text,
    x              numeric(12,3),
    y              numeric(12,3),
    lon            numeric(10,7),
    lat            numeric(10,7),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    geom           geometry(Point, 32749) NOT NULL
);
CREATE INDEX IF NOT EXISTS test_pit_gix ON sewer.test_pit USING gist (geom);
COMMENT ON TABLE sewer.test_pit IS 'Titik test pit. Status: Direncanakan, Digali, Selesai (warna di dashboard: abu-abu, oranye, hijau).';

CREATE OR REPLACE FUNCTION sewer.trg_tp() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.tp_no IS NULL THEN
        NEW.tp_no := NULLIF(regexp_replace(COALESCE(NEW.tp_id, ''), '\D', '', 'g'), '')::integer;
    END IF;
    IF NEW.tp_no IS NULL THEN
        RAISE EXCEPTION 'Nomor test pit (tp_no) wajib diisi';
    END IF;
    NEW.tp_id  := 'TP ' || NEW.tp_no;
    NEW.geom   := ST_Force2D(NEW.geom);
    NEW.status := COALESCE(NULLIF(trim(NEW.status), ''), 'Direncanakan');
    IF NEW.zone IS NULL THEN
        NEW.zone := sewer.zone_of(NEW.geom);
    END IF;
    IF NEW.location_name IS NULL THEN
        SELECT p.location_name INTO NEW.location_name
          FROM sewer.lateral_pipe p
         WHERE ST_DWithin(p.geom, NEW.geom, 30)
         ORDER BY p.geom <-> NEW.geom LIMIT 1;
    END IF;
    NEW.x   := round(ST_X(NEW.geom)::numeric, 3);
    NEW.y   := round(ST_Y(NEW.geom)::numeric, 3);
    NEW.lon := round(ST_X(ST_Transform(NEW.geom, 4326))::numeric, 7);
    NEW.lat := round(ST_Y(ST_Transform(NEW.geom, 4326))::numeric, 7);
    IF TG_OP = 'UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_tp_derive ON sewer.test_pit;
CREATE TRIGGER trg_tp_derive BEFORE INSERT OR UPDATE ON sewer.test_pit
    FOR EACH ROW EXECUTE FUNCTION sewer.trg_tp();

-- Zona mengikuti atribut ZONA dari file survei (beberapa titik di batas zona
-- secara poligon jatuh di zona sebelah, mis. TP 80, 91, 100 di poligon zona 1).
INSERT INTO sewer.test_pit (tp_no, zone, geom) VALUES
  ( 66, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.480611382, -6.954401777), 4326), 32749)),
  ( 67, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481081628, -6.954564905), 4326), 32749)),
  ( 68, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481731886, -6.954164553), 4326), 32749)),
  ( 69, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481851151, -6.953761701), 4326), 32749)),
  ( 70, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482169003, -6.954737130), 4326), 32749)),
  ( 71, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482641330, -6.954869514), 4326), 32749)),
  ( 72, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482786090, -6.954364112), 4326), 32749)),
  ( 73, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482900321, -6.954018631), 4326), 32749)),
  ( 74, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.483128291, -6.954872162), 4326), 32749)),
  ( 75, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.483834977, -6.955014823), 4326), 32749)),
  ( 76, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.484047372, -6.954339183), 4326), 32749)),
  ( 77, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481550940, -6.954737187), 4326), 32749)),
  ( 78, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481582294, -6.955071357), 4326), 32749)),
  ( 79, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481452263, -6.955500194), 4326), 32749)),
  ( 80, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.480315258, -6.955947158), 4326), 32749)),
  ( 81, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.480818282, -6.955906236), 4326), 32749)),
  ( 82, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481156548, -6.955883323), 4326), 32749)),
  ( 83, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481880408, -6.956008683), 4326), 32749)),
  ( 84, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482215425, -6.956076439), 4326), 32749)),
  ( 85, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482453839, -6.955459002), 4326), 32749)),
  ( 86, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482559212, -6.955135691), 4326), 32749)),
  ( 87, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.483540002, -6.955236119), 4326), 32749)),
  ( 88, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.483379014, -6.955763827), 4326), 32749)),
  ( 89, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.483575380, -6.955807813), 4326), 32749)),
  ( 90, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.483236134, -6.956098350), 4326), 32749)),
  ( 91, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.480143207, -6.956496852), 4326), 32749)),
  ( 92, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.480717176, -6.956778267), 4326), 32749)),
  ( 93, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481201514, -6.956962433), 4326), 32749)),
  ( 94, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481892322, -6.956685327), 4326), 32749)),
  ( 95, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482143167, -6.956539397), 4326), 32749)),
  ( 96, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481193242, -6.957389423), 4326), 32749)),
  ( 97, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481998011, -6.957536382), 4326), 32749)),
  ( 98, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482771127, -6.957788614), 4326), 32749)),
  ( 99, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.483417402, -6.957892458), 4326), 32749)),
  (100, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.479739523, -6.957888140), 4326), 32749)),
  (101, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.480644763, -6.958055935), 4326), 32749)),
  (102, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.480762502, -6.957626787), 4326), 32749)),
  (103, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481446040, -6.958168907), 4326), 32749)),
  (104, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481477104, -6.957851567), 4326), 32749)),
  (105, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482661158, -6.959704139), 4326), 32749)),
  (106, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.481981354, -6.957899608), 4326), 32749)),
  (107, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482031943, -6.958269087), 4326), 32749)),
  (108, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482015345, -6.958603883), 4326), 32749)),
  (109, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482539327, -6.958333088), 4326), 32749)),
  (110, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.483094589, -6.958472843), 4326), 32749)),
  (111, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.483443838, -6.958597810), 4326), 32749)),
  (112, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482911397, -6.958922274), 4326), 32749)),
  (113, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.482790822, -6.959304672), 4326), 32749)),
  (114, 4, ST_Transform(ST_SetSRID(ST_MakePoint(110.483256891, -6.958995957), 4326), 32749)),
  (115, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.479820312, -6.959077845), 4326), 32749)),
  (116, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480218732, -6.959090549), 4326), 32749)),
  (117, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480516424, -6.958937100), 4326), 32749)),
  (118, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480625856, -6.958390205), 4326), 32749)),
  (119, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480765347, -6.959404480), 4326), 32749)),
  (120, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480997024, -6.959048346), 4326), 32749)),
  (121, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481235119, -6.958502767), 4326), 32749)),
  (122, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481377157, -6.959069902), 4326), 32749)),
  (123, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481731891, -6.958601456), 4326), 32749)),
  (124, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481901701, -6.959137812), 4326), 32749)),
  (125, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.482348623, -6.958903947), 4326), 32749)),
  (126, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.482638500, -6.959200002), 4326), 32749)),
  (127, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480330349, -6.959486896), 4326), 32749)),
  (128, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480794062, -6.959585541), 4326), 32749)),
  (129, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481233623, -6.959890028), 4326), 32749)),
  (130, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481658222, -6.960135386), 4326), 32749)),
  (131, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.482122312, -6.960237386), 4326), 32749)),
  (132, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.482798854, -6.960477545), 4326), 32749)),
  (133, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.479222121, -6.959646021), 4326), 32749)),
  (134, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.479982708, -6.960064457), 4326), 32749)),
  (135, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480580282, -6.960378110), 4326), 32749)),
  (136, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480804968, -6.960082375), 4326), 32749)),
  (137, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481087875, -6.960706073), 4326), 32749)),
  (138, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481607891, -6.960826823), 4326), 32749)),
  (139, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.482178691, -6.961015289), 4326), 32749)),
  (140, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481040715, -6.961081288), 4326), 32749)),
  (141, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.478950883, -6.960822267), 4326), 32749)),
  (142, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.479589307, -6.960951200), 4326), 32749)),
  (143, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480263960, -6.961450907), 4326), 32749)),
  (144, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480645681, -6.960152955), 4326), 32749)),
  (145, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481244186, -6.961564519), 4326), 32749)),
  (146, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481581920, -6.961576441), 4326), 32749)),
  (147, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.482063468, -6.961386938), 4326), 32749)),
  (148, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.482833353, -6.961982308), 4326), 32749)),
  (149, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.478740708, -6.962643071), 4326), 32749)),
  (150, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.479363276, -6.962736827), 4326), 32749)),
  (151, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.479711441, -6.962361392), 4326), 32749)),
  (152, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.479614407, -6.961841922), 4326), 32749)),
  (153, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.479916940, -6.961725350), 4326), 32749)),
  (154, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.479687887, -6.963444949), 4326), 32749)),
  (155, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480095280, -6.962586706), 4326), 32749)),
  (156, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480106400, -6.961893562), 4326), 32749)),
  (157, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480429355, -6.961810335), 4326), 32749)),
  (158, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480210676, -6.962906813), 4326), 32749)),
  (159, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480815877, -6.962807478), 4326), 32749)),
  (160, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481291632, -6.962619299), 4326), 32749)),
  (161, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481673125, -6.962930263), 4326), 32749)),
  (162, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.482139493, -6.963013288), 4326), 32749)),
  (163, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.482263673, -6.963471718), 4326), 32749)),
  (164, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.479412067, -6.963208311), 4326), 32749)),
  (165, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481779204, -6.962319773), 4326), 32749)),
  (166, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481411094, -6.961817184), 4326), 32749)),
  (167, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.481211933, -6.962230893), 4326), 32749)),
  (168, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480611696, -6.961965143), 4326), 32749)),
  (169, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.480870535, -6.962298966), 4326), 32749)),
  (170, 5, ST_Transform(ST_SetSRID(ST_MakePoint(110.479382638, -6.958976813), 4326), 32749)),
  (171, 6, ST_SetSRID(ST_MakePoint(442507.8646, 9230239.5490), 32749)),
  (172, 6, ST_SetSRID(ST_MakePoint(442558.4455, 9230276.5000), 32749)),
  (173, 6, ST_SetSRID(ST_MakePoint(442534.2065, 9230126.1690), 32749)),
  (174, 6, ST_SetSRID(ST_MakePoint(442691.0049, 9230222.7230), 32749)),
  (175, 6, ST_SetSRID(ST_MakePoint(442863.4315, 9230147.5430), 32749)),
  (176, 6, ST_SetSRID(ST_MakePoint(442513.0850, 9230060.9350), 32749)),
  (177, 6, ST_SetSRID(ST_MakePoint(442673.0531, 9230054.9790), 32749)),
  (178, 6, ST_SetSRID(ST_MakePoint(442849.6345, 9230026.3110), 32749)),
  (179, 6, ST_SetSRID(ST_MakePoint(442854.7155, 9230098.7000), 32749)),
  (180, 6, ST_SetSRID(ST_MakePoint(442906.7912, 9230032.2780), 32749)),
  (181, 6, ST_SetSRID(ST_MakePoint(442937.8395, 9230113.9580), 32749)),
  (182, 6, ST_SetSRID(ST_MakePoint(443015.4160, 9230187.3750), 32749)),
  (183, 6, ST_SetSRID(ST_MakePoint(442950.5655, 9229997.2790), 32749)),
  (184, 6, ST_SetSRID(ST_MakePoint(442657.5705, 9230001.9340), 32749)),
  (185, 6, ST_SetSRID(ST_MakePoint(442641.0396, 9229943.1470), 32749)),
  (186, 6, ST_SetSRID(ST_MakePoint(442623.6750, 9229890.5730), 32749)),
  (187, 6, ST_SetSRID(ST_MakePoint(442833.9299, 9229921.4500), 32749)),
  (188, 6, ST_SetSRID(ST_MakePoint(442787.2845, 9229908.7140), 32749)),
  (189, 6, ST_SetSRID(ST_MakePoint(442946.9870, 9229892.2100), 32749)),
  (190, 6, ST_SetSRID(ST_MakePoint(443041.2910, 9229976.3590), 32749)),
  (191, 6, ST_SetSRID(ST_MakePoint(443122.4515, 9230001.5600), 32749)),
  (192, 6, ST_SetSRID(ST_MakePoint(442422.8869, 9230256.4600), 32749)),
  (193, 6, ST_SetSRID(ST_MakePoint(442963.3980, 9229870.3780), 32749)),
  (194, 6, ST_SetSRID(ST_MakePoint(442938.5270, 9229799.4050), 32749)),
  (195, 6, ST_SetSRID(ST_MakePoint(442915.9970, 9229754.0210), 32749)),
  (196, 6, ST_SetSRID(ST_MakePoint(442881.6486, 9229680.4210), 32749)),
  (197, 6, ST_SetSRID(ST_MakePoint(442975.9782, 9229734.6760), 32749)),
  (198, 6, ST_SetSRID(ST_MakePoint(442868.1364, 9229609.0820), 32749)),
  (199, 6, ST_SetSRID(ST_MakePoint(443056.6022, 9229737.1510), 32749)),
  (200, 6, ST_SetSRID(ST_MakePoint(442946.4620, 9229671.3750), 32749)),
  (201, 6, ST_SetSRID(ST_MakePoint(442923.5070, 9229597.5530), 32749)),
  (202, 6, ST_SetSRID(ST_MakePoint(443069.0280, 9229786.5490), 32749)),
  (203, 6, ST_SetSRID(ST_MakePoint(443063.2171, 9229696.3190), 32749)),
  (204, 6, ST_SetSRID(ST_MakePoint(443040.7438, 9229631.4620), 32749)),
  (205, 6, ST_SetSRID(ST_MakePoint(443007.2190, 9229567.4870), 32749)),
  (206, 6, ST_SetSRID(ST_MakePoint(443195.8030, 9229769.2930), 32749)),
  (207, 6, ST_SetSRID(ST_MakePoint(443190.6330, 9229719.5890), 32749)),
  (208, 6, ST_SetSRID(ST_MakePoint(443142.2040, 9229714.6710), 32749)),
  (209, 6, ST_SetSRID(ST_MakePoint(443129.0700, 9229637.8480), 32749)),
  (210, 6, ST_SetSRID(ST_MakePoint(443237.3550, 9229617.5490), 32749)),
  (211, 6, ST_SetSRID(ST_MakePoint(443112.4150, 9229574.5920), 32749)),
  (212, 6, ST_SetSRID(ST_MakePoint(443076.4070, 9229524.3190), 32749)),
  (213, 6, ST_SetSRID(ST_MakePoint(443132.3668, 9229492.7110), 32749)),
  (214, 6, ST_SetSRID(ST_MakePoint(443200.9892, 9229458.3600), 32749)),
  (215, 6, ST_SetSRID(ST_MakePoint(442779.8577, 9229622.8060), 32749))
ON CONFLICT (tp_id) DO NOTHING;
