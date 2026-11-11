from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import List, Optional
import psycopg2
from psycopg2.extras import RealDictCursor

@dataclass
class StudentViewDTO:
    student_id: int
    student_card_no: str
    first_name: str
    last_name: str
    group_code: str
    specialty_name: str
    faculty_name: str
    status: str
    last_modified_by: Optional[str]


@dataclass
class TranscriptRowDTO:
    enrollment_id: int
    student_id: int
    student_full_name: str
    course_code: str
    course_name: str
    credits_ects: Decimal
    enrollment_status: str
    score: Optional[Decimal]
    ects_grade: Optional[str]

class StudentRepository:
    def __init__(self, cursor):
        self._cur = cursor

    def register_student(
        self,
        username: str,
        email: str,
        password_hash: str,
        group_id: int,
        student_card_no: str,
        first_name: str,
        last_name: str,
        birth_date: date,
        funding_type: str,
    ) -> int:
        self._cur.execute(
            """
            CALL university.sp_register_student(
                %s, %s, %s, %s, %s, %s, %s, %s, %s, NULL
            );
            """,
            (
                username,
                email,
                password_hash,
                group_id,
                student_card_no,
                first_name,
                last_name,
                birth_date,
                funding_type,
            ),
        )
        result = self._cur.fetchone()
        return result["o_student_id"]

    def soft_delete(self, student_id: int) -> None:
        self._cur.execute("CALL university.sp_soft_delete_student(%s);", (student_id,))

    def get_active_by_id(self, student_id: int) -> Optional[StudentViewDTO]:
        self._cur.execute(
            """
            SELECT student_id, student_card_no, first_name, last_name,
                   group_code, specialty_name, faculty_name, status, last_modified_by
            FROM university.vw_active_students
            WHERE student_id = %s;
            """,
            (student_id,),
        )
        row = self._cur.fetchone()
        return StudentViewDTO(**row) if row else None

    def get_all_active_by_group(self, group_code: str) -> List[StudentViewDTO]:
        self._cur.execute(
            """
            SELECT student_id, student_card_no, first_name, last_name,
                   group_code, specialty_name, faculty_name, status, last_modified_by
            FROM university.vw_active_students
            WHERE group_code = %s
            ORDER BY last_name, first_name;
            """,
            (group_code,),
        )
        return [StudentViewDTO(**row) for row in self._cur.fetchall()]


class AcademicProgressRepository:
    def __init__(self, cursor):
        self._cur = cursor

    def enroll_student(self, student_id: int, offering_id: int) -> int:
        self._cur.execute(
            "CALL university.sp_enroll_student_in_offering(%s, %s, NULL);",
            (student_id, offering_id),
        )
        result = self._cur.fetchone()
        return result["o_enrollment_id"]

    def assign_grade(self, enrollment_id: int, score: float) -> None:
        self._cur.execute(
            "CALL university.sp_set_student_grade(%s, %s);",
            (enrollment_id, score),
        )

    def get_student_transcript(self, student_id: int) -> List[TranscriptRowDTO]:
        self._cur.execute(
            """
            SELECT enrollment_id, student_id, student_full_name,
                   course_code, course_name, credits_ects,
                   enrollment_status, score, ects_grade
            FROM university.vw_student_transcript
            WHERE student_id = %s
            ORDER BY course_code;
            """,
            (student_id,),
        )
        return [TranscriptRowDTO(**row) for row in self._cur.fetchall()]

    def calculate_gpa(self, student_id: int) -> Decimal:
        self._cur.execute(
            "SELECT university.fn_calculate_student_gpa(%s) AS gpa;",
            (student_id,),
        )
        return self._cur.fetchone()["gpa"]

class UniversityUnitOfWork:
    def __init__(self, dsn: str, actor_user_id: int):
        self._dsn = dsn
        self._actor_user_id = actor_user_id
        self._conn = None
        self._cur = None
        self.students: Optional[StudentRepository] = None
        self.academic: Optional[AcademicProgressRepository] = None

    def __enter__(self) -> "UniversityUnitOfWork":
        self._conn = psycopg2.connect(self._dsn)
        self._conn.autocommit = False
        self._cur = self._conn.cursor(cursor_factory=RealDictCursor)

        self._cur.execute("SET search_path TO university, public;")
        # id користувача для тригерів (updated_by, audit_logs)
        self._cur.execute(
            "SELECT set_config('app.current_user_id', %s, true);",
            (str(self._actor_user_id),),
        )

        self.students = StudentRepository(self._cur)
        self.academic = AcademicProgressRepository(self._cur)
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None:
            self.rollback()
        self._cur.close()
        self._conn.close()

    def commit(self) -> None:
        self._conn.commit()

    def rollback(self) -> None:
        self._conn.rollback()


if __name__ == "__main__":
    DB_DSN = "dbname=stbd_lab1 user=postgres password=postgres host=localhost port=5432"
    DEAN_ADMIN_USER_ID = 1

    with UniversityUnitOfWork(DB_DSN, actor_user_id=DEAN_ADMIN_USER_ID) as uow:
        student_id = uow.students.register_student(
            username="i.moskaliuk",
            email="i.moskaliuk@knu.ua",
            password_hash="argon2_hashed_pwd",
            group_id=1,
            student_card_no="КВ12345678",
            first_name="Ілля",
            last_name="Москалюк",
            birth_date=date(2006, 8, 2),
            funding_type="state",
        )

        enr_db = uow.academic.enroll_student(student_id=student_id, offering_id=1)
        enr_alg = uow.academic.enroll_student(student_id=student_id, offering_id=2)

        uow.academic.assign_grade(enrollment_id=enr_db, score=95.0)
        uow.academic.assign_grade(enrollment_id=enr_alg, score=88.0)

        uow.commit()

    with UniversityUnitOfWork(DB_DSN, actor_user_id=DEAN_ADMIN_USER_ID) as uow:
        student = uow.students.get_active_by_id(student_id)
        print(f"Студент: {student.last_name} {student.first_name} ({student.group_code})")
        print(f"Останнім змінив: {student.last_modified_by}")

        transcript = uow.academic.get_student_transcript(student_id)
        for row in transcript:
            print(f" - {row.course_name}: {row.score} балів (ECTS: {row.ects_grade})")

        gpa = uow.academic.calculate_gpa(student_id)
        print(f"Зважений середній бал (GPA): {gpa}")

    with UniversityUnitOfWork(DB_DSN, actor_user_id=DEAN_ADMIN_USER_ID) as uow:
        uow.students.soft_delete(student_id)
        uow.commit()

        deleted_check = uow.students.get_active_by_id(student_id)
        print(f"Активний профіль після Soft Delete: {deleted_check}")