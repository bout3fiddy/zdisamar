"""Progress reporting for long benchmark runs."""

from .db import BenchmarkDb


class Progress:
    def __init__(self, db: BenchmarkDb, run_id: str) -> None:

        self.db = db
        self.run_id = run_id

    def log(self, phase: str, message: str) -> None:

        self.db.event(self.run_id, phase, message)
        print(f"[{phase}] {message}", flush=True)
