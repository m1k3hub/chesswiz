"""Locust load test for the scidb-beta runtime adapter (Phase 2).

Run locally:

    locust -f opening-report/load/locustfile.py --host http://localhost:5001 \
        --users 50 --spawn-rate 5 --run-time 5m --headless

Nightly CI runs this headless against an ephemeral container and fails the
build when the p95 latency budget or error-rate budget is exceeded:

    locust -f load/locustfile.py --host http://localhost:5001 \
        --users 100 --spawn-rate 10 --run-time 10m --headless \
        --only-summary

Rate-limited responses (429) from the searches/analysis endpoints are
expected under load and are reported as successes so error budgets reflect
real failures only.
"""

from __future__ import annotations

import json
import uuid

from locust import HttpUser, between, task

START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"


class ScidbUser(HttpUser):
    """Simulated studio user: browses databases, queries the tree, searches."""

    wait_time = between(0.5, 2.0)

    @task(5)
    def health_live(self) -> None:
        self.client.get("/api/health/live", name="/api/health/live")

    @task(4)
    def list_databases(self) -> None:
        self.client.get("/api/databases", name="/api/databases")

    @task(4)
    def list_games(self) -> None:
        self.client.get("/api/databases/masters/games", name="/api/databases/{id}/games")

    @task(3)
    def game_detail(self) -> None:
        self.client.get("/api/games/g-001", name="/api/games/{id}")

    @task(3)
    def tree_query_root(self) -> None:
        self.client.post(
            "/api/tree/query",
            json={"moves": [], "source": None, "fen": START_FEN},
            name="/api/tree/query (root)",
        )

    @task(2)
    def tree_query_e4(self) -> None:
        self.client.post(
            "/api/tree/query",
            json={
                "moves": [{"san": "e4", "uci": "e2e4"}],
                "source": None,
                "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
            },
            name="/api/tree/query (1.e4)",
        )

    @task(2)
    def search_and_results(self) -> None:
        with self.client.post(
            "/api/searches",
            json={"databaseId": "masters", "type": "advanced", "query": {"white": "carlsen"}},
            name="/api/searches",
            catch_response=True,
        ) as resp:
            if resp.status_code == 429:
                resp.success()  # rate limiting under load is expected
                return
            if resp.status_code != 200:
                resp.failure(f"search failed: {resp.status_code}")
                return
            job_id = resp.json().get("jobId")
        if job_id:
            self.client.get(f"/api/searches/{job_id}/results", name="/api/searches/{id}/results")

    @task(1)
    def analysis_start_stop(self) -> None:
        with self.client.post(
            "/api/analysis/start",
            json={"fen": START_FEN, "multiPv": 1, "depth": 5, "engineId": "mock"},
            name="/api/analysis/start",
            catch_response=True,
        ) as resp:
            if resp.status_code == 429:
                resp.success()
                return
            if resp.status_code != 200:
                resp.failure(f"analysis start failed: {resp.status_code}")
                return
            job_id = resp.json().get("jobId")
        if job_id:
            self.client.get(f"/api/analysis/{job_id}", name="/api/analysis/{id}")
            self.client.post(f"/api/analysis/{job_id}/stop", name="/api/analysis/{id}/stop")

    @task(1)
    def workspace(self) -> None:
        # Unique query param defeats intermediaries; measures real latency.
        self.client.get(
            f"/api/workspace?_={uuid.uuid4().hex[:8]}",
            name="/api/workspace",
        )


class HealthOnlyUser(HttpUser):
    """Lightweight probe user for sustained background traffic."""

    wait_time = between(1.0, 3.0)
    weight = 1

    @task
    def health(self) -> None:
        self.client.get("/api/health/live", name="/api/health/live")
