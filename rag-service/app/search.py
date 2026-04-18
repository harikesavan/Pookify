from openai import OpenAI

from app.config import OPENAI_API_KEY

openai_client = OpenAI(api_key=OPENAI_API_KEY)


def search_vector_store(vector_store_id: str, query: str, max_results: int = 5) -> list[dict]:
    search_results = openai_client.vector_stores.search(
        vector_store_id=vector_store_id,
        query=query,
        max_num_results=max_results,
        rewrite_query=True,
    )

    chunks = []
    for result in search_results.data:
        chunk_text = ""
        if result.content:
            chunk_text = " ".join(
                block.text for block in result.content if hasattr(block, "text")
            )
        chunks.append({
            "file_id": result.file_id,
            "filename": result.filename,
            "score": result.score,
            "text": chunk_text,
        })
    return chunks


def ask_with_file_search(vector_store_id: str, query: str, max_results: int = 5) -> dict:
    response = openai_client.responses.create(
        model="gpt-4o",
        input=query,
        tools=[{
            "type": "file_search",
            "vector_store_ids": [vector_store_id],
            "max_num_results": max_results,
        }],
        include=["file_search_call.results"],
    )

    answer_text = ""
    citations = []
    retrieved_chunks = []

    for output_item in response.output:
        if output_item.type == "file_search_call":
            if hasattr(output_item, "results") and output_item.results:
                for sr in output_item.results:
                    retrieved_chunks.append({
                        "file_id": sr.file_id,
                        "filename": sr.filename,
                        "score": sr.score,
                        "text": sr.text if hasattr(sr, "text") else "",
                    })
        elif output_item.type == "message":
            for content_block in output_item.content:
                if hasattr(content_block, "text"):
                    answer_text = content_block.text
                if hasattr(content_block, "annotations"):
                    for annotation in content_block.annotations:
                        if hasattr(annotation, "filename"):
                            citations.append({
                                "filename": annotation.filename,
                                "file_id": annotation.file_id if hasattr(annotation, "file_id") else None,
                            })

    return {
        "answer": answer_text,
        "citations": citations,
        "retrieved_chunks": retrieved_chunks,
    }
