CREATE SCHEMA university;
SET search_path TO university, public;

CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    role_id INT NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(120) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE faculties (
    id SERIAL PRIMARY KEY,
    code VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(150) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by INT REFERENCES users(id) ON DELETE SET NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ
);

CREATE TABLE departments (
    id SERIAL PRIMARY KEY,
    faculty_id INT NOT NULL REFERENCES faculties(id) ON DELETE RESTRICT,
    code VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(150) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by INT REFERENCES users(id) ON DELETE SET NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ
);

CREATE TABLE specialties (
    id SERIAL PRIMARY KEY,
    code VARCHAR(10) UNIQUE NOT NULL,
    name VARCHAR(150) NOT NULL,
    degree_level VARCHAR(30) NOT NULL CHECK (degree_level IN ('Bachelor', 'Master', 'PhD'))
);

CREATE TABLE teachers (
    id SERIAL PRIMARY KEY,
    user_id INT UNIQUE REFERENCES users(id) ON DELETE SET NULL,
    department_id INT NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
    first_name VARCHAR(60) NOT NULL,
    last_name VARCHAR(60) NOT NULL,
    academic_degree VARCHAR(60),
    position VARCHAR(60) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by INT REFERENCES users(id) ON DELETE SET NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ
);

CREATE TABLE study_groups (
    id SERIAL PRIMARY KEY,
    department_id INT NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
    specialty_id INT NOT NULL REFERENCES specialties(id) ON DELETE RESTRICT,
    curator_id INT REFERENCES teachers(id) ON DELETE SET NULL,
    code VARCHAR(20) UNIQUE NOT NULL,
    enrollment_year INT NOT NULL CHECK (enrollment_year >= 2000),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ
);

CREATE TABLE students (
    id SERIAL PRIMARY KEY,
    user_id INT UNIQUE REFERENCES users(id) ON DELETE SET NULL,
    group_id INT NOT NULL REFERENCES study_groups(id) ON DELETE RESTRICT,
    student_card_no VARCHAR(30) UNIQUE NOT NULL,
    first_name VARCHAR(60) NOT NULL,
    last_name VARCHAR(60) NOT NULL,
    birth_date DATE NOT NULL,
    funding_type VARCHAR(20) NOT NULL CHECK (funding_type IN ('state', 'contract')),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'academic_leave', 'expelled', 'graduated')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by INT REFERENCES users(id) ON DELETE SET NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ
);

CREATE TABLE courses (
    id SERIAL PRIMARY KEY,
    department_id INT NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
    code VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(150) NOT NULL,
    credits_ects NUMERIC(3,1) NOT NULL CHECK (credits_ects > 0),
    hours_total INT NOT NULL CHECK (hours_total > 0),
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by INT REFERENCES users(id) ON DELETE SET NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ
);

CREATE TABLE semesters (
    id SERIAL PRIMARY KEY,
    academic_year VARCHAR(9) NOT NULL,
    term_number SMALLINT NOT NULL CHECK (term_number IN (1, 2)),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    is_current BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (academic_year, term_number),
    CHECK (end_date > start_date)
);

CREATE TABLE course_offerings (
    id SERIAL PRIMARY KEY,
    course_id INT NOT NULL REFERENCES courses(id) ON DELETE RESTRICT,
    semester_id INT NOT NULL REFERENCES semesters(id) ON DELETE RESTRICT,
    teacher_id INT NOT NULL REFERENCES teachers(id) ON DELETE RESTRICT,
    max_students INT NOT NULL DEFAULT 100 CHECK (max_students > 0),
    UNIQUE (course_id, semester_id, teacher_id)
);

CREATE TABLE enrollments (
    id SERIAL PRIMARY KEY,
    student_id INT NOT NULL REFERENCES students(id) ON DELETE RESTRICT,
    offering_id INT NOT NULL REFERENCES course_offerings(id) ON DELETE RESTRICT,
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status VARCHAR(20) NOT NULL DEFAULT 'enrolled' CHECK (status IN ('enrolled', 'completed', 'dropped')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by INT REFERENCES users(id) ON DELETE SET NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ,
    UNIQUE (student_id, offering_id)
);

CREATE TABLE grades (
    id SERIAL PRIMARY KEY,
    enrollment_id INT UNIQUE NOT NULL REFERENCES enrollments(id) ON DELETE RESTRICT,
    score NUMERIC(5,2) NOT NULL CHECK (score >= 0 AND score <= 100),
    ects_grade VARCHAR(2) NOT NULL,
    graded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by INT REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE buildings (
    id SERIAL PRIMARY KEY,
    code VARCHAR(10) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    address VARCHAR(255) NOT NULL
);

CREATE TABLE classrooms (
    id SERIAL PRIMARY KEY,
    building_id INT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
    room_number VARCHAR(20) NOT NULL,
    capacity INT NOT NULL CHECK (capacity > 0),
    room_type VARCHAR(30) NOT NULL CHECK (room_type IN ('lecture', 'lab', 'seminar')),
    UNIQUE (building_id, room_number)
);

CREATE TABLE schedule_slots (
    id SERIAL PRIMARY KEY,
    offering_id INT NOT NULL REFERENCES course_offerings(id) ON DELETE CASCADE,
    group_id INT NOT NULL REFERENCES study_groups(id) ON DELETE CASCADE,
    classroom_id INT NOT NULL REFERENCES classrooms(id) ON DELETE RESTRICT,
    day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 1 AND 6),
    pair_number SMALLINT NOT NULL CHECK (pair_number BETWEEN 1 AND 8),
    lesson_type VARCHAR(20) NOT NULL CHECK (lesson_type IN ('lecture', 'lab', 'practical')),
    UNIQUE (classroom_id, day_of_week, pair_number)
);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(60) NOT NULL,
    record_id INT NOT NULL,
    operation VARCHAR(20) NOT NULL,
    old_values JSONB,
    new_values JSONB,
    changed_by INT REFERENCES users(id) ON DELETE SET NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);