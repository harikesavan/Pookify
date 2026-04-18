import secrets

from fastapi import HTTPException
from openai import OpenAI

from app.config import OPENAI_API_KEY
from app.storage import load_companies, save_companies

openai_client = OpenAI(api_key=OPENAI_API_KEY)


def create_company(company_id: str, company_name: str, custom_instructions: str = "") -> dict:
    companies = load_companies()

    if company_id in companies:
        raise HTTPException(status_code=409, detail="Company already exists")

    vector_store = openai_client.vector_stores.create(name=f"clicky-{company_id}")
    api_key = f"ck_live_{secrets.token_hex(24)}"

    company = {
        "company_id": company_id,
        "company_name": company_name,
        "vector_store_id": vector_store.id,
        "api_key": api_key,
        "custom_instructions": custom_instructions,
    }

    companies[company_id] = company
    save_companies(companies)
    return company


def get_company_by_id(company_id: str) -> dict:
    companies = load_companies()
    if company_id not in companies:
        raise HTTPException(status_code=404, detail=f"Company not found: {company_id}")
    return companies[company_id]


def get_company_by_api_key(api_key: str) -> dict:
    if not api_key:
        raise HTTPException(status_code=401, detail="Missing API key")
    companies = load_companies()
    for company in companies.values():
        if company["api_key"] == api_key:
            return company
    raise HTTPException(status_code=401, detail="Invalid API key")


def update_company(company_id: str, company_name: str = None, custom_instructions: str = None) -> dict:
    companies = load_companies()
    if company_id not in companies:
        raise HTTPException(status_code=404, detail="Company not found")

    if company_name is not None:
        companies[company_id]["company_name"] = company_name
    if custom_instructions is not None:
        companies[company_id]["custom_instructions"] = custom_instructions

    save_companies(companies)
    return companies[company_id]


def regenerate_api_key(company_id: str) -> str:
    companies = load_companies()
    if company_id not in companies:
        raise HTTPException(status_code=404, detail="Company not found")

    new_key = f"ck_live_{secrets.token_hex(24)}"
    companies[company_id]["api_key"] = new_key
    save_companies(companies)
    return new_key


def get_file_count(vector_store_id: str) -> int:
    try:
        store = openai_client.vector_stores.retrieve(vector_store_id)
        return store.file_counts.completed
    except Exception:
        return -1
