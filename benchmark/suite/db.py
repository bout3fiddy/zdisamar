"""SQLite scratch telemetry for benchmark runs."""

import json
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any

from .stats import json_ready


class BenchmarkDb:
    def __init__(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(path)
        self.connection.row_factory = sqlite3.Row
        self._init_schema()

    def close(self) -> None:
        self.connection.close()

    def create_run(self, *, git: dict[str, Any], command: str) -> str:
        run_id = uuid.uuid4().hex
        self.connection.execute(
            """
            insert into runs(run_id, started_at_unix_s, status, git_json, command)
            values (?, ?, ?, ?, ?)
            """,
            (run_id, time.time(), "running", json.dumps(json_ready(git)), command),
        )
        self.connection.commit()

        return run_id

    def finish_run(self, run_id: str, status: str) -> None:
        self.connection.execute(
            """
            update runs
            set finished_at_unix_s = ?, status = ?
            where run_id = ?
            """,
            (time.time(), status, run_id),
        )
        self.connection.commit()

    def event(self, run_id: str, phase: str, message: str) -> None:
        self.connection.execute(
            """
            insert into events(run_id, at_unix_s, phase, message)
            values (?, ?, ?, ?)
            """,
            (run_id, time.time(), phase, message),
        )
        self.connection.commit()

    def sample(
        self,
        run_id: str,
        *,
        phase: str,
        mode: str,
        case_id: str,
        repeat: int,
        elapsed_s: float,
        payload: dict[str, Any] | None = None,
    ) -> None:
        self.connection.execute(
            """
            insert into samples(
                run_id, phase, mode, case_id, repeat, elapsed_s, payload_json
            )
            values (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                run_id,
                phase,
                mode,
                case_id,
                repeat,
                elapsed_s,
                json.dumps(json_ready(payload or {}), sort_keys=True),
            ),
        )
        self.connection.commit()

    def residual(
        self,
        run_id: str,
        *,
        phase: str,
        mode: str,
        case_id: str,
        metric: str,
        value: float,
        payload: dict[str, Any] | None = None,
    ) -> None:
        self.connection.execute(
            """
            insert into residuals(
                run_id, phase, mode, case_id, metric, value, payload_json
            )
            values (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                run_id,
                phase,
                mode,
                case_id,
                metric,
                value,
                json.dumps(json_ready(payload or {}), sort_keys=True),
            ),
        )
        self.connection.commit()

    def summary(self, run_id: str, name: str, payload: dict[str, Any]) -> None:
        self.connection.execute(
            """
            insert or replace into summaries(run_id, name, payload_json)
            values (?, ?, ?)
            """,
            (run_id, name, json.dumps(json_ready(payload), sort_keys=True)),
        )
        self.connection.commit()

    def run_payload(self, run_id: str) -> dict[str, Any]:
        row = self.connection.execute(
            """
            select run_id, started_at_unix_s, finished_at_unix_s, status, git_json, command
            from runs
            where run_id = ?
            """,
            (run_id,),
        ).fetchone()

        if row is None:
            raise ValueError(f"unknown run_id: {run_id}")

        return {
            "run_id": row["run_id"],
            "started_at_unix_s": row["started_at_unix_s"],
            "finished_at_unix_s": row["finished_at_unix_s"],
            "status": row["status"],
            "git": json.loads(row["git_json"]),
            "command": row["command"],
        }

    def summaries(self, run_id: str) -> dict[str, Any]:
        rows = self.connection.execute(
            """
            select name, payload_json
            from summaries
            where run_id = ?
            """,
            (run_id,),
        ).fetchall()

        return {row["name"]: json.loads(row["payload_json"]) for row in rows}

    def _init_schema(self) -> None:
        self.connection.executescript(
            """
            create table if not exists runs (
                run_id text primary key,
                started_at_unix_s real not null,
                finished_at_unix_s real,
                status text not null,
                git_json text not null,
                command text not null
            );

            create table if not exists events (
                id integer primary key autoincrement,
                run_id text not null,
                at_unix_s real not null,
                phase text not null,
                message text not null
            );

            create table if not exists samples (
                id integer primary key autoincrement,
                run_id text not null,
                phase text not null,
                mode text not null,
                case_id text not null,
                repeat integer not null,
                elapsed_s real not null,
                payload_json text not null
            );

            create table if not exists residuals (
                id integer primary key autoincrement,
                run_id text not null,
                phase text not null,
                mode text not null,
                case_id text not null,
                metric text not null,
                value real not null,
                payload_json text not null
            );

            create table if not exists summaries (
                run_id text not null,
                name text not null,
                payload_json text not null,
                primary key(run_id, name)
            );
            """
        )
        self.connection.commit()
