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

WITH RECURSIVE box_faces AS (
    -- Step 1: Generate six faces for each box
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
    -- Step 2: Calculate distances and angles for each face
    SELECT
        bf.box_id,
        bf.face,
        bf.vertices,
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
        ) AS angle,
        vp.x AS viewer_x,
        vp.y AS viewer_y,
        vp.z AS viewer_z
    FROM box_faces bf
    CROSS JOIN viewer_position vp
),
ordered_faces AS (
    -- Step 3: Order faces by distance
    SELECT
        fa.box_id,
        fa.face,
        fa.vertices,
        fa.distance_2d,
        fa.angle,
        fa.viewer_x,
        fa.viewer_y,
        fa.viewer_z,
        ROW_NUMBER() OVER (ORDER BY fa.distance_2d) AS row_num
    FROM face_angles fa
),
recursive_visibility AS (
    -- Base case: Start with the first face
    SELECT
        of.box_id,
        of.face,
        of.vertices,
        of.angle,
        of.distance_2d,
        of.row_num,
        of.angle AS max_angle,
        of.viewer_x,
        of.viewer_y,
        of.viewer_z,
        TRUE AS visible
    FROM ordered_faces of
    WHERE of.row_num = 1 -- Start with the closest face

    UNION ALL

    -- Recursive case: Process the next face in order
    SELECT
        of.box_id,
        of.face,
        of.vertices,
        of.angle,
        of.distance_2d,
        of.row_num,
        GREATEST(rv.max_angle, of.angle) AS max_angle,
        of.viewer_x,
        of.viewer_y,
        of.viewer_z,
        CASE
            WHEN of.angle > rv.max_angle THEN TRUE -- Visible if angle exceeds max_angle
            ELSE FALSE
        END AS visible
    FROM ordered_faces of
    JOIN recursive_visibility rv
        ON of.row_num = rv.row_num + 1 -- Process faces in sequence
)
-- Final output
SELECT DISTINCT
    box_id,
    face,
    vertices[1] AS x1, vertices[2] AS y1, vertices[3] AS z1,
    vertices[4] AS x2, vertices[5] AS y2, vertices[6] AS z2,
    vertices[7] AS x3, vertices[8] AS y3, vertices[9] AS z3,
    vertices[10] AS x4, vertices[11] AS y4, vertices[12] AS z4,
    viewer_x,
    viewer_y,
    viewer_z,
    visible
FROM recursive_visibility
ORDER BY box_id, face;
