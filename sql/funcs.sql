SET search_path TO university, public;

CREATE OR REPLACE FUNCTION fn_get_current_user_id()
RETURNS INT AS $$
DECLARE
    v_user_id TEXT;
BEGIN
    v_user_id := current_setting('app.current_user_id', true);
    IF v_user_id IS NULL OR v_user_id = '' THEN
        RETURN NULL;
    END IF;
    RETURN v_user_id::INT;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_fn_set_audit_fields()
RETURNS TRIGGER AS $$
DECLARE
    v_actor_id INT;
BEGIN
    NEW.updated_at := NOW();
    v_actor_id := fn_get_current_user_id();
    IF v_actor_id IS NOT NULL THEN
        NEW.updated_by := v_actor_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_faculties_audit BEFORE INSERT OR UPDATE ON faculties
FOR EACH ROW EXECUTE FUNCTION trg_fn_set_audit_fields();

CREATE TRIGGER trg_departments_audit BEFORE INSERT OR UPDATE ON departments
FOR EACH ROW EXECUTE FUNCTION trg_fn_set_audit_fields();

CREATE TRIGGER trg_students_audit BEFORE INSERT OR UPDATE ON students
FOR EACH ROW EXECUTE FUNCTION trg_fn_set_audit_fields();

CREATE TRIGGER trg_teachers_audit BEFORE INSERT OR UPDATE ON teachers
FOR EACH ROW EXECUTE FUNCTION trg_fn_set_audit_fields();

CREATE TRIGGER trg_courses_audit BEFORE INSERT OR UPDATE ON courses
FOR EACH ROW EXECUTE FUNCTION trg_fn_set_audit_fields();

CREATE TRIGGER trg_enrollments_audit BEFORE INSERT OR UPDATE ON enrollments
FOR EACH ROW EXECUTE FUNCTION trg_fn_set_audit_fields();

CREATE TRIGGER trg_grades_audit BEFORE INSERT OR UPDATE ON grades
FOR EACH ROW EXECUTE FUNCTION trg_fn_set_audit_fields();

