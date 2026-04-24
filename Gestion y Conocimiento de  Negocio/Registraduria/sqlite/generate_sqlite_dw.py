#!/usr/bin/env python3
"""Generate a Viaticos data warehouse in SQLite from a CSV source.

Creates a 6-table star schema:
- dim_tiempo
- dim_empleado
- dim_procedimiento
- dim_ruta
- dim_fuente_dato
- fact_viaticos
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import re
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Optional, TextIO, Tuple

SPACE_RE = re.compile(r"\s+")
NON_DIGIT_RE = re.compile(r"[^0-9]")
THOUSANDS_RE = re.compile(r"^[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?$")
DECIMAL_COMMA_RE = re.compile(r"^[0-9]+,[0-9]+$")
NON_NUMERIC_RE = re.compile(r"[^0-9,\.\-]")
ROUTE_SPLIT_RE = re.compile(r"\s*[,;]\s*")

MONTH_NAMES = {
    1: "January",
    2: "February",
    3: "March",
    4: "April",
    5: "May",
    6: "June",
    7: "July",
    8: "August",
    9: "September",
    10: "October",
    11: "November",
    12: "December",
}


def clean_spaces(value: Optional[str]) -> str:
    return SPACE_RE.sub(" ", (value or "").strip())


def parse_int_digits(value: Optional[str]) -> Optional[int]:
    digits = NON_DIGIT_RE.sub("", value or "")
    if not digits:
        return None
    return int(digits)


def parse_decimal(value: Optional[str]) -> float:
    raw = (value or "").strip()
    if not raw:
        return 0.0

    cleaned = NON_NUMERIC_RE.sub("", raw)
    if not cleaned:
        return 0.0

    if THOUSANDS_RE.match(cleaned):
        cleaned = cleaned.replace(",", "")
    elif DECIMAL_COMMA_RE.match(cleaned):
        cleaned = cleaned.replace(",", ".")
    else:
        cleaned = cleaned.replace(",", "")

    try:
        return float(cleaned)
    except ValueError:
        return 0.0


def parse_date_ddmmyyyy(value: Optional[str]) -> Optional[dt.date]:
    raw = (value or "").strip()
    if not raw:
        return None
    try:
        return dt.datetime.strptime(raw, "%d/%m/%Y").date()
    except ValueError:
        return None


def normalize_procedure(value: Optional[str]) -> str:
    text = clean_spaces(value).lower()
    if text == "prorroga":
        return "Prorroga"
    if text == "interrumpir":
        return "Interrumpir"
    return "Inicial"


def classify_purpose(value: Optional[str]) -> str:
    text = clean_spaces(value).lower()
    if "auditor" in text:
        return "AUDITORIA"
    if "visita" in text:
        return "VISITA"
    if "capacit" in text:
        return "CAPACITACION"
    if "dialogo" in text:
        return "DIALOGO"
    if "apoyo" in text:
        return "APOYO"
    return "OTROS"


def position_profile(value: Optional[str]) -> Tuple[str, Optional[int], int]:
    text = clean_spaces(value).lower()

    if "contratista" in text:
        return "CONTRATISTA", None, 1
    if "contralor" in text:
        return "CONTRALOR", 1, 0
    if "director" in text:
        return "DIRECTOR", 2, 0
    if "gerente" in text:
        return "GERENTE", 2, 0
    if "asesor" in text:
        return "ASESOR", 3, 0
    if "profesional" in text:
        return "PROFESIONAL", 3, 0
    if "especializado" in text:
        return "ESPECIALIZADO", 3, 0
    if "tecnologo" in text:
        return "TECNOLOGO", 4, 0
    if "tecnico" in text:
        return "TECNICO", 4, 0
    if "auxiliar" in text:
        return "AUXILIAR", 4, 0
    return "OTRO", None, 0


def source_profile(value: Optional[str]) -> Tuple[int, str]:
    text = clean_spaces(value).lower()
    is_real = int("real" in text and "ficticio" not in text)
    reliability = "real" if is_real else "synthetic"
    return is_real, reliability


def route_profile(route_value: Optional[str]) -> Tuple[str, Optional[str], Optional[str], int, int]:
    route_original = clean_spaces(route_value)
    if not route_original:
        return "", None, None, 0, 1

    stops = [item.strip() for item in ROUTE_SPLIT_RE.split(route_original) if item.strip()]
    if not stops:
        stops = [route_original]

    first_leg = stops[0]
    if "-" in first_leg:
        origin_raw, destination_raw = first_leg.split("-", 1)
        city_origin = origin_raw.strip() or None
        city_destination = destination_raw.strip() or None
    else:
        city_origin = None
        city_destination = None

    destination_count = max(1, len(stops))
    is_multi = 1 if destination_count > 1 else 0
    return route_original, city_origin, city_destination, is_multi, destination_count


def open_csv_handle(csv_path: Path, csv_encoding: str) -> Tuple[TextIO, str]:
    normalized = csv_encoding.strip().lower()
    if normalized != "auto":
        handle = csv_path.open("r", encoding=csv_encoding, errors="strict", newline="")
        return handle, csv_encoding

    for candidate in ("utf-8-sig", "latin-1"):
        handle = csv_path.open("r", encoding=candidate, errors="strict", newline="")
        try:
            handle.read(8192)
            handle.seek(0)
            return handle, candidate
        except UnicodeDecodeError:
            handle.close()

    raise UnicodeError("Could not decode CSV with auto-detection (utf-8-sig, latin-1)")


def build_validation_notes(
    commission_request_id: Optional[int],
    year_num: Optional[int],
    employee_id: Optional[int],
    route_original: str,
    origen_register: Optional[str],
    start_date_dt: Optional[dt.date],
    end_date_dt: Optional[dt.date],
) -> Optional[str]:
    notes: List[str] = []
    if commission_request_id is None:
        notes.append("missing_commission_request_id")
    if year_num is None:
        notes.append("missing_year")
    if employee_id is None:
        notes.append("missing_employee_id")
    if not route_original:
        notes.append("missing_route")
    if not origen_register:
        notes.append("missing_origen_register")
    if start_date_dt is None:
        notes.append("invalid_start_date")
    if end_date_dt is None:
        notes.append("invalid_end_date")
    if start_date_dt is not None and end_date_dt is not None and start_date_dt > end_date_dt:
        notes.append("start_date_gt_end_date")

    if not notes:
        return None
    return ",".join(notes)


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS dim_tiempo (
            date_key INTEGER PRIMARY KEY,
            full_date TEXT NOT NULL UNIQUE,
            day_num INTEGER NOT NULL,
            month_num INTEGER NOT NULL,
            month_name TEXT NOT NULL,
            quarter_num INTEGER NOT NULL,
            year_num INTEGER NOT NULL,
            week_num INTEGER NOT NULL,
            is_weekend INTEGER NOT NULL CHECK (is_weekend IN (0, 1)),
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS dim_empleado (
            employee_key INTEGER PRIMARY KEY AUTOINCREMENT,
            employee_id INTEGER NOT NULL UNIQUE,
            employee_name_clean TEXT NOT NULL,
            employee_position_raw TEXT,
            employee_position_norm TEXT,
            position_level INTEGER,
            is_contractor INTEGER NOT NULL DEFAULT 0 CHECK (is_contractor IN (0, 1)),
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS dim_procedimiento (
            procedure_key INTEGER PRIMARY KEY AUTOINCREMENT,
            procedure_type TEXT NOT NULL UNIQUE,
            procedure_group TEXT NOT NULL,
            is_interruption INTEGER NOT NULL CHECK (is_interruption IN (0, 1)),
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS dim_ruta (
            route_key INTEGER PRIMARY KEY AUTOINCREMENT,
            route_original TEXT NOT NULL UNIQUE,
            city_origin TEXT,
            city_destination_main TEXT,
            is_multi_destination INTEGER NOT NULL CHECK (is_multi_destination IN (0, 1)),
            destination_count INTEGER NOT NULL CHECK (destination_count >= 1),
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS dim_fuente_dato (
            source_key INTEGER PRIMARY KEY AUTOINCREMENT,
            origen_register TEXT NOT NULL UNIQUE,
            is_real_data INTEGER NOT NULL CHECK (is_real_data IN (0, 1)),
            reliability_label TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS fact_viaticos (
            viatico_key INTEGER PRIMARY KEY AUTOINCREMENT,
            commission_request_id INTEGER NOT NULL,
            year_num INTEGER NOT NULL,
            employee_key INTEGER NOT NULL,
            procedure_key INTEGER NOT NULL,
            route_key INTEGER NOT NULL,
            source_key INTEGER NOT NULL,
            start_date_key INTEGER NOT NULL,
            end_date_key INTEGER NOT NULL,
            commission_days REAL NOT NULL,
            total_travel_allowance REAL NOT NULL,
            commission_purpose_raw TEXT,
            purpose_category TEXT,
            quality_note TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (employee_key) REFERENCES dim_empleado(employee_key),
            FOREIGN KEY (procedure_key) REFERENCES dim_procedimiento(procedure_key),
            FOREIGN KEY (route_key) REFERENCES dim_ruta(route_key),
            FOREIGN KEY (source_key) REFERENCES dim_fuente_dato(source_key),
            FOREIGN KEY (start_date_key) REFERENCES dim_tiempo(date_key),
            FOREIGN KEY (end_date_key) REFERENCES dim_tiempo(date_key)
        );

        CREATE INDEX IF NOT EXISTS ix_fact_year ON fact_viaticos(year_num);
        CREATE INDEX IF NOT EXISTS ix_fact_employee ON fact_viaticos(employee_key);
        CREATE INDEX IF NOT EXISTS ix_fact_procedure ON fact_viaticos(procedure_key);
        CREATE INDEX IF NOT EXISTS ix_fact_route ON fact_viaticos(route_key);
        CREATE INDEX IF NOT EXISTS ix_fact_source ON fact_viaticos(source_key);
        """
    )


