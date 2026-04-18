import json

from fastapi import APIRouter, File, UploadFile, HTTPException, Header, Request
from fastapi.responses import StreamingResponse

from app.chat import stream_chat_completion
from app.companies import (
    create_company, get_company_by_id, get_company_by_api_key,
    update_company, regenerate_api_key, get_file_count,
)
from app.config import PUBLIC_RAG_URL
from app.ingestion import ingest_file_content
from app.models import (
    CreateCompanyRequest, UpdateCompanyRequest,
    IngestFromMinioRequest, QueryRequest, AskRequest, ExchangeTokenRequest,
)
from app.search import search_vector_store, ask_with_file_search
from app.setup_tokens import create_setup_token, exchange_setup_token
from app.storage import load_companies, download_from_minio

company_router = APIRouter(prefix="/companies", tags=["companies"])
query_router = APIRouter(tags=["query"])
chat_router = APIRouter(tags=["chat"])
auth_router = APIRouter(tags=["auth"])


@company_router.post("")
async def handle_create_company(request: CreateCompanyRequest):
    company = create_company(request.company_id, request.company_name, request.custom_instructions)
    setup_token = create_setup_token(request.company_id)
    return {**company, "setup_token": setup_token}


@company_router.post("/{company_id}/setup-token")
async def handle_create_setup_token(company_id: str):
    get_company_by_id(company_id)
    token = create_setup_token(company_id)
    return {"setup_token": token, "expires_in_seconds": 900}


@company_router.get("")
async def handle_list_companies():
    companies = load_companies()
    return [
        {
            **company,
            "api_key": company["api_key"][:12] + "...",
            "file_count": get_file_count(company["vector_store_id"]),
        }
        for company in companies.values()
    ]


@company_router.get("/{company_id}")
async def handle_get_company(company_id: str):
    company = get_company_by_id(company_id)
    return {**company, "file_count": get_file_count(company["vector_store_id"])}


@company_router.patch("/{company_id}")
async def handle_update_company(company_id: str, request: UpdateCompanyRequest):
    return update_company(company_id, request.company_name, request.custom_instructions)


@company_router.post("/{company_id}/regenerate-key")
async def handle_regenerate_key(company_id: str):
    new_key = regenerate_api_key(company_id)
    return {"api_key": new_key}


@company_router.get("/{company_id}/config")
async def handle_get_config(company_id: str):
    company = get_company_by_id(company_id)
    return {
        "company_id": company["company_id"],
        "company_name": company["company_name"],
        "rag_service_url": PUBLIC_RAG_URL,
        "api_key": company["api_key"],
    }


@company_router.post("/{company_id}/ingest")
async def handle_ingest_file(company_id: str, file: UploadFile = File(...)):
    company = get_company_by_id(company_id)
    file_content = await file.read()
    if not file_content:
        raise HTTPException(status_code=400, detail="Empty file")
    return ingest_file_content(company["vector_store_id"], file.filename, file_content, company_id=company_id)


@company_router.post("/{company_id}/ingest-from-minio")
async def handle_ingest_from_minio(company_id: str, request: IngestFromMinioRequest):
    company = get_company_by_id(company_id)
    try:
        file_content = download_from_minio(request.object_key)
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"MinIO download failed: {str(e)}")
    if not file_content:
        raise HTTPException(status_code=400, detail="Downloaded file is empty")
    filename = request.object_key.split("/")[-1]
    return ingest_file_content(company["vector_store_id"], filename, file_content, company_id=company_id)


@query_router.post("/query")
async def handle_query(request: QueryRequest, x_api_key: str = Header(None)):
    company = get_company_by_api_key(x_api_key)
    chunks = search_vector_store(
        company["vector_store_id"],
        request.query,
        request.max_results,
        session_id=request.session_id,
        company_id=company["company_id"],
    )
    return {
        "query": request.query,
        "company_id": company["company_id"],
        "custom_instructions": company.get("custom_instructions", ""),
        "chunks": chunks,
    }


@query_router.post("/ask")
async def handle_ask(request: AskRequest, x_api_key: str = Header(None)):
    company = get_company_by_api_key(x_api_key)
    return ask_with_file_search(
        company["vector_store_id"],
        request.query,
        request.max_results,
        session_id=request.session_id,
        company_id=company["company_id"],
    )


@chat_router.post("/chat")
async def handle_chat(request: Request):
    body = await request.json()

    messages = body.get("messages", [])
    model = body.get("model", "gpt-4o")
    max_completion_tokens = body.get("max_completion_tokens", 1024)
    is_streaming = body.get("stream", False)
    session_id = body.get("session_id") or request.headers.get("x-session-id")
    user_id = request.headers.get("x-user-id")
    company_id = request.headers.get("x-company-id")

    if not is_streaming:
        from langfuse.openai import openai as lf_openai
        from app.config import OPENAI_API_KEY
        from langfuse import propagate_attributes

        client = lf_openai.OpenAI(api_key=OPENAI_API_KEY)
        with propagate_attributes(
            session_id=session_id, user_id=user_id,
            trace_name="chat-completion",
            tags=["chat"], metadata={"company_id": company_id, "model": model},
        ):
            response = client.chat.completions.create(
                model=model, messages=messages,
                max_completion_tokens=max_completion_tokens,
                name="vision-chat",
            )
            return response.model_dump()

    def generate_sse():
        for chunk in stream_chat_completion(
            messages=messages,
            model=model,
            max_completion_tokens=max_completion_tokens,
            session_id=session_id,
            user_id=user_id,
            company_id=company_id,
        ):
            yield f"data: {json.dumps(chunk.model_dump())}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(generate_sse(), media_type="text/event-stream")


@auth_router.post("/exchange-token")
async def handle_exchange_token(request: ExchangeTokenRequest):
    company_id = exchange_setup_token(request.token)
    company = get_company_by_id(company_id)
    return {
        "company_id": company["company_id"],
        "company_name": company["company_name"],
        "api_key": company["api_key"],
        "rag_service_url": PUBLIC_RAG_URL,
    }
