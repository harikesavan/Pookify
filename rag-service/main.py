from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import DATA_DIR, MINIO_BUCKET
from app.routes import company_router, query_router
from app.storage import load_companies, ensure_minio_bucket, get_minio_client


@asynccontextmanager
async def lifespan(app: FastAPI):
    Path(DATA_DIR).mkdir(parents=True, exist_ok=True)
    try:
        ensure_minio_bucket()
    except Exception as e:
        print(f"MinIO not available at startup: {e}")
    yield


app = FastAPI(title="Clicky RAG Service", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(company_router)
app.include_router(query_router)


@app.get("/health")
async def health():
    companies = load_companies()

    minio_status = "unknown"
    try:
        s3 = get_minio_client()
        s3.head_bucket(Bucket=MINIO_BUCKET)
        minio_status = "connected"
    except Exception:
        minio_status = "unavailable"

    return {
        "status": "ok",
        "company_count": len(companies),
        "minio_status": minio_status,
    }
