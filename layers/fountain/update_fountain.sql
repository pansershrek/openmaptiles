DROP TRIGGER IF EXISTS trigger_delete_line ON osm_water_polygon;
DROP TRIGGER IF EXISTS trigger_update_line ON osm_water_polygon;
DROP TRIGGER IF EXISTS trigger_insert_line ON osm_water_polygon;

CREATE OR REPLACE VIEW osm_fountain_view AS
SELECT wp.osm_id,
       ll.wkb_geometry AS geometry,
       name,
       name_en,
       name_de,
       update_tags(tags, ll.wkb_geometry) AS tags,
       ST_Area(wp.geometry) AS area,
       is_intermittent
FROM osm_water_polygon AS wp
         INNER JOIN lake_centerline ll ON wp.osm_id = ll.osm_id
WHERE wp.name <> '' AND tags->'amenity' = 'fountain'
  AND ST_IsValid(wp.geometry);

-- etldoc:  osm_water_polygon ->  osm_fountain
-- etldoc:  lake_centerline  ->  osm_fountain
CREATE TABLE IF NOT EXISTS osm_fountain AS
SELECT *
FROM osm_fountain_view;
DO
$$
    BEGIN
        ALTER TABLE osm_fountain
            ADD CONSTRAINT osm_fountain_pk PRIMARY KEY (osm_id);
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'primary key osm_fountain_pk already exists in osm_fountain.';
    END;
$$;
CREATE INDEX IF NOT EXISTS osm_fountain_geometry_idx ON osm_fountain USING gist (geometry);

-- Handle updates

CREATE SCHEMA IF NOT EXISTS fountain;

CREATE OR REPLACE FUNCTION fountain.delete() RETURNS trigger AS
$$
BEGIN
    DELETE
    FROM osm_fountain
    WHERE osm_fountain.osm_id = OLD.osm_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fountain.update() RETURNS trigger AS
$$
BEGIN
    UPDATE osm_fountain
    SET (osm_id, geometry, name, name_en, name_de, tags, area, is_intermittent) =
            (SELECT * FROM osm_fountain_view WHERE osm_fountain_view.osm_id = NEW.osm_id)
    WHERE osm_fountain.osm_id = NEW.osm_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fountain.insert() RETURNS trigger AS
$$
BEGIN
    INSERT INTO osm_fountain
    SELECT *
    FROM osm_fountain_view
    WHERE osm_fountain_view.osm_id = NEW.osm_id
    -- May happen in case we replay update
    ON CONFLICT ON CONSTRAINT osm_fountain_pk
    DO NOTHING;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_delete_line
    AFTER DELETE
    ON osm_water_polygon
    FOR EACH ROW
EXECUTE PROCEDURE fountain.delete();

CREATE TRIGGER trigger_update_line
    AFTER UPDATE
    ON osm_water_polygon
    FOR EACH ROW
EXECUTE PROCEDURE fountain.update();

CREATE TRIGGER trigger_insert_line
    AFTER INSERT
    ON osm_water_polygon
    FOR EACH ROW
EXECUTE PROCEDURE fountain.insert();
