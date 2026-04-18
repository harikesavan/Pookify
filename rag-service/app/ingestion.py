import time

from fastapi import HTTPException
from openai import OpenAI

from app.config import OPENAI_API_KEY

openai_client = OpenAI(api_key=OPENAI_API_KEY)


def ingest_file_content(vector_store_id: str, filename: str, file_content: bytes) -> dict:
    uploaded_file = openai_client.files.create(
        file=(filename, file_content),
        purpose="assistants"
    )

    openai_client.vector_stores.files.create(
        vector_store_id=vector_store_id,
        file_id=uploaded_file.id
    )

    max_wait_seconds = 60
    start = time.time()
    while time.time() - start < max_wait_seconds:
        vs_file = openai_client.vector_stores.files.retrieve(
            vector_store_id=vector_store_id,
            file_id=uploaded_file.id
        )
        if vs_file.status == "completed":
            break
        if vs_file.status == "failed":
            raise HTTPException(
                status_code=500,
                detail=f"File indexing failed: {vs_file.last_error}"
            )
        time.sleep(1)

    return {
        "file_id": uploaded_file.id,
        "filename": filename,
        "vector_store_id": vector_store_id,
        "status": "indexed"
    }
