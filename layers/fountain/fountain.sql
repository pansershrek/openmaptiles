-- etldoc: layer_fountain[shape=record fillcolor=lightpink, style="rounded,filled",
-- etldoc:     label="layer_fountain | <z0_8> z0_8 | <z9_13> z9_13 | <z14_> z14+" ] ;

CREATE OR REPLACE VIEW fountain_z12 AS
(
SELECT name, geometry,
       'fountain'::text AS class,
       is_intermittent
FROM osm_water_polygon
WHERE COALESCE(osm_water_polygon.tags->'amenity', '') = 'fountain'
);

CREATE OR REPLACE FUNCTION layer_fountain(bbox geometry, zoom_level integer)
    RETURNS TABLE
            (
                geometry     geometry,
                class        text,
                name         text,
                intermittent int
            )
AS
$$
SELECT geometry,
       class::text,
       name,
       is_intermittent::int AS intermittent
FROM (
         SELECT *
         FROM fountain_z12
         WHERE zoom_level >= 12
     ) AS zoom_levels
WHERE geometry && bbox;
$$ LANGUAGE SQL STABLE
                -- STRICT
                PARALLEL SAFE;