def get_lookup(conn: sqlite3.Connection, query: str) -> Dict[Any, Any]:
    cursor = conn.execute(query)
    return {row[0]: row[1] for row in cursor.fetchall()}


def insert_dimensions(
    conn: sqlite3.Connection,
    employees: Dict[int, Dict[str, Any]],
    procedures: Dict[str, Dict[str, Any]],
    routes: Dict[str, Dict[str, Any]],
    sources: Dict[str, Dict[str, Any]],
) -> None:
    conn.executemany(
        """
        INSERT INTO dim_fuente_dato (origen_register, is_real_data, reliability_label)
        VALUES (?, ?, ?)
        ON CONFLICT(origen_register) DO UPDATE SET
            is_real_data = excluded.is_real_data,
            reliability_label = excluded.reliability_label
        """,
        [
            (
                key,
                value["is_real_data"],
                value["reliability_label"],
            )
            for key, value in sources.items()
        ],
    )

    conn.executemany(
        """
        INSERT INTO dim_procedimiento (procedure_type, procedure_group, is_interruption)
        VALUES (?, ?, ?)
        ON CONFLICT(procedure_type) DO UPDATE SET
            procedure_group = excluded.procedure_group,
            is_interruption = excluded.is_interruption
        """,
        [
            (
                key,
                value["procedure_group"],
                value["is_interruption"],
            )
            for key, value in procedures.items()
        ],
    )

    conn.executemany(
        """
        INSERT INTO dim_empleado (
            employee_id,
            employee_name_clean,
            employee_position_raw,
            employee_position_norm,
            position_level,
            is_contractor
        )
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(employee_id) DO UPDATE SET
            employee_name_clean = excluded.employee_name_clean,
            employee_position_raw = excluded.employee_position_raw,
            employee_position_norm = excluded.employee_position_norm,
            position_level = excluded.position_level,
            is_contractor = excluded.is_contractor
        """,
        [
            (
                employee_id,
                value["employee_name_clean"],
                value["employee_position_raw"],
                value["employee_position_norm"],
                value["position_level"],
                value["is_contractor"],
            )
            for employee_id, value in employees.items()
        ],
    )

    conn.executemany(
        """
        INSERT INTO dim_ruta (
            route_original,
            city_origin,
            city_destination_main,
            is_multi_destination,
            destination_count
        )
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(route_original) DO UPDATE SET
            city_origin = excluded.city_origin,
            city_destination_main = excluded.city_destination_main,
            is_multi_destination = excluded.is_multi_destination,
            destination_count = excluded.destination_count
        """,
        [
            (
                route_original,
                value["city_origin"],
                value["city_destination_main"],
                value["is_multi_destination"],
                value["destination_count"],
            )
            for route_original, value in routes.items()
        ],
    )


