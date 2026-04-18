import time

from fastapi import HTTPException
from langfuse.openai import openai
from langfuse import get_client, propagate_attributes

from app.config import OPENAI_API_KEY

openai_client = openai.OpenAI(api_key=OPENAI_API_KEY)
langfuse = get_client()


def ingest_file_content(vector_store_id: str, filename: str, file_content: bytes, company_id: str = None) -> dict:
    with propagate_attributes(
        trace_name="document-ingestion",
        tags=["ingestion"],
        metadata={"company_id": company_id, "filename": filename, "file_size_bytes": len(file_content)},
    ):
        with langfuse.start_as_current_observation(
            name="file-upload-and-index",
            as_type="span",
            input={"filename": filename, "size_bytes": len(file_content), "vector_store_id": vector_store_id},
        ) as span:
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

            indexing_duration = time.time() - start
            span.update(output={
                "file_id": uploaded_file.id,
                "status": "indexed",
                "indexing_duration_seconds": round(indexing_duration, 1),
            })

            return {
                "file_id": uploaded_file.id,
                "filename": filename,
                "vector_store_id": vector_store_id,
                "status": "indexed"
            }
