CREATE TABLE boxes (
    id SERIAL PRIMARY KEY,
    x_min FLOAT,
    y_min FLOAT,
    z_min FLOAT,
    x_max FLOAT,
    y_max FLOAT,
    z_max FLOAT,
    geom GEOMETRY(POLYGON, 4326)
);


CREATE TABLE viewer_position (
    id SERIAL PRIMARY KEY,
    x FLOAT,
    y FLOAT,
    z FLOAT,
    point GEOMETRY(POINTZ, 4326)
);

DROP TABLE viewer_position;
-- Insert example boxes (grid-like terrain)
INSERT INTO boxes (x_min, y_min, z_min, x_max, y_max, z_max)
VALUES
    (0, 0, 0, 1, 1, 1),
    (1, 0, 0, 2, 1, 2),
    (0, 1, 0, 1, 2, 3),
    (1, 1, 0, 2, 2, 1);

-- Insert viewer position
INSERT INTO viewer_position (x, y, z, point)
VALUES (3, 3, 5, ST_SetSRID(ST_MakePoint(3, 3, 5), 4326));

WITH box_faces AS (
    -- gene the six faces of each box
    SELECT
        id AS box_id,
        'front' AS face,
        ARRAY[
            x_min, y_max, z_min,
            x_max, y_max, z_min,
            x_max, y_max, z_max,
            x_min, y_max, z_max
        ] AS vertices
    FROM boxes
    UNION ALL
    SELECT
        id AS box_id,
        'back' AS face,
        ARRAY[
            x_min, y_min, z_min,
            x_max, y_min, z_min,
            x_max, y_min, z_max,
            x_min, y_min, z_max
        ] AS vertices
    FROM boxes
    UNION ALL
    SELECT
        id AS box_id,
        'left' AS face,
        ARRAY[
            x_min, y_min, z_min,
            x_min, y_max, z_min,
            x_min, y_max, z_max,
            x_min, y_min, z_max
        ] AS vertices
    FROM boxes
    UNION ALL
    SELECT
        id AS box_id,
        'right' AS face,
        ARRAY[
            x_max, y_min, z_min,
            x_max, y_max, z_min,
            x_max, y_max, z_max,
            x_max, y_min, z_max
        ] AS vertices
    FROM boxes
    UNION ALL
    SELECT
        id AS box_id,
        'top' AS face,
        ARRAY[
            x_min, y_min, z_max,
            x_max, y_min, z_max,
            x_max, y_max, z_max,
            x_min, y_max, z_max
        ] AS vertices
    FROM boxes
    UNION ALL
    SELECT
        id AS box_id,
        'bottom' AS face,
        ARRAY[
            x_min, y_min, z_min,
            x_max, y_min, z_min,
            x_max, y_max, z_min,
            x_min, y_max, z_min
        ] AS vertices
    FROM boxes
),
face_angles AS (
    -- calc distances and angles for each face
    SELECT
        bf.box_id,
        bf.face,
        bf.vertices,
        ST_Distance(
            ST_SetSRID(vp.point, 4326), -- =viewer position has SRID 4326 for 3D
            ST_SetSRID(
                ST_MakePoint(
                    (bf.vertices[1] + bf.vertices[4] + bf.vertices[7] + bf.vertices[10]) / 4,
                    (bf.vertices[2] + bf.vertices[5] + bf.vertices[8] + bf.vertices[11]) / 4,
                    (bf.vertices[3] + bf.vertices[6] + bf.vertices[9] + bf.vertices[12]) / 4
                ),
                4326
            )
        ) AS distance_2d,
        ATAN2(
            ((bf.vertices[3] + bf.vertices[6] + bf.vertices[9] + bf.vertices[12]) / 4) - vp.z,
            ST_Distance(
                ST_SetSRID(vp.point, 4326),
                ST_SetSRID(
                    ST_MakePoint(
                        (bf.vertices[1] + bf.vertices[4] + bf.vertices[7] + bf.vertices[10]) / 4,
                        (bf.vertices[2] + bf.vertices[5] + bf.vertices[8] + bf.vertices[11]) / 4,
                        (bf.vertices[3] + bf.vertices[6] + bf.vertices[9] + bf.vertices[12]) / 4
                    ),
                    4326
                )
            )
        ) AS angle
    FROM box_faces bf
    CROSS JOIN viewer_position vp
),
visible_faces AS (
    -- det visibility and eliminate duplicates
    SELECT DISTINCT
        fa.box_id,
        fa.face,
        fa.vertices,
        NOT EXISTS (
            SELECT 1
            FROM face_angles fa2
            WHERE
                fa2.box_id != fa.box_id -- obstructing face belongs to different box
                AND fa2.angle > fa.angle -- obstructing face has a higher angle
                AND ST_Distance(
                    ST_SetSRID(vp.point, 4326),
                    ST_SetSRID(
                        ST_MakePoint(
                            (fa2.vertices[1] + fa2.vertices[4] + fa2.vertices[7] + fa2.vertices[10]) / 4,
                            (fa2.vertices[2] + fa2.vertices[5] + fa2.vertices[8] + fa2.vertices[11]) / 4,
                            (fa2.vertices[3] + fa2.vertices[6] + fa2.vertices[9] + fa2.vertices[12]) / 4
                        ),
                        4326
                    )
                ) <
                ST_Distance(
                    ST_SetSRID(vp.point, 4326),
                    ST_SetSRID(
                        ST_MakePoint(
                            (fa.vertices[1] + fa.vertices[4] + fa.vertices[7] + fa.vertices[10]) / 4,
                            (fa.vertices[2] + fa.vertices[5] + fa.vertices[8] + fa.vertices[11]) / 4,
                            (fa.vertices[3] + fa.vertices[6] + fa.vertices[9] + fa.vertices[12]) / 4
                        ),
                        4326
                    )
                ) -- obstructing face is closer
        ) AND NOT EXISTS (
            -- additional condition: check line-of-sight obstr for higher angle faces
            SELECT 1
            FROM face_angles fa3
            WHERE
                fa3.angle > fa.angle -- face has a higher angle
              AND ST_Distance(
                    ST_SetSRID(vp.point, 4326),
                    ST_SetSRID(
                        ST_MakePoint(
                            (fa3.vertices[1] + fa3.vertices[4] + fa3.vertices[7] + fa3.vertices[10]) / 4,
                            (fa3.vertices[2] + fa3.vertices[5] + fa3.vertices[8] + fa3.vertices[11]) / 4,
                            (fa3.vertices[3] + fa3.vertices[6] + fa3.vertices[9] + fa3.vertices[12]) / 4
                        ),
                        4326
                    )
                ) <=
                ST_Distance(
                    ST_SetSRID(vp.point, 4326),
                    ST_SetSRID(
                        ST_MakePoint(
                            (fa.vertices[1] + fa.vertices[4] + fa.vertices[7] + fa.vertices[10]) / 4,
                            (fa.vertices[2] + fa.vertices[5] + fa.vertices[8] + fa.vertices[11]) / 4,
                            (fa.vertices[3] + fa.vertices[6] + fa.vertices[9] + fa.vertices[12]) / 4
                        ),
                        4326
                    )
                ) -- obstructing face is closer/just as close
                AND ST_Intersects( -- Check line-of-sight intersection
                    ST_MakeLine(
                        ST_SetSRID(ST_MakePoint(vp.x, vp.y, vp.z), 4326), -- Viewer position
                        ST_SetSRID(
                            ST_MakePoint(
                                (fa.vertices[1] + fa.vertices[4] + fa.vertices[7] + fa.vertices[10]) / 4,
                                (fa.vertices[2] + fa.vertices[5] + fa.vertices[8] + fa.vertices[11]) / 4,
                                (fa.vertices[3] + fa.vertices[6] + fa.vertices[9] + fa.vertices[12]) / 4
                            ),
                            4326
                        )
                    ),
                    ST_SetSRID(
                        ST_MakePolygon(ST_MakeLine(ARRAY[
                            ST_SetSRID(ST_MakePoint(fa3.vertices[1], fa3.vertices[2], fa3.vertices[3]), 4326),
                            ST_SetSRID(ST_MakePoint(fa3.vertices[4], fa3.vertices[5], fa3.vertices[6]), 4326),
                            ST_SetSRID(ST_MakePoint(fa3.vertices[7], fa3.vertices[8], fa3.vertices[9]), 4326),
                            ST_SetSRID(ST_MakePoint(fa3.vertices[10], fa3.vertices[11], fa3.vertices[12]), 4326),
                            ST_SetSRID(ST_MakePoint(fa3.vertices[1], fa3.vertices[2], fa3.vertices[3]), 4326) -- Close polygon
                        ])),
                        4326
                    )
                ) -- LOS intersects another face

        ) AS visible
    FROM face_angles fa
    CROSS JOIN viewer_position vp


)

-- final CSV Output - for Blender
SELECT DISTINCT
    box_id,
    face,
    vertices[1] AS x1, vertices[2] AS y1, vertices[3] AS z1,
    vertices[4] AS x2, vertices[5] AS y2, vertices[6] AS z2,
    vertices[7] AS x3, vertices[8] AS y3, vertices[9] AS z3,
    vertices[10] AS x4, vertices[11] AS y4, vertices[12] AS z4,
    vp.x AS viewer_x, vp.y AS viewer_y, vp.z AS viewer_z, -- viewer pos
    visible
FROM visible_faces
CROSS JOIN viewer_position vp
ORDER BY box_id, face;
