-- Drop the materialized view (this will also remove its indexes)
DROP MATERIALIZED VIEW entities_caches;

-- Recreate the materialized view with a deterministic ID
-- Copied and tweaked from 20251119191120_fix_null_ids_in_entities_cache.sql
CREATE MATERIALIZED VIEW entities_caches AS
-- Get the indexed fields for each family
WITH families_indexed_fields AS (
    SELECT
        f.id AS family_id,
        (
            SELECT jsonb_object_agg(field->>'key', field->>'field_type')
            FROM jsonb_array_elements(f.entity_form->'fields') AS field
            WHERE
                (field->>'indexed')::boolean IS TRUE
                AND
                (field->>'field_type')::text IN ('EnumSingleOption', 'EnumMultiOption')
        ) AS indexed_enums,
        (
            SELECT jsonb_object_agg(field->>'key', field->>'field_type')
            FROM jsonb_array_elements(f.entity_form->'fields') AS field
            WHERE
                (field->>'indexed')::boolean IS TRUE
                AND
                (field->>'field_type')::text IN ('SingleLineText', 'MultiLineText', 'RichText')
        ) AS indexed_strings
    FROM families f
),
-- For each location of each parent, get a row with the parent and its location flattened
transitive_locations AS (
    SELECT
        ee.child_id,
        e.id AS parent_id,
        e.display_name AS parent_display_name,
        parent_location.value,
        parent_location.ordinality AS location_index
    FROM entities_entities ee
    JOIN entities e ON ee.parent_id = e.id
    -- Join the locations from the array of locations
    LEFT JOIN LATERAL (
        SELECT value, ordinality
        FROM jsonb_array_elements(e.locations) WITH ORDINALITY AS location(value, ordinality)
    ) AS parent_location ON true
    WHERE e.moderated
),
-- For each location of each entity, get a row with the entity and its location
direct_locations AS (
    SELECT
        e.id AS entity_id,
        location.value,
        location.ordinality AS location_index
    FROM entities e 
    -- Join the locations from the array of locations
    LEFT JOIN LATERAL (
        SELECT value, ordinality
        FROM jsonb_array_elements(e.locations) WITH ORDINALITY AS location(value, ordinality)
    ) AS location ON true
    WHERE e.moderated
),
-- For entity, get a row with the entity information
entities_information AS (
    SELECT
        e.id AS entity_id,
        e.category_id,
        e.display_name,
        c.family_id,
        e.hidden,
        array_remove(array_agg(DISTINCT et.tag_id), NULL) AS tags_ids,
        COALESCE(
            jsonb_object_agg(
                key,
                CASE
                    WHEN jsonb_typeof(transformed_fields.value) = 'array' THEN transformed_fields.value
                    ELSE 
                        CASE
                            WHEN transformed_fields.value IS NULL THEN '[]'::jsonb
                            ELSE jsonb_build_array(transformed_fields.value)
                        END
                    END
            ) FILTER (WHERE key IS NOT NULL),
            '{}'::jsonb
        )AS enums,
        coalesce((
            SELECT string_agg(value::text, ' ')
            FROM jsonb_each_text(e.data)
            WHERE key IN (
                SELECT jsonb_object_keys(f.indexed_strings)
                FROM families_indexed_fields f
                WHERE f.family_id = c.family_id
            )
        ), '') || ' ' ||
        coalesce(string_agg(c.title::text, ' '), '') || ' ' ||
        coalesce(string_agg(ett.title::text, ' '), '') || ' ' ||
        coalesce(string_agg(cett.title::text, ' '), '')
        AS indexed_string_values
    FROM entities e
    JOIN categories c ON e.category_id = c.id
    LEFT JOIN entity_tags et ON e.id = et.entity_id
    LEFT JOIN entities_entities ee ON e.id = ee.parent_id
    LEFT JOIN entities e2 ON ee.child_id = e2.id
    LEFT JOIN entity_tags cet ON ee.child_id = cet.entity_id
    LEFT JOIN tags ett ON et.tag_id = ett.id
    LEFT JOIN tags cett ON cet.tag_id = cett.id
    LEFT JOIN LATERAL (
        SELECT
            key,
            value
        FROM jsonb_each(e.data)
        WHERE key IN (
            SELECT jsonb_object_keys(f.indexed_enums)
            FROM families_indexed_fields f
            WHERE f.family_id = c.family_id
        )
    ) AS transformed_fields ON true
    WHERE e.moderated
    GROUP BY e.id, c.family_id, e.display_name, e.category_id
)
-- Add the entities with their locations to the materialized view
SELECT
    md5(dl.entity_id::text || COALESCE(dl.location_index, -1)::text || 'alone_loc')::uuid AS id,
    ei.entity_id,
    ei.category_id,
    ei.display_name,
    ei.family_id,
    dl.location_index,
    (dl.value ->> 'long')::double precision AS longitude,
    (dl.value ->> 'lat')::double precision AS latitude,
    ST_Transform(ST_SetSRID(ST_MakePoint((dl.value ->> 'long')::double precision, (dl.value ->> 'lat')::double precision), 4326), 3857) AS web_mercator_location,
    dl.value ->> 'plain_text' AS plain_text_location,
    ei.tags_ids,
    NULL AS parent_id,
    NULL AS parent_display_name,
    ei.hidden,
    ei.display_name || ' ' || COALESCE(ei.indexed_string_values, '') || ' ' || COALESCE((dl.value ->> 'plain_text'), '') AS full_text_search_s,
    to_tsvector(ei.display_name || ' ' || COALESCE(ei.indexed_string_values, '') || ' ' || COALESCE((dl.value ->> 'plain_text'), '')) AS full_text_search_ts,
    ei.enums
