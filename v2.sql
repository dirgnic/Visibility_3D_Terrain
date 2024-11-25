-- 1. Install required extensions
CREATE EXTENSION IF NOT EXISTS postgis;

-- 2. Drop tables if they already exist
DROP TABLE IF EXISTS boxes;
DROP TABLE IF EXISTS viewer_position;

-- 3. Create tables
CREATE TABLE boxes (
    id SERIAL PRIMARY KEY,
    x_min FLOAT,
    y_min FLOAT,
    z_min FLOAT,
    x_max FLOAT,
    y_max FLOAT,
    z_max FLOAT
);

-- 4. Insert example data
INSERT INTO boxes (x_min, y_min, z_min, x_max, y_max, z_max)
VALUES
    (0, 0, 0, 1, 1, 1),
    (1, 0, 0, 2, 1, 2),
    (0, 1, 0, 1, 2, 3),
    (1, 1, 0, 2, 2, 1);


\set viewer_x 3
\set viewer_y 3
\set viewer_z 5


WITH RECURSIVE next_box AS (
    -- Base case: Start with the first box
    SELECT
        id AS box_id,
        x_min, y_min, z_min, x_max, y_max, z_max
    FROM boxes
    WHERE id = (SELECT MIN(id) FROM boxes)

    UNION ALL

    -- Recursive case: Move to the next box
    SELECT
        b.id AS box_id,
        b.x_min, b.y_min, b.z_min, b.x_max, b.y_max, b.z_max
    FROM next_box nb
    JOIN boxes b ON b.id > nb.box_id -- Move to the next box
),
box_faces AS (
    -- Generate all faces for each box from the recursive result
    SELECT
        nb.box_id,
        'front' AS face,
        ARRAY[
            nb.x_min, nb.y_max, nb.z_min,
            nb.x_max, nb.y_max, nb.z_min,
            nb.x_max, nb.y_max, nb.z_max,
            nb.x_min, nb.y_max, nb.z_max
        ] AS vertices
    FROM next_box nb
    UNION ALL
    SELECT
        nb.box_id,
        'back' AS face,
        ARRAY[
            nb.x_min, nb.y_min, nb.z_min,
            nb.x_max, nb.y_min, nb.z_min,
            nb.x_max, nb.y_min, nb.z_max,
            nb.x_min, nb.y_min, nb.z_max
        ] AS vertices
    FROM next_box nb
    UNION ALL
    SELECT
        nb.box_id,
        'left' AS face,
        ARRAY[
            nb.x_min, nb.y_min, nb.z_min,
            nb.x_min, nb.y_max, nb.z_min,
            nb.x_min, nb.y_max, nb.z_max,
            nb.x_min, nb.y_min, nb.z_max
        ] AS vertices
    FROM next_box nb
    UNION ALL
    SELECT
        nb.box_id,
        'right' AS face,
        ARRAY[
            nb.x_max, nb.y_min, nb.z_min,
            nb.x_max, nb.y_max, nb.z_min,
            nb.x_max, nb.y_max, nb.z_max,
            nb.x_max, nb.y_min, nb.z_max
        ] AS vertices
    FROM next_box nb
    UNION ALL
    SELECT
        nb.box_id,
        'top' AS face,
        ARRAY[
            nb.x_min, nb.y_min, nb.z_max,
            nb.x_max, nb.y_min, nb.z_max,
            nb.x_max, nb.y_max, nb.z_max,
            nb.x_min, nb.y_max, nb.z_max
        ] AS vertices
    FROM next_box nb
    UNION ALL
    SELECT
        nb.box_id,
        'bottom' AS face,
        ARRAY[
            nb.x_min, nb.y_min, nb.z_min,
            nb.x_max, nb.y_min, nb.z_min,
            nb.x_max, nb.y_max, nb.z_min,
            nb.x_min, nb.y_max, nb.z_min
        ] AS vertices
    FROM next_box nb
),
face_angles AS (
    -- Calculate distances and angles for each face
    SELECT
        bf.box_id,
        bf.face,
        bf.vertices,
        ST_Distance(
            ST_SetSRID(ST_MakePoint(:viewer_x, :viewer_y, :viewer_z), 4326),
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
            ((bf.vertices[3] + bf.vertices[6] + bf.vertices[9] + bf.vertices[12]) / 4) - :viewer_z,
            ST_Distance(
                ST_SetSRID(ST_MakePoint(:viewer_x, :viewer_y, :viewer_z), 4326),
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
                    ST_SetSRID(ST_MakePoint(:viewer_x, :viewer_y, :viewer_z), 4326),
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
                    ST_SetSRID(ST_MakePoint(:viewer_x, :viewer_y, :viewer_z), 4326),
                    ST_SetSRID(
                        ST_MakePoint(
                            (fa.vertices[1] + fa.vertices[4] + fa.vertices[7] + fa.vertices[10]) / 4,
                            (fa.vertices[2] + fa.vertices[5] + fa.vertices[8] + fa.vertices[11]) / 4,
                            (fa.vertices[3] + fa.vertices[6] + fa.vertices[9] + fa.vertices[12]) / 4
                        ),
                        4326
                    )
                ) -- Obstructing face is closer
        ) AND NOT EXISTS (
            -- additional condition: check line-of-sight obstr for higher angle faces
            SELECT 1
            FROM face_angles fa3
            WHERE
                fa3.angle > fa.angle -- face has a higher angle
              AND ST_Distance(
                    ST_SetSRID(ST_MakePoint(:viewer_x, :viewer_y, :viewer_z), 4326),
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
                    ST_SetSRID(ST_MakePoint(:viewer_x, :viewer_y, :viewer_z), 4326),
                    ST_SetSRID(
                        ST_MakePoint(
                            (fa.vertices[1] + fa.vertices[4] + fa.vertices[7] + fa.vertices[10]) / 4,
                            (fa.vertices[2] + fa.vertices[5] + fa.vertices[8] + fa.vertices[11]) / 4,
                            (fa.vertices[3] + fa.vertices[6] + fa.vertices[9] + fa.vertices[12]) / 4
                        ),
                        4326
                    )
                ) -- Obstructing face is closer
                AND ST_Intersects( -- Check line-of-sight intersection
                    ST_MakeLine(
                        ST_SetSRID(ST_MakePoint(:viewer_x, :viewer_y, :viewer_z), 4326), -- Viewer position
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
)
-- Final query to output all visible faces
SELECT
    box_id,
    face,
    vertices[1] AS x1, vertices[2] AS y1, vertices[3] AS z1,
    vertices[4] AS x2, vertices[5] AS y2, vertices[6] AS z2,
    vertices[7] AS x3, vertices[8] AS y3, vertices[9] AS z3,
    vertices[10] AS x4, vertices[11] AS y4, vertices[12] AS z4,
    :viewer_x AS viewer_x,
    :viewer_y AS viewer_y,
    :viewer_z AS viewer_z,
    visible
FROM visible_faces
ORDER BY box_id, face;

