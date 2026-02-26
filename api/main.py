import os
import socket
import time

import psycopg2
from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

app = FastAPI()

REQUEST_COUNT = Counter(
    "api_requests_total",
    "Total API requests",
    ["endpoint"],
)
RESPONSE_COUNT = Counter(
    "api_responses_total",
    "Total API responses",
    ["endpoint", "status"],
)
DB_QUERY_SECONDS = Histogram(
    "db_query_seconds",
    "Time spent querying the database",
)


@app.middleware("http")
async def record_metrics(request: Request, call_next):
    endpoint = request.url.path
    try:
        response = await call_next(request)
        status = str(response.status_code)
        return response
    except Exception:
        status = "500"
        raise
    finally:
        REQUEST_COUNT.labels(endpoint=endpoint).inc()
        RESPONSE_COUNT.labels(endpoint=endpoint, status=status).inc()


def get_db_config():
    return {
        "host": os.getenv("DB_HOST", "localhost"),
        "port": int(os.getenv("DB_PORT", "5432")),
        "dbname": os.getenv("DB_NAME", "gv_db"),
        "user": os.getenv("DB_USER", "gv_user"),
        "password": os.getenv("DB_PASSWORD", "gv_pass"),
    }


def get_conn():
    config = get_db_config()
    return psycopg2.connect(**config)


@app.get("/user")
def get_user():
    start_time = time.perf_counter()
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT name FROM users WHERE id = 1;")
                row = cur.fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="User not found")
                return {"name": row[0]}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Database unavailable") from exc
    finally:
        DB_QUERY_SECONDS.observe(time.perf_counter() - start_time)


@app.get("/container")
def get_container():
    return {"container_id": socket.gethostname()}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
