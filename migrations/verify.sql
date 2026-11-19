-- Проверка без изменения данных и чтения file_data.
-- Ожидается: 4 таблицы, 42 поля, 4 ALWAYS IDENTITY, 8 FK с RESTRICT.
-- DEFAULT сверяются с точными выражениями начальной миграции.
-- Ошибка P0001 останавливает psql при ON_ERROR_STOP=1.
-- Для CHECK сверяются имена и convalidated, определения выводятся в отчёте.
BEGIN READ ONLY;
SET LOCAL search_path = pg_catalog, public;

DO $verify$
DECLARE
    mismatch text;
BEGIN
    IF to_regclass('public.grades') IS NOT NULL
       OR to_regclass('public.submission_files') IS NOT NULL THEN
        RAISE EXCEPTION 'MVP schema mismatch: legacy grades/submission_files relations are present';
    END IF;

    WITH expected(table_name, column_name, data_type, not_null, identity_kind) AS (
        VALUES
            ('users', 'id', 'integer', true, 'a'),
            ('users', 'full_name', 'text', true, ''),
            ('users', 'login', 'text', true, ''),
            ('users', 'email', 'text', true, ''),
            ('users', 'password_hash', 'text', true, ''),
            ('users', 'is_active', 'boolean', true, ''),
            ('users', 'created_at', 'timestamp with time zone', true, ''),
            ('users', 'role', 'text', true, ''),
            ('users', 'group_id', 'integer', false, ''),
            ('groups', 'id', 'integer', true, 'a'),
            ('groups', 'name', 'text', true, ''),
            ('groups', 'description', 'text', true, ''),
            ('groups', 'start_date', 'date', true, ''),
            ('groups', 'end_date', 'date', true, ''),
            ('groups', 'curator_id', 'integer', true, ''),
            ('assignments', 'id', 'integer', true, 'a'),
            ('assignments', 'curator_id', 'integer', true, ''),
            ('assignments', 'title', 'text', true, ''),
            ('assignments', 'description', 'text', false, ''),
            ('assignments', 'type', 'text', true, ''),
            ('assignments', 'deadline', 'timestamp with time zone', false, ''),
            ('assignments', 'criteria', 'text', false, ''),
            ('assignments', 'status', 'text', true, ''),
            ('assignments', 'created_at', 'timestamp with time zone', true, ''),
            ('assignments', 'published_at', 'timestamp with time zone', false, ''),
            ('assignments', 'group_id', 'integer', false, ''),
            ('assignments', 'student_id', 'integer', false, ''),
            ('submissions', 'id', 'integer', true, 'a'),
            ('submissions', 'assignment_id', 'integer', true, ''),
            ('submissions', 'student_id', 'integer', true, ''),
            ('submissions', 'status', 'text', true, ''),
            ('submissions', 'submitted_at', 'timestamp with time zone', true, ''),
            ('submissions', 'original_name', 'text', true, ''),
            ('submissions', 'file_data', 'bytea', true, ''),
            ('submissions', 'mime_type', 'text', true, ''),
            ('submissions', 'size_bytes', 'bigint', true, ''),
            ('submissions', 'curator_id', 'integer', true, ''),
            ('submissions', 'score', 'integer', false, ''),
            ('submissions', 'feedback', 'text', false, ''),
            ('submissions', 'decision', 'text', false, ''),
            ('submissions', 'graded_at', 'timestamp with time zone', false, ''),
            ('submissions', 'result_published_at', 'timestamp with time zone', false, '')
    ), actual AS (
        SELECT c.relname AS table_name, a.attname AS column_name,
               format_type(a.atttypid, a.atttypmod) AS data_type,
               a.attnotnull AS not_null, a.attidentity::text AS identity_kind
        FROM pg_attribute AS a
        JOIN pg_class AS c ON c.oid = a.attrelid
        JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
          AND c.relname IN ('users', 'groups', 'assignments', 'submissions')
          AND a.attnum > 0 AND NOT a.attisdropped
    )
    SELECT string_agg(
        coalesce(e.table_name, a.table_name) || '.' || coalesce(e.column_name, a.column_name),
        ', ' ORDER BY coalesce(e.table_name, a.table_name), coalesce(e.column_name, a.column_name)
    ) INTO mismatch
    FROM expected AS e
    FULL JOIN actual AS a USING (table_name, column_name)
    WHERE e.data_type IS DISTINCT FROM a.data_type
       OR e.not_null IS DISTINCT FROM a.not_null
       OR e.identity_kind IS DISTINCT FROM a.identity_kind;
    IF mismatch IS NOT NULL THEN
        RAISE EXCEPTION 'MVP schema mismatch: missing/extra column, type, NULL or IDENTITY at %', mismatch;
    END IF;

    -- pg_attrdef читается как метаданные: выражения DEFAULT не выполняются.
    -- FULL JOIN также обнаруживает DEFAULT у полей, где он не предусмотрен.
    WITH expected(table_name, column_name, default_expression) AS (
        VALUES
            ('users', 'is_active', 'true'),
            ('users', 'created_at', 'CURRENT_TIMESTAMP'),
            ('groups', 'description', $default$''::text$default$),
            ('assignments', 'type', $default$'task'::text$default$),
            ('assignments', 'status', $default$'draft'::text$default$),
            ('assignments', 'created_at', 'CURRENT_TIMESTAMP'),
            ('submissions', 'status', $default$'submitted'::text$default$),
            ('submissions', 'submitted_at', 'CURRENT_TIMESTAMP')
    ), actual AS (
        SELECT t.relname AS table_name, a.attname AS column_name,
               pg_get_expr(d.adbin, d.adrelid, false) AS default_expression,
               a.attgenerated::text AS generated_kind
        FROM pg_attrdef AS d
        JOIN pg_class AS t ON t.oid = d.adrelid
        JOIN pg_namespace AS n ON n.oid = t.relnamespace
        JOIN pg_attribute AS a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
        WHERE n.nspname = 'public' AND t.relkind IN ('r', 'p')
          AND t.relname IN ('users', 'groups', 'assignments', 'submissions')
          AND a.attnum > 0 AND NOT a.attisdropped
    )
    SELECT string_agg(
        coalesce(e.table_name, a.table_name) || '.' || coalesce(e.column_name, a.column_name),
        ', ' ORDER BY coalesce(e.table_name, a.table_name), coalesce(e.column_name, a.column_name)
    ) INTO mismatch
    FROM expected AS e
    FULL JOIN actual AS a USING (table_name, column_name)
    WHERE e.default_expression IS DISTINCT FROM a.default_expression
       OR (a.generated_kind IS NOT NULL AND a.generated_kind <> '');
    IF mismatch IS NOT NULL THEN
        RAISE EXCEPTION 'MVP schema mismatch: missing, unexpected or changed DEFAULT at %', mismatch;
    END IF;

    WITH expected(table_name, constraint_name, column_name, referenced_table, referenced_column) AS (
        VALUES
            ('users', 'users_group_fk', 'group_id', 'groups', 'id'),
            ('groups', 'groups_curator_fk', 'curator_id', 'users', 'id'),
            ('assignments', 'assignments_curator_fk', 'curator_id', 'users', 'id'),
            ('assignments', 'assignments_group_fk', 'group_id', 'groups', 'id'),
            ('assignments', 'assignments_student_fk', 'student_id', 'users', 'id'),
            ('submissions', 'submissions_assignment_fk', 'assignment_id', 'assignments', 'id'),
            ('submissions', 'submissions_student_fk', 'student_id', 'users', 'id'),
            ('submissions', 'submissions_curator_fk', 'curator_id', 'users', 'id')
    ), actual AS (
        SELECT source.relname AS table_name, c.conname AS constraint_name,
               source_column.attname AS column_name, target.relname AS referenced_table,
               target_column.attname AS referenced_column, target_ns.nspname AS referenced_schema,
               c.confdeltype, c.confupdtype, c.convalidated, c.condeferrable,
               cardinality(c.conkey) AS key_count, cardinality(c.confkey) AS target_key_count
        FROM pg_constraint AS c
        JOIN pg_class AS source ON source.oid = c.conrelid
        JOIN pg_namespace AS source_ns ON source_ns.oid = source.relnamespace
        JOIN pg_class AS target ON target.oid = c.confrelid
        JOIN pg_namespace AS target_ns ON target_ns.oid = target.relnamespace
        JOIN pg_attribute AS source_column ON source_column.attrelid = source.oid
                                          AND source_column.attnum = c.conkey[1]
        JOIN pg_attribute AS target_column ON target_column.attrelid = target.oid
                                          AND target_column.attnum = c.confkey[1]
        WHERE c.contype = 'f' AND source_ns.nspname = 'public'
          AND source.relname IN ('users', 'groups', 'assignments', 'submissions')
    )
    SELECT string_agg(coalesce(e.constraint_name, a.constraint_name), ', ')
    INTO mismatch
    FROM expected AS e
    FULL JOIN actual AS a USING (table_name, constraint_name)
    WHERE e.column_name IS DISTINCT FROM a.column_name
       OR e.referenced_table IS DISTINCT FROM a.referenced_table
       OR e.referenced_column IS DISTINCT FROM a.referenced_column
       OR a.referenced_schema IS DISTINCT FROM 'public'
       OR a.confdeltype IS DISTINCT FROM 'r'::"char"
       OR a.confupdtype IS DISTINCT FROM 'r'::"char"
       OR a.convalidated IS DISTINCT FROM true
       OR a.condeferrable IS DISTINCT FROM false
       OR a.key_count IS DISTINCT FROM 1
       OR a.target_key_count IS DISTINCT FROM 1;
    IF mismatch IS NOT NULL THEN
        RAISE EXCEPTION 'MVP schema mismatch: foreign key definition at %', mismatch;
    END IF;

    WITH expected(table_name, constraint_name, kind, column_names) AS (
        VALUES
            ('users', 'users_pkey', 'p', ARRAY['id']),
            ('groups', 'groups_pkey', 'p', ARRAY['id']),
            ('assignments', 'assignments_pkey', 'p', ARRAY['id']),
            ('submissions', 'submissions_pkey', 'p', ARRAY['id']),
            ('submissions', 'submissions_assignment_student_unique', 'u', ARRAY['assignment_id', 'student_id'])
    ), actual AS (
        SELECT t.relname AS table_name, c.conname AS constraint_name, c.contype::text AS kind,
               ARRAY(
                   SELECT a.attname::text
                   FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, position)
                   JOIN pg_attribute AS a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
                   ORDER BY k.position
               ) AS column_names,
               c.convalidated, c.condeferrable, i.indisvalid, i.indisready
        FROM pg_constraint AS c
        JOIN pg_class AS t ON t.oid = c.conrelid
        JOIN pg_namespace AS n ON n.oid = t.relnamespace
        JOIN pg_index AS i ON i.indexrelid = c.conindid
        WHERE n.nspname = 'public' AND c.contype IN ('p', 'u')
          AND t.relname IN ('users', 'groups', 'assignments', 'submissions')
    )
    SELECT string_agg(coalesce(e.constraint_name, a.constraint_name), ', ')
    INTO mismatch
    FROM expected AS e
    FULL JOIN actual AS a USING (table_name, constraint_name)
    WHERE e.kind IS DISTINCT FROM a.kind
       OR e.column_names IS DISTINCT FROM a.column_names
       OR a.convalidated IS DISTINCT FROM true
       OR a.condeferrable IS DISTINCT FROM false
       OR a.indisvalid IS DISTINCT FROM true
       OR a.indisready IS DISTINCT FROM true;
    IF mismatch IS NOT NULL THEN
        RAISE EXCEPTION 'MVP schema mismatch: primary/unique key definition at %', mismatch;
    END IF;

    WITH expected(table_name, constraint_name) AS (
        VALUES
            ('users', 'users_full_name_nonempty'),
            ('users', 'users_login_nonempty'),
            ('users', 'users_email_nonempty'),
            ('users', 'users_password_hash_nonempty'),
            ('users', 'users_role_allowed'),
            ('users', 'users_role_group_consistent'),
            ('groups', 'groups_name_nonempty'),
            ('groups', 'groups_dates_ordered'),
            ('assignments', 'assignments_title_nonempty'),
            ('assignments', 'assignments_type_allowed'),
            ('assignments', 'assignments_status_allowed'),
            ('assignments', 'assignments_at_most_one_recipient'),
            ('assignments', 'assignments_publication_complete'),
            ('assignments', 'assignments_publication_time'),
            ('submissions', 'submissions_status_allowed'),
            ('submissions', 'submissions_original_name_nonempty'),
            ('submissions', 'submissions_mime_type_nonempty'),
            ('submissions', 'submissions_file_size_matches'),
            ('submissions', 'submissions_file_size_allowed'),
            ('submissions', 'submissions_score_nonnegative'),
            ('submissions', 'submissions_decision_consistent'),
            ('submissions', 'submissions_result_state_consistent'),
            ('submissions', 'submissions_grading_time'),
            ('submissions', 'submissions_result_publication_time')
    )
    SELECT string_agg(e.constraint_name, ', ') INTO mismatch
    FROM expected AS e
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_constraint AS c
        JOIN pg_class AS t ON t.oid = c.conrelid
        JOIN pg_namespace AS n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public' AND t.relname = e.table_name
          AND c.conname = e.constraint_name AND c.contype = 'c' AND c.convalidated
    );
    IF mismatch IS NOT NULL THEN
        RAISE EXCEPTION 'MVP schema mismatch: missing or unvalidated CHECK at %', mismatch;
    END IF;

    WITH expected(table_name, index_name, unique_index, expression, column_names) AS (
        VALUES
            ('users', 'users_login_ci_uq', true, 'lower(btrim(login))', ARRAY[]::text[]),
            ('users', 'users_email_ci_uq', true, 'lower(btrim(email))', ARRAY[]::text[]),
            ('users', 'users_group_idx', false, NULL, ARRAY['group_id']),
            ('groups', 'groups_curator_idx', false, NULL, ARRAY['curator_id']),
            ('assignments', 'assignments_group_status_deadline_idx', false, NULL, ARRAY['group_id', 'status', 'deadline']),
            ('assignments', 'assignments_student_status_deadline_idx', false, NULL, ARRAY['student_id', 'status', 'deadline']),
            ('assignments', 'assignments_curator_idx', false, NULL, ARRAY['curator_id']),
            ('submissions', 'submissions_student_status_idx', false, NULL, ARRAY['student_id', 'status']),
            ('submissions', 'submissions_curator_status_idx', false, NULL, ARRAY['curator_id', 'status'])
    ), actual AS (
        SELECT t.relname AS table_name, idx.relname AS index_name, i.indisunique AS unique_index,
               pg_get_expr(i.indexprs, i.indrelid) AS expression,
               ARRAY(
                   SELECT a.attname::text
                   FROM unnest(i.indkey) WITH ORDINALITY AS k(attnum, position)
                   JOIN pg_attribute AS a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
                   WHERE k.position <= i.indnkeyatts ORDER BY k.position
               ) AS column_names,
               i.indisvalid, i.indisready, i.indnkeyatts, i.indnatts,
               i.indpred IS NULL AS unconditional, am.amname AS method
        FROM pg_index AS i
        JOIN pg_class AS idx ON idx.oid = i.indexrelid
        JOIN pg_class AS t ON t.oid = i.indrelid
        JOIN pg_namespace AS n ON n.oid = t.relnamespace
        JOIN pg_am AS am ON am.oid = idx.relam
        WHERE n.nspname = 'public'
    )
    SELECT string_agg(e.index_name, ', ') INTO mismatch
    FROM expected AS e LEFT JOIN actual AS a USING (table_name, index_name)
    WHERE e.unique_index IS DISTINCT FROM a.unique_index
       OR e.expression IS DISTINCT FROM a.expression
       OR e.column_names IS DISTINCT FROM a.column_names
       OR a.indisvalid IS DISTINCT FROM true
       OR a.indisready IS DISTINCT FROM true
       OR a.unconditional IS DISTINCT FROM true
       OR a.method IS DISTINCT FROM 'btree'
       OR a.indnkeyatts IS DISTINCT FROM
          CASE WHEN e.expression IS NULL THEN cardinality(e.column_names) ELSE 1 END
       OR a.indnatts IS DISTINCT FROM a.indnkeyatts;
    IF mismatch IS NOT NULL THEN
        RAISE EXCEPTION 'MVP schema mismatch: missing or incorrect index at %', mismatch;
    END IF;
END
$verify$;

SELECT table_name, count(*) AS column_count
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('users', 'groups', 'assignments', 'submissions')
GROUP BY table_name
ORDER BY table_name;

SELECT table_name, column_name, data_type, is_nullable, identity_generation, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('users', 'groups', 'assignments', 'submissions')
ORDER BY table_name, ordinal_position;

SELECT c.conrelid::regclass AS table_name, c.conname, pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint AS c
WHERE c.connamespace = 'public'::regnamespace AND c.contype IN ('p', 'u', 'f', 'c')
  AND c.conrelid IN ('public.users'::regclass, 'public.groups'::regclass,
                    'public.assignments'::regclass, 'public.submissions'::regclass)
ORDER BY c.conrelid::regclass::text, c.conname;

SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('users', 'groups', 'assignments', 'submissions')
ORDER BY tablename, indexname;

COMMIT;