FROM direct_locations dl
JOIN entities_information ei ON dl.entity_id = ei.entity_id

UNION

-- Add the entities with their parents locations to the materialized view
SELECT
    md5(tl.child_id::text || tl.parent_id::text || COALESCE(tl.location_index, -1)::text || 'with_parent')::uuid AS id,
    tl.child_id AS entity_id,
    ei.category_id,
    ei.display_name,
    ei.family_id,
    tl.location_index,
    (tl.value ->> 'long')::double precision AS longitude,
    (tl.value ->> 'lat')::double precision AS latitude,
    ST_Transform(ST_SetSRID(ST_MakePoint((tl.value ->> 'long')::double precision, (tl.value ->> 'lat')::double precision), 4326), 3857) AS web_mercator_location,
    tl.value ->> 'plain_text' AS plain_text_location,
    ei.tags_ids,
    tl.parent_id,
    tl.parent_display_name,
    ei.hidden,
    ei.display_name || ' ' || COALESCE(ei.indexed_string_values, '') || ' ' || COALESCE((tl.value ->> 'plain_text'), '') AS full_text_search_s,
    to_tsvector(ei.display_name || ' ' || COALESCE(ei.indexed_string_values, '') || ' ' || COALESCE((tl.value ->> 'plain_text'), '')) AS full_text_search_ts,
    ei.enums
FROM transitive_locations tl
JOIN entities_information ei ON tl.child_id = ei.entity_id;

-- Recreate unique index on ID for concurrency refresh
-- Copied as is from 20251119191120_fix_null_ids_in_entities_cache.sql
CREATE UNIQUE INDEX entities_caches_id_idx ON entities_caches(id);

