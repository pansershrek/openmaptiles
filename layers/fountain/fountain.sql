-- etldoc: layer_fountain[shape=record fillcolor=lightpink, style="rounded,filled",
-- etldoc:     label="layer_fountain | <z0_8> z0_8 | <z9_13> z9_13 | <z14_> z14+" ] ;

CREATE OR REPLACE FUNCTION layer_fountain(bbox geometry, zoom_level integer)
    RETURNS TABLE
            (
                osm_id       bigint,
                geometry     geometry,
                name         text,
                name_en      text,
                name_de      text,
                tags         hstore,
                class        text,
                intermittent int
            )
AS
$$
SELECT
    -- etldoc: osm_fountain ->  layer_fountain:z9_13
    -- etldoc: osm_fountain ->  layer_fountain:z14_
    CASE
        WHEN osm_id < 0 THEN -osm_id * 10 + 4
        ELSE osm_id * 10 + 1
        END AS osm_id_hash,
    geometry,
    name,
    COALESCE(NULLIF(name_en, ''), name) AS name_en,
    COALESCE(NULLIF(name_de, ''), name, name_en) AS name_de,
    tags,
    'fountain'::text AS class,
    is_intermittent::int AS intermittent
FROM osm_fountain
WHERE geometry && bbox
    AND ((zoom_level BETWEEN 9 AND 13 AND LineLabel(zoom_level, NULLIF(name, ''), geometry))
    OR (zoom_level >= 14))
$$ LANGUAGE SQL STABLE
                -- STRICT
                PARALLEL SAFE;
