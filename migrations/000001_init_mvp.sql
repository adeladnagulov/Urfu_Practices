-- +goose Up
-- MVP, 10.11.2026: 4 tables, 44 columns, 8 foreign keys.
-- The application checks user roles, workflow transitions, file contents,
-- and the score against the assignment maximum.

CREATE TABLE public.users (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name text NOT NULL,
    login text NOT NULL,
    email text NOT NULL,
    password_hash text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    role text NOT NULL,
    group_id integer,

    CONSTRAINT users_full_name_nonempty CHECK (full_name ~ '[^[:space:]]'),
    CONSTRAINT users_login_nonempty CHECK (btrim(login) <> ''),
    CONSTRAINT users_email_nonempty CHECK (btrim(email) <> ''),
    CONSTRAINT users_password_hash_nonempty CHECK (btrim(password_hash) <> ''),
    CONSTRAINT users_role_allowed CHECK (role IN ('student', 'curator', 'admin')),
    CONSTRAINT users_role_group_consistent CHECK (
        (role = 'student' AND group_id IS NOT NULL)
        OR (role IN ('curator', 'admin') AND group_id IS NULL)
    )
);

-- Уникальность по тому же выражению, которое должен использовать вход.
CREATE UNIQUE INDEX users_login_ci_uq ON public.users (lower(btrim(login)));
CREATE UNIQUE INDEX users_email_ci_uq ON public.users (lower(btrim(email)));