def insert_dim_tiempo(conn: sqlite3.Connection, min_date: dt.date, max_date: dt.date) -> None:
    rows = []
    current = min_date
    one_day = dt.timedelta(days=1)

    while current <= max_date:
        date_key = int(current.strftime("%Y%m%d"))
        iso_week = current.isocalendar()[1]
        rows.append(
            (
                date_key,
                current.isoformat(),
                current.day,
                current.month,
                MONTH_NAMES[current.month],
                ((current.month - 1) // 3) + 1,
                current.year,
                iso_week,
                1 if current.weekday() >= 5 else 0,
            )
        )
        current += one_day

    conn.executemany(
        """
        INSERT OR IGNORE INTO dim_tiempo (
            date_key,
            full_date,
            day_num,
            month_num,
            month_name,
            quarter_num,
            year_num,
            week_num,
            is_weekend
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )


def insert_facts(
    conn: sqlite3.Connection,
    fact_rows: List[Dict[str, Any]],
    employee_map: Dict[int, int],
    procedure_map: Dict[str, int],
    route_map: Dict[str, int],
    source_map: Dict[str, int],
    date_map: Dict[str, int],
) -> Tuple[int, int]:
    inserted = 0
    skipped = 0

    for row in fact_rows:
        commission_request_id = row["commission_request_id"]
        year_num = row["year_num"]
        employee_key = employee_map.get(row["employee_id"])
        procedure_key = procedure_map.get(row["procedure_type_norm"])
        route_key = route_map.get(row["route_original"])
        source_key = source_map.get(row["origen_register"])

        start_date_key = None
        end_date_key = None
        if row["start_date_dt"] is not None:
            start_date_key = date_map.get(row["start_date_dt"].isoformat())
        if row["end_date_dt"] is not None:
            end_date_key = date_map.get(row["end_date_dt"].isoformat())

        if not all(
            [
                employee_key,
                procedure_key,
                route_key,
                source_key,
                start_date_key,
                end_date_key,
                row["commission_request_id"],
                row["year_num"],
            ]
        ):
            skipped += 1
            continue

        conn.execute(
            """
            INSERT INTO fact_viaticos (
                commission_request_id,
                year_num,
                employee_key,
                procedure_key,
                route_key,
                source_key,
                start_date_key,
                end_date_key,
                commission_days,
                total_travel_allowance,
                commission_purpose_raw,
                purpose_category,
                quality_note
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                commission_request_id,
                year_num,
                employee_key,
                procedure_key,
                route_key,
                source_key,
                start_date_key,
                end_date_key,
                row["commission_days_num"],
                row["total_travel_allowance_num"],
                row["commission_purpose_raw"],
                row["purpose_category"],
                row["quality_note"],
            ),
        )
        inserted += 1

    return inserted, skipped


def build_sqlite(csv_path: Path, db_path: Path, overwrite: bool, csv_encoding: str) -> None:
    if not csv_path.exists():
        raise FileNotFoundError(f"CSV not found: {csv_path}")

    if overwrite and db_path.exists():
        db_path.unlink()

    db_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    ensure_schema(conn)

    employees: Dict[int, Dict[str, Any]] = {}
    procedures: Dict[str, Dict[str, Any]] = {}
    routes: Dict[str, Dict[str, Any]] = {}
    sources: Dict[str, Dict[str, Any]] = {}
    fact_rows: List[Dict[str, Any]] = []

    total_rows = 0
    rows_with_quality_note = 0

    handle, used_encoding = open_csv_handle(csv_path, csv_encoding)
    with handle:
        reader = csv.DictReader(handle)
        for raw in reader:
            total_rows += 1

            commission_request_id = parse_int_digits(raw.get("commission_request_id"))
            procedure_type_norm = normalize_procedure(raw.get("procedure_type"))
            employee_id = parse_int_digits(raw.get("employee_id"))
            employee_name_clean = clean_spaces(raw.get("employee_name"))
            employee_position_raw = clean_spaces(raw.get("employee_position")) or None
            employee_position_norm, position_level, is_contractor = position_profile(employee_position_raw)

            route_original, city_origin, city_destination_main, is_multi_destination, destination_count = route_profile(
                raw.get("route")
            )

            start_date_dt = parse_date_ddmmyyyy(raw.get("start_date"))
            end_date_dt = parse_date_ddmmyyyy(raw.get("end_date"))
            commission_days_num = parse_decimal(raw.get("commission_days"))
            total_travel_allowance_num = parse_decimal(raw.get("total_travel_allowance"))
            commission_purpose_raw = clean_spaces(raw.get("commission_purpose")) or None
            purpose_category = classify_purpose(commission_purpose_raw)

            year_num = parse_int_digits(raw.get("year"))
            if year_num is None and start_date_dt is not None:
                year_num = start_date_dt.year
            if year_num is None and end_date_dt is not None:
                year_num = end_date_dt.year

            origen_register = clean_spaces(raw.get("origen_register")) or None

            quality_note = build_validation_notes(
                commission_request_id=commission_request_id,
                year_num=year_num,
                employee_id=employee_id,
                route_original=route_original,
                origen_register=origen_register,
                start_date_dt=start_date_dt,
                end_date_dt=end_date_dt,
            )
            if quality_note is not None:
                rows_with_quality_note += 1

            if commission_request_id is None:
                commission_request_id = -total_rows

            if year_num is None:
                year_num = 0

            if employee_id is None:
                employee_id = -1
                employee_name_clean = employee_name_clean or "SIN_IDENTIFICAR"
                employee_position_raw = employee_position_raw or "SIN_CARGO"
                employee_position_norm = "OTRO"
                position_level = None
                is_contractor = 0

            if not route_original:
                route_original = "RUTA_NO_INFORMADA"
                city_origin = None
                city_destination_main = None
                is_multi_destination = 0
                destination_count = 1

            if not origen_register:
                origen_register = "UNKNOWN"

            if start_date_dt is None and end_date_dt is None:
                default_year = year_num if year_num > 0 else 1900
                start_date_dt = dt.date(default_year, 1, 1)
                end_date_dt = dt.date(default_year, 1, 1)
            elif start_date_dt is None:
                start_date_dt = end_date_dt
            elif end_date_dt is None:
                end_date_dt = start_date_dt

            if start_date_dt > end_date_dt:
                start_date_dt, end_date_dt = end_date_dt, start_date_dt

            is_real_data, reliability_label = source_profile(origen_register)
            sources[origen_register] = {
                "is_real_data": is_real_data,
                "reliability_label": reliability_label,
            }

            procedures[procedure_type_norm] = {
                "procedure_group": (
                    "Interrupcion"
                    if procedure_type_norm == "Interrumpir"
                    else "Extension"
                    if procedure_type_norm == "Prorroga"
                    else "Normal"
                ),
                "is_interruption": 1 if procedure_type_norm == "Interrumpir" else 0,
            }

            if employee_id == -1:
                employees.setdefault(
                    employee_id,
                    {
                        "employee_name_clean": "SIN_IDENTIFICAR",
                        "employee_position_raw": "SIN_CARGO",
                        "employee_position_norm": "OTRO",
                        "position_level": None,
                        "is_contractor": 0,
                    },
                )
            else:
                employees[employee_id] = {
                    "employee_name_clean": employee_name_clean or "SIN_NOMBRE",
                    "employee_position_raw": employee_position_raw,
                    "employee_position_norm": employee_position_norm,
                    "position_level": position_level,
                    "is_contractor": is_contractor,
                }

            routes[route_original] = {
                "city_origin": city_origin,
                "city_destination_main": city_destination_main,
                "is_multi_destination": is_multi_destination,
                "destination_count": destination_count,
            }

            fact_row = {
                "commission_request_id": commission_request_id,
                "year_num": year_num,
                "employee_id": employee_id,
                "procedure_type_norm": procedure_type_norm,
                "route_original": route_original,
                "origen_register": origen_register,
                "start_date_dt": start_date_dt,
                "end_date_dt": end_date_dt,
                "commission_days_num": commission_days_num,
                "total_travel_allowance_num": total_travel_allowance_num,
                "commission_purpose_raw": commission_purpose_raw,
                "purpose_category": purpose_category,
                "quality_note": quality_note,
            }
            fact_rows.append(fact_row)

    insert_dimensions(conn, employees, procedures, routes, sources)

    employee_map = get_lookup(conn, "SELECT employee_id, employee_key FROM dim_empleado")
    procedure_map = get_lookup(conn, "SELECT procedure_type, procedure_key FROM dim_procedimiento")
    route_map = get_lookup(conn, "SELECT route_original, route_key FROM dim_ruta")
    source_map = get_lookup(conn, "SELECT origen_register, source_key FROM dim_fuente_dato")

    if fact_rows:
        min_date = min(min(v["start_date_dt"], v["end_date_dt"]) for v in fact_rows)
        max_date = max(max(v["start_date_dt"], v["end_date_dt"]) for v in fact_rows)
        insert_dim_tiempo(conn, min_date, max_date)

    date_map = get_lookup(conn, "SELECT full_date, date_key FROM dim_tiempo")
    inserted_facts, skipped_facts = insert_facts(
        conn,
        fact_rows,
        employee_map,
        procedure_map,
        route_map,
        source_map,
        date_map,
    )

    conn.commit()

    counts = {
        "dim_tiempo": conn.execute("SELECT COUNT(*) FROM dim_tiempo").fetchone()[0],
        "dim_empleado": conn.execute("SELECT COUNT(*) FROM dim_empleado").fetchone()[0],
        "dim_procedimiento": conn.execute("SELECT COUNT(*) FROM dim_procedimiento").fetchone()[0],
        "dim_ruta": conn.execute("SELECT COUNT(*) FROM dim_ruta").fetchone()[0],
        "dim_fuente_dato": conn.execute("SELECT COUNT(*) FROM dim_fuente_dato").fetchone()[0],
        "fact_viaticos": conn.execute("SELECT COUNT(*) FROM fact_viaticos").fetchone()[0],
    }

    conn.close()

    print("SQLite DW generated successfully")
    print(f"Database: {db_path}")
    print(f"CSV encoding used: {used_encoding}")
    print(f"Source CSV rows: {total_rows}")
    print(f"Fact rows attempted: {len(fact_rows)}")
    print(f"Fact rows inserted: {inserted_facts}")
    print(f"Fact rows skipped due to unresolved FK/date mapping: {skipped_facts}")
    print(f"Rows with quality_note: {rows_with_quality_note}")
    print("Table counts:")
    for table_name, row_count in counts.items():
        print(f"  - {table_name}: {row_count}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build Viaticos DW SQLite database from CSV")
    parser.add_argument(
        "--csv",
        default="Viaticos_Registraduria_2022_2025.csv",
        help="Path to source CSV",
    )
    parser.add_argument(
        "--db",
        default="sqlite/viaticos_dw.sqlite",
        help="Output SQLite database path",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Delete destination DB before loading",
    )
    parser.add_argument(
        "--csv-encoding",
        default="auto",
        help="Encoding used to read source CSV (default: auto; tries utf-8-sig, then latin-1)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    csv_path = Path(args.csv).resolve()
    db_path = Path(args.db).resolve()
    build_sqlite(
        csv_path=csv_path,
        db_path=db_path,
        overwrite=args.overwrite,
        csv_encoding=args.csv_encoding,
    )


if __name__ == "__main__":
    main()
