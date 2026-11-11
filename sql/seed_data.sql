SET search_path TO university, public;

INSERT INTO roles (name, description) VALUES 
('admin', 'Адміністратор деканату'),
('teacher', 'Викладач'),
('student', 'Студент');

INSERT INTO users (role_id, username, email, password_hash) VALUES 
(1, 'dean_admin', 'dean@knu.ua', 'hash_admin'),
(2, 'prof_koval', 'koval@knu.ua', 'hash_koval');

SET app.current_user_id = '1';

INSERT INTO faculties (code, name) VALUES ('CSC', 'Факультет комп''ютерних наук та кібернетики');
INSERT INTO departments (faculty_id, code, name) VALUES (1, 'TPS', 'Кафедра теорії та технології програмування');
INSERT INTO specialties (code, name, degree_level) VALUES ('122', 'Комп''ютерні науки', 'Bachelor');
INSERT INTO teachers (user_id, department_id, first_name, last_name, academic_degree, position)
VALUES (2, 1, 'Олександр', 'Коваль', 'д.ф.-м.н.', 'Професор');

INSERT INTO study_groups (department_id, specialty_id, curator_id, code, enrollment_year)
VALUES (1, 1, 1, 'К-24', 2024);

INSERT INTO courses (department_id, code, name, credits_ects, hours_total, description)
VALUES 
(1, 'DB-2026', 'Організація баз даних та знань', 5.0, 150, 'Реляційні СУБД, PostgreSQL, транзакції, індекси'),
(1, 'ALG-2026', 'Алгоритми та структури даних', 6.0, 180, 'Графи, дерева, динамічне програмування');

INSERT INTO semesters (academic_year, term_number, start_date, end_date, is_current)
VALUES ('2026/2027', 1, '2026-09-01', '2026-12-31', TRUE);

INSERT INTO course_offerings (course_id, semester_id, teacher_id, max_students)
VALUES (1, 1, 1, 60), (2, 1, 1, 60);