CREATE TABLE public.groups (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL,
    description text NOT NULL DEFAULT '',
    start_date date NOT NULL,
    end_date date NOT NULL,
    curator_id integer NOT NULL,

    CONSTRAINT groups_name_nonempty CHECK (name ~ '[^[:space:]]'),
    CONSTRAINT groups_dates_ordered CHECK (end_date >= start_date),
    CONSTRAINT groups_curator_fk FOREIGN KEY (curator_id)
        REFERENCES public.users (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);

-- Цикл DDL разрывается ALTER TABLE. Данные: куратор -> группа -> студент.
ALTER TABLE public.users
    ADD CONSTRAINT users_group_fk FOREIGN KEY (group_id)
        REFERENCES public.groups (id) ON UPDATE RESTRICT ON DELETE RESTRICT;

CREATE TABLE public.assignments (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    curator_id integer NOT NULL,
    title text NOT NULL,
    description text,
    type text NOT NULL DEFAULT 'task',
    deadline timestamptz,
    max_score integer,
    criteria text,
    status text NOT NULL DEFAULT 'draft',
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at timestamptz,
    group_id integer,
    student_id integer,

    CONSTRAINT assignments_curator_fk FOREIGN KEY (curator_id)
        REFERENCES public.users (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT assignments_group_fk FOREIGN KEY (group_id)
        REFERENCES public.groups (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT assignments_student_fk FOREIGN KEY (student_id)
        REFERENCES public.users (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT assignments_title_nonempty CHECK (title ~ '[^[:space:]]'),
    CONSTRAINT assignments_type_allowed CHECK (type IN ('task', 'report')),
    CONSTRAINT assignments_max_score_positive CHECK (max_score > 0),
    CONSTRAINT assignments_status_allowed CHECK (status IN ('draft', 'published')),
    CONSTRAINT assignments_at_most_one_recipient CHECK (
        group_id IS NULL OR student_id IS NULL
    ),
    CONSTRAINT assignments_publication_complete CHECK (
        (status = 'draft' AND published_at IS NULL)
        OR (
            status = 'published'
            AND published_at IS NOT NULL
            AND (group_id IS NOT NULL OR student_id IS NOT NULL)
            AND description IS NOT NULL AND description ~ '[^[:space:]]'
            AND deadline IS NOT NULL
            AND max_score IS NOT NULL
            AND criteria IS NOT NULL AND criteria ~ '[^[:space:]]'
        )
    ),
    CONSTRAINT assignments_publication_time CHECK (
        published_at IS NULL OR published_at >= created_at
    )
);

CREATE TABLE public.submissions (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assignment_id integer NOT NULL,
    student_id integer NOT NULL,
    status text NOT NULL DEFAULT 'submitted',
    submitted_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    original_name text NOT NULL,
    file_data bytea NOT NULL,
    mime_type text NOT NULL,
    size_bytes bigint NOT NULL,
    uploaded_at timestamptz NOT NULL,
    curator_id integer,
    score integer,
    feedback text,
    decision text,
    graded_at timestamptz,
    published_at timestamptz,

    CONSTRAINT submissions_assignment_fk FOREIGN KEY (assignment_id)
        REFERENCES public.assignments (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT submissions_student_fk FOREIGN KEY (student_id)
        REFERENCES public.users (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT submissions_curator_fk FOREIGN KEY (curator_id)
        REFERENCES public.users (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT submissions_assignment_student_unique UNIQUE (assignment_id, student_id),
    CONSTRAINT submissions_status_allowed CHECK (
        status IN ('submitted', 'under_review', 'revision_required', 'graded')
    ),
    CONSTRAINT submissions_original_name_nonempty CHECK (original_name ~ '[^[:space:]]'),
    CONSTRAINT submissions_mime_type_nonempty CHECK (mime_type ~ '[^[:space:]]'),
    CONSTRAINT submissions_file_size_matches CHECK (size_bytes = octet_length(file_data)),
    CONSTRAINT submissions_file_size_allowed CHECK (
        octet_length(file_data) BETWEEN 1 AND 20000000
    ),
    CONSTRAINT submissions_score_nonnegative CHECK (score IS NULL OR score >= 0),
    -- CASE и IS NOT NULL не дают SQL UNKNOWN обойти обязательность результата.
    CONSTRAINT submissions_decision_consistent CHECK (
        CASE
            WHEN decision IS NULL THEN
                score IS NULL AND feedback IS NULL AND graded_at IS NULL
            WHEN decision = 'accepted' THEN
                score IS NOT NULL AND graded_at IS NOT NULL
            WHEN decision = 'revision_required' THEN
                graded_at IS NOT NULL
                AND feedback IS NOT NULL AND feedback ~ '[^[:space:]]'
            ELSE false
        END
    ),
    CONSTRAINT submissions_result_state_consistent CHECK (
        CASE status
            WHEN 'submitted' THEN
                curator_id IS NULL AND score IS NULL AND feedback IS NULL AND decision IS NULL
                AND graded_at IS NULL AND published_at IS NULL
            WHEN 'under_review' THEN
                curator_id IS NOT NULL AND published_at IS NULL
            WHEN 'graded' THEN
                curator_id IS NOT NULL AND decision IS NOT NULL AND decision = 'accepted'
                AND published_at IS NOT NULL
            WHEN 'revision_required' THEN
                curator_id IS NOT NULL AND decision IS NOT NULL AND decision = 'revision_required'
                AND published_at IS NOT NULL
            ELSE false
        END
    ),
    CONSTRAINT submissions_upload_time CHECK (uploaded_at <= submitted_at),
    CONSTRAINT submissions_grading_time CHECK (
        graded_at IS NULL OR graded_at >= submitted_at
    ),
    CONSTRAINT submissions_result_publication_time CHECK (
        published_at IS NULL
        OR (graded_at IS NOT NULL AND published_at >= graded_at)
    )
);

CREATE INDEX users_group_idx ON public.users (group_id);
CREATE INDEX groups_curator_idx ON public.groups (curator_id);
CREATE INDEX assignments_group_status_deadline_idx
    ON public.assignments (group_id, status, deadline);
CREATE INDEX assignments_student_status_deadline_idx
    ON public.assignments (student_id, status, deadline);
CREATE INDEX assignments_curator_idx ON public.assignments (curator_id);
CREATE INDEX submissions_student_status_idx ON public.submissions (student_id, status);
CREATE INDEX submissions_curator_status_idx ON public.submissions (curator_id, status);

-- +goose Down

DROP TABLE public.submissions;
DROP TABLE public.assignments;
ALTER TABLE public.users DROP CONSTRAINT users_group_fk;
DROP TABLE public.groups;
DROP TABLE public.users;
