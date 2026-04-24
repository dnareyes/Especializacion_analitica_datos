#!/usr/bin/env python3
"""Export Viaticos DW SQLite tables to CSV files."""

from __future__ import annotations

import argparse
import csv
import sqlite3
from pathlib import Path
from typing import Iterable, List

DEFAULT_TABLES = [
    "dim_tiempo",
    "dim_empleado",
    "dim_procedimiento",
    "dim_ruta",
    "dim_fuente_dato",
    "fact_viaticos",
]


def parse_tables(raw: str) -> List[str]:
    values = [item.strip() for item in raw.split(",") if item.strip()]
    if not values:
        return DEFAULT_TABLES
    return values


def export_table(conn: sqlite3.Connection, table_name: str, output_path: Path) -> int:
    cursor = conn.execute(f"SELECT * FROM {table_name}")
    headers = [col[0] for col in cursor.description]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    row_count = 0

    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(headers)
        for row in cursor:
            writer.writerow(row)
            row_count += 1

    return row_count


def run_export(db_path: Path, out_dir: Path, tables: Iterable[str]) -> None:
    if not db_path.exists():
        raise FileNotFoundError(f"SQLite DB not found: {db_path}")

    conn = sqlite3.connect(db_path)

    try:
        for table_name in tables:
            output_path = out_dir / f"{table_name}.csv"
            row_count = export_table(conn, table_name, output_path)
            print(f"Exported {table_name}: {row_count} rows -> {output_path}")
    finally:
        conn.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export SQLite tables to CSV")
    parser.add_argument(
        "--db",
        default="sqlite/viaticos_dw.sqlite",
        help="Path to SQLite database",
    )
    parser.add_argument(
        "--outdir",
        default="sqlite/exports",
        help="Directory where CSV files will be written",
    )
    parser.add_argument(
        "--tables",
        default=",".join(DEFAULT_TABLES),
        help="Comma-separated table names",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    db_path = Path(args.db).resolve()
    out_dir = Path(args.outdir).resolve()
    tables = parse_tables(args.tables)
    run_export(db_path=db_path, out_dir=out_dir, tables=tables)


if __name__ == "__main__":
    main()
