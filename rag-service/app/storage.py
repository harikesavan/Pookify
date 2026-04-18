import json
from pathlib import Path

import boto3
from botocore.config import Config as BotoConfig

from app.config import DATA_DIR, MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, MINIO_BUCKET

COMPANIES_FILE = Path(DATA_DIR) / "companies.json"


def load_companies() -> dict:
    if COMPANIES_FILE.exists():
        return json.loads(COMPANIES_FILE.read_text())
    return {}


def save_companies(companies: dict):
    Path(DATA_DIR).mkdir(parents=True, exist_ok=True)
    COMPANIES_FILE.write_text(json.dumps(companies, indent=2))


def get_minio_client():
    return boto3.client(
        "s3",
        endpoint_url=f"http://{MINIO_ENDPOINT}",
        aws_access_key_id=MINIO_ACCESS_KEY,
        aws_secret_access_key=MINIO_SECRET_KEY,
        config=BotoConfig(signature_version="s3v4"),
        region_name="us-east-1",
    )


def ensure_minio_bucket():
    s3 = get_minio_client()
    try:
        s3.head_bucket(Bucket=MINIO_BUCKET)
    except Exception:
        s3.create_bucket(Bucket=MINIO_BUCKET)
        print(f"Created MinIO bucket: {MINIO_BUCKET}")


def download_from_minio(object_key: str) -> bytes:
    s3 = get_minio_client()
    response = s3.get_object(Bucket=MINIO_BUCKET, Key=object_key)
    return response["Body"].read()