-- Recreate indexes on the materialized view
-- Copied as is from 20251119191120_fix_null_ids_in_entities_cache.sql
CREATE INDEX entities_caches_entity_id_idx ON entities_caches(entity_id);
CREATE INDEX entities_caches_category_id_idx ON entities_caches(category_id);
CREATE INDEX entities_caches_family_id_idx ON entities_caches(family_id);
CREATE INDEX entities_caches_hidden_idx ON entities_caches (hidden);
CREATE INDEX entities_caches_enums_idx ON entities_caches USING GIN (enums);
CREATE INDEX entities_caches_gps_location_idx ON entities_caches USING GIST((ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)));
CREATE INDEX entities_caches_web_mercator_location_idx ON entities_caches USING GIST(web_mercator_location);
CREATE INDEX entities_caches_full_text_search_idx ON entities_caches USING GIST(full_text_search_ts);
CREATE INDEX entities_caches_display_name_gist_trgm ON entities_caches USING GIST(display_name gist_trgm_ops);

CREATE MATERIALIZED VIEW words AS SELECT word FROM ts_stat('SELECT to_tsvector(''simple'', full_text_search_s) FROM entities_caches');

CREATE OR REPLACE FUNCTION refresh_entities_caches() RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY entities_caches;
    REFRESH MATERIALIZED VIEW words;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION tsquery_or(state tsquery, value tsquery)
RETURNS tsquery
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT state || value
$$;

CREATE OR REPLACE AGGREGATE tsquery_or_agg(tsquery) (
    SFUNC = tsquery_or,
    STYPE = tsquery
);

CREATE OR REPLACE FUNCTION tsquery_and(state tsquery, value tsquery)
RETURNS tsquery
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT state && value
$$;

CREATE OR REPLACE AGGREGATE tsquery_and_agg(tsquery) (
    SFUNC = tsquery_and,
    STYPE = tsquery
);

