DROP TRIGGER IF EXISTS trigger_flag_transportation ON osm_highway_linestring;
DROP TRIGGER IF EXISTS trigger_refresh ON transportation.updates;

-- Instead of using relations to find out the road names we
-- stitch together the touching ways with the same name
-- to allow for nice label rendering
-- Because this works well for roads that do not have relations as well


-- Improve performance of the sql in transportation_name/network_type.sql
CREATE INDEX IF NOT EXISTS osm_highway_linestring_highway_partial_idx
    ON osm_highway_linestring (highway)
    WHERE highway IN ('motorway', 'trunk', 'primary', 'construction');

-- etldoc: osm_highway_linestring ->  osm_transportation_merge_linestring
DROP MATERIALIZED VIEW IF EXISTS osm_transportation_merge_linestring CASCADE;
CREATE MATERIALIZED VIEW osm_transportation_merge_linestring AS
(
SELECT (ST_Dump(geometry)).geom AS geometry,
       NULL::bigint AS osm_id,
       highway,
       construction,
       is_bridge,
       is_tunnel,
       is_ford,
       z_order
FROM (
         SELECT ST_LineMerge(ST_Collect(geometry)) AS geometry,
                highway,
                construction,
                is_bridge,
                is_tunnel,
                is_ford,
                min(z_order) AS z_order
         FROM osm_highway_linestring
         WHERE (highway IN ('motorway', 'trunk', 'primary') OR
                highway = 'construction' AND construction IN ('motorway', 'trunk', 'primary'))
           AND ST_IsValid(geometry)
         GROUP BY highway, construction, is_bridge, is_tunnel, is_ford
     ) AS highway_union
    ) /* DELAY_MATERIALIZED_VIEW_CREATION */;
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_geometry_idx
    ON osm_transportation_merge_linestring USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_highway_partial_idx
    ON osm_transportation_merge_linestring (highway, construction)
    WHERE highway IN ('motorway', 'trunk', 'primary', 'construction');

-- etldoc: osm_transportation_merge_linestring -> osm_transportation_merge_linestring_gen_z8
DROP MATERIALIZED VIEW IF EXISTS osm_transportation_merge_linestring_gen_z8 CASCADE;
CREATE MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z8 AS
(
SELECT ST_Simplify(geometry, ZRes(12)) AS geometry,
       osm_id,
       highway,
       construction,
       is_bridge,
       is_tunnel,
       is_ford,
       z_order
FROM osm_transportation_merge_linestring
WHERE highway IN ('motorway', 'trunk', 'primary')
   OR highway = 'construction' AND construction IN ('motorway', 'trunk', 'primary')
    ) /* DELAY_MATERIALIZED_VIEW_CREATION */;
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_geometry_idx
    ON osm_transportation_merge_linestring_gen_z8 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_highway_partial_idx
    ON osm_transportation_merge_linestring_gen_z8 (highway, construction)
    WHERE highway IN ('motorway', 'trunk', 'primary', 'construction');


-- Handle updates

CREATE SCHEMA IF NOT EXISTS transportation;

CREATE TABLE IF NOT EXISTS transportation.updates
(
    id serial PRIMARY KEY,
    t text,
    UNIQUE (t)
);
CREATE OR REPLACE FUNCTION transportation.flag() RETURNS trigger AS
$$
BEGIN
    INSERT INTO transportation.updates(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION transportation.refresh() RETURNS trigger AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation';
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring;
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z8;
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z7;
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z6;
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z5;
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z4;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.updates;

    RAISE LOG 'Refresh transportation done in %', age(clock_timestamp(), t);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_flag_transportation
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_highway_linestring
    FOR EACH STATEMENT
EXECUTE PROCEDURE transportation.flag();

CREATE CONSTRAINT TRIGGER trigger_refresh
    AFTER INSERT
    ON transportation.updates
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE transportation.refresh();