CREATE OR REPLACE FUNCTION trg_fn_log_entity_changes()
RETURNS TRIGGER AS $$
DECLARE
    v_op VARCHAR(20);
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_logs(table_name, record_id, operation, old_values, new_values, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', NULL, to_jsonb(NEW), fn_get_current_user_id());
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF (OLD.is_deleted = FALSE AND NEW.is_deleted = TRUE) THEN
            v_op := 'SOFT_DELETE';
        ELSE
            v_op := 'UPDATE';
        END IF;
        INSERT INTO audit_logs(table_name, record_id, operation, old_values, new_values, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, v_op, to_jsonb(OLD), to_jsonb(NEW), fn_get_current_user_id());
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_students_history AFTER INSERT OR UPDATE ON students
FOR EACH ROW EXECUTE FUNCTION trg_fn_log_entity_changes();

CREATE TRIGGER trg_enrollments_history AFTER INSERT OR UPDATE ON enrollments
FOR EACH ROW EXECUTE FUNCTION trg_fn_log_entity_changes();

CREATE OR REPLACE FUNCTION trg_fn_prevent_hard_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Фізичне видалення з таблиці "%" заборонено, використовуйте soft delete', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_students_prevent_delete BEFORE DELETE ON students
FOR EACH ROW EXECUTE FUNCTION trg_fn_prevent_hard_delete();

CREATE OR REPLACE FUNCTION trg_fn_compute_ects_grade()
RETURNS TRIGGER AS $$
BEGIN
    NEW.ects_grade := CASE
        WHEN NEW.score >= 90 THEN 'A'
        WHEN NEW.score >= 82 THEN 'B'
        WHEN NEW.score >= 74 THEN 'C'
        WHEN NEW.score >= 64 THEN 'D'
        WHEN NEW.score >= 60 THEN 'E'
        WHEN NEW.score >= 35 THEN 'FX'
        ELSE 'F'
    END;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_grades_auto_ects BEFORE INSERT OR UPDATE ON grades
FOR EACH ROW EXECUTE FUNCTION trg_fn_compute_ects_grade();

CREATE OR REPLACE VIEW vw_active_students AS
SELECT 
    s.id AS student_id,
    s.student_card_no,
    s.first_name,
    s.last_name,
    s.birth_date,
    s.funding_type,
    s.status,
    sg.id AS group_id,
    sg.code AS group_code,
    sp.code AS specialty_code,
    sp.name AS specialty_name,
    d.name AS department_name,
    f.name AS faculty_name,
    s.updated_at,
    u.username AS last_modified_by
FROM students s
JOIN study_groups sg ON s.group_id = sg.id AND sg.is_deleted = FALSE
JOIN specialties sp ON sg.specialty_id = sp.id
JOIN departments d ON sg.department_id = d.id AND d.is_deleted = FALSE
JOIN faculties f ON d.faculty_id = f.id AND f.is_deleted = FALSE
LEFT JOIN users u ON s.updated_by = u.id
WHERE s.is_deleted = FALSE;

CREATE OR REPLACE VIEW vw_student_transcript AS
SELECT 
    e.id AS enrollment_id,
    s.id AS student_id,
    s.student_card_no,
    s.last_name || ' ' || s.first_name AS student_full_name,
    sg.code AS group_code,
    c.code AS course_code,
    c.name AS course_name,
    c.credits_ects,
    sem.academic_year,
    sem.term_number,
    t.last_name || ' ' || t.first_name AS teacher_name,
    e.status AS enrollment_status,
    g.score,
    g.ects_grade,
    g.graded_at
FROM enrollments e
JOIN students s ON e.student_id = s.id
JOIN study_groups sg ON s.group_id = sg.id
JOIN course_offerings co ON e.offering_id = co.id
JOIN courses c ON co.course_id = c.id
JOIN semesters sem ON co.semester_id = sem.id
JOIN teachers t ON co.teacher_id = t.id
LEFT JOIN grades g ON g.enrollment_id = e.id
WHERE e.is_deleted = FALSE 
  AND s.is_deleted = FALSE 
  AND c.is_deleted = FALSE;

CREATE OR REPLACE VIEW vw_teacher_workload AS
SELECT 
    t.id AS teacher_id,
    t.last_name || ' ' || t.first_name AS teacher_name,
    t.position,
    d.name AS department_name,
    sem.academic_year,
    sem.term_number,
    COUNT(co.id) AS offerings_count,
    COALESCE(SUM(c.hours_total), 0) AS total_course_hours
FROM teachers t
JOIN departments d ON t.department_id = d.id
LEFT JOIN course_offerings co ON co.teacher_id = t.id
LEFT JOIN semesters sem ON co.semester_id = sem.id
LEFT JOIN courses c ON co.course_id = c.id AND c.is_deleted = FALSE
WHERE t.is_deleted = FALSE
GROUP BY t.id, t.last_name, t.first_name, t.position, d.name, sem.academic_year, sem.term_number;

CREATE OR REPLACE FUNCTION fn_calculate_student_gpa(p_student_id INT)
RETURNS NUMERIC(5,2) AS $$
DECLARE
    v_gpa NUMERIC(5,2);
BEGIN
    SELECT ROUND(SUM(g.score * c.credits_ects) / NULLIF(SUM(c.credits_ects), 0), 2)
    INTO v_gpa
    FROM enrollments e
    JOIN grades g ON g.enrollment_id = e.id
    JOIN course_offerings co ON e.offering_id = co.id
    JOIN courses c ON co.course_id = c.id
    WHERE e.student_id = p_student_id
      AND e.is_deleted = FALSE
      AND c.is_deleted = FALSE;

    RETURN COALESCE(v_gpa, 0.00);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE sp_register_student(
    IN p_username VARCHAR(50),
    IN p_email VARCHAR(120),
    IN p_password_hash TEXT,
    IN p_group_id INT,
    IN p_student_card_no VARCHAR(30),
    IN p_first_name VARCHAR(60),
    IN p_last_name VARCHAR(60),
    IN p_birth_date DATE,
    IN p_funding_type VARCHAR(20),
    OUT o_student_id INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_role_id INT;
    v_user_id INT;
BEGIN
    SELECT id INTO v_role_id FROM roles WHERE name = 'student';
    IF v_role_id IS NULL THEN
        RAISE EXCEPTION 'Роль student не знайдена у таблиці roles';
    END IF;

    INSERT INTO users (role_id, username, email, password_hash)
    VALUES (v_role_id, p_username, p_email, p_password_hash)
    RETURNING id INTO v_user_id;

    INSERT INTO students (
        user_id, group_id, student_card_no, first_name, last_name, birth_date, funding_type
    )
    VALUES (
        v_user_id, p_group_id, p_student_card_no, p_first_name, p_last_name, p_birth_date, p_funding_type
    )
    RETURNING id INTO o_student_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_soft_delete_student(
    IN p_student_id INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_user_id INT;
BEGIN
    UPDATE students
    SET is_deleted = TRUE,
        deleted_at = NOW(),
        status = 'expelled'
    WHERE id = p_student_id AND is_deleted = FALSE
    RETURNING user_id INTO v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активного студента з ID % не знайдено', p_student_id;
    END IF;

    IF v_user_id IS NOT NULL THEN
        UPDATE users SET is_active = FALSE WHERE id = v_user_id;
    END IF;

    UPDATE enrollments
    SET is_deleted = TRUE,
        deleted_at = NOW(),
        status = 'dropped'
    WHERE student_id = p_student_id 
      AND status = 'enrolled' 
      AND is_deleted = FALSE;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_enroll_student_in_offering(
    IN p_student_id INT,
    IN p_offering_id INT,
    OUT o_enrollment_id INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_current_count INT;
    v_max_students INT;
BEGIN
    SELECT max_students INTO v_max_students 
    FROM course_offerings WHERE id = p_offering_id;

    SELECT COUNT(*) INTO v_current_count 
    FROM enrollments 
    WHERE offering_id = p_offering_id AND is_deleted = FALSE;

    IF v_current_count >= v_max_students THEN
        RAISE EXCEPTION 'Досягнуто ліміт студентів (%) для курсу (offering_id=%)', v_max_students, p_offering_id;
    END IF;

    SELECT id INTO o_enrollment_id
    FROM enrollments
    WHERE student_id = p_student_id AND offering_id = p_offering_id;

    IF o_enrollment_id IS NULL THEN
        INSERT INTO enrollments (student_id, offering_id)
        VALUES (p_student_id, p_offering_id)
        RETURNING id INTO o_enrollment_id;
    ELSE
        UPDATE enrollments
        SET is_deleted = FALSE,
            deleted_at = NULL,
            status = 'enrolled'
        WHERE id = o_enrollment_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_set_student_grade(
    IN p_enrollment_id INT,
    IN p_score NUMERIC(5,2)
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM enrollments WHERE id = p_enrollment_id AND is_deleted = FALSE) THEN
        RAISE EXCEPTION 'Активний запис на курс (enrollment_id=%) не знайдено', p_enrollment_id;
    END IF;

    IF EXISTS (SELECT 1 FROM grades WHERE enrollment_id = p_enrollment_id) THEN
        UPDATE grades
        SET score = p_score,
            graded_at = NOW()
        WHERE enrollment_id = p_enrollment_id;
    ELSE
        INSERT INTO grades (enrollment_id, score)
        VALUES (p_enrollment_id, p_score);
    END IF;

    UPDATE enrollments
    SET status = 'completed'
    WHERE id = p_enrollment_id;
END;
$$;