-- Update the search_entities function to remove group by full_text_search_ts
CREATE OR REPLACE FUNCTION search_entities(
    search_query TEXT,
    geographic_restriction TEXT,
    input_family_id UUID,

    at_allow_all_categories BOOL,
    at_allow_all_tags BOOL,
    at_allowed_categories_ids  UUID[],
    at_allowed_tags_ids UUID[],
    at_excluded_categories_ids UUID[],
    at_excluded_tags_ids UUID[],

    current_page BIGINT,
    page_size BIGINT,

    user_active_categories_ids UUID[],
    user_required_tags_ids UUID[],
    user_excluded_tags_ids UUID[],

    require_locations BOOL,

    user_enum_constraints JSONB
) RETURNS TABLE (
    id UUID,
    entity_id UUID,
    category_id UUID,
    tags_ids UUID[],
    family_id UUID,
    display_name TEXT,
    parents JSONB,
    locations JSONB,
    total_results BIGINT,
    total_pages BIGINT,
    response_current_page BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH included_entities AS (
        SELECT ec.*
        FROM entities_caches ec
        WHERE
            -- Family filter
            ec.family_id = input_family_id
            -- Hidden filter
            AND NOT ec.hidden
            -- Access tokens blacklists
            AND NOT (ec.category_id = ANY(at_excluded_categories_ids))
            AND NOT (ec.tags_ids && at_excluded_tags_ids)
            -- User filters blacklists
            AND NOT (ec.tags_ids && user_excluded_tags_ids)
    ),
    search_terms AS (
        SELECT *
        FROM string_to_table(search_query, ' ')
        AS term
    ),
    search_words AS (
        SELECT term, to_tsquery(word) AS tsquery
        FROM words, search_terms
        WHERE term <% word
        GROUP BY term, tsquery
    ),
    ts_search_query_tmp AS (
        SELECT tsquery_or_agg(tsquery) AS tsquery FROM search_words GROUP BY term
    ),
    ts_search_query AS (
        SELECT tsquery_and_agg(tsquery) AS tsquery FROM ts_search_query_tmp
    ),
    filtered_entities AS (
        SELECT
            ie.*,
            CASE
                WHEN search_query IS NOT NULL AND search_query <> '' AND
                    (ie.display_name ILIKE '%' || lower(search_query) || '%')
                THEN 1 ELSE 0
            END AS exact_match_score,
            CASE
                WHEN search_query IS NOT NULL AND search_query <> '' THEN
                    ts_rank(full_text_search_ts, tsquery)
                ELSE 0
            END AS rank
        FROM included_entities ie, ts_search_query
        WHERE
            (
                search_query IS NULL OR search_query = '' OR (
                    ie.display_name ILIKE '%' || lower(search_query) || '%'
                        OR (full_text_search_ts @@ tsquery)
                    )
            )
            AND (
                geographic_restriction IS NULL OR
                ST_Intersects(ie.web_mercator_location, st_geomfromtext(geographic_restriction))
            )
            AND ie.family_id = input_family_id
            AND NOT ie.hidden
            -- Categories
            AND (at_allow_all_categories OR ie.category_id = ANY(at_allowed_categories_ids))
            -- Tags
            AND (at_allow_all_tags OR (ie.tags_ids && at_allowed_tags_ids))
            -- User filters
            AND (ie.category_id = ANY(user_active_categories_ids))
            AND (array_length(user_required_tags_ids, 1) = 0 OR user_required_tags_ids <@ ie.tags_ids)
            -- Enum constraints
            AND (
                user_enum_constraints IS NULL OR
                user_enum_constraints = '{}'::jsonb OR
                (
                    SELECT bool_and(
                        ie.enums->key ?| array(SELECT jsonb_array_elements_text(value))
                    )
                    FROM jsonb_each(user_enum_constraints) AS constraints(key, value)
                    WHERE key IS NOT NULL AND ie.enums ? key
                )
            )
    ),
    aggregated_entities AS (
        SELECT
            fe.entity_id,
            fe.category_id,
            fe.tags_ids,
            fe.family_id,
            fe.display_name,
            COALESCE (
                jsonb_agg(
                    DISTINCT jsonb_build_object(
                        'id', fe.parent_id,
                        'display_name', fe.parent_display_name
                    )
                ) FILTER (
                    WHERE fe.parent_id IS NOT NULL
                        AND fe.parent_id IS NOT NULL
                        AND fe.parent_display_name IS NOT NULL
                ),
                '[]'::jsonb
            ) AS parents,
            COALESCE (
                jsonb_agg(
                    DISTINCT jsonb_build_object(
                        'x', ST_X(fe.web_mercator_location),
                        'y', ST_Y(fe.web_mercator_location),
                        'plain_text', fe.plain_text_location
                    )
                ) FILTER (
                    WHERE web_mercator_location IS NOT NULL
                        AND fe.plain_text_location IS NOT NULL),
                '[]'::jsonb
            ) AS locations,
            fe.exact_match_score,
            MAX(rank) AS rank
        FROM filtered_entities fe
        GROUP BY
            fe.entity_id,
            fe.category_id,
            fe.tags_ids,
            fe.family_id,
            fe.display_name,
            fe.exact_match_score
    ),
    ranked_entities AS (
        SELECT
            ae.*,
            RANK() OVER (
                ORDER BY
                exact_match_score DESC,
                ae.rank DESC,
                ae.display_name ASC
            ) AS rank
        FROM aggregated_entities ae
        WHERE ((NOT require_locations) OR jsonb_array_length(ae.locations) > 0)
    ),
    total_count AS (
        SELECT COUNT(*) AS total_results FROM ranked_entities
    ),
    paginated_results AS (
        SELECT
            re.entity_id AS id,
            re.entity_id,
            re.category_id,
            re.tags_ids,
            re.family_id,
            re.display_name,
            re.parents,
            re.locations,
            tc.total_results,
            CEIL(tc.total_results / page_size::FLOAT)::BIGINT AS total_pages,
            current_page as response_current_page
        FROM ranked_entities re, total_count tc
        LIMIT page_size
        OFFSET (current_page - 1) * page_size
    )
    SELECT * FROM paginated_results;
END;
$$ LANGUAGE plpgsql;
