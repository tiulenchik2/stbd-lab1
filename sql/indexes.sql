SET search_path TO university, public;

CREATE INDEX idx_students_active_group_lastname
ON students (group_id, last_name)
WHERE is_deleted = FALSE;

CREATE INDEX idx_students_card_hash
ON students USING HASH (student_card_no);