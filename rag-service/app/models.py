from pydantic import BaseModel


class CreateCompanyRequest(BaseModel):
    company_id: str
    company_name: str
    custom_instructions: str = ""


class UpdateCompanyRequest(BaseModel):
    company_name: str = None
    custom_instructions: str = None


class IngestFromMinioRequest(BaseModel):
    object_key: str


class QueryRequest(BaseModel):
    query: str
    max_results: int = 5
    session_id: str = None


class AskRequest(BaseModel):
    query: str
    max_results: int = 5
    session_id: str = None


class ExchangeTokenRequest(BaseModel):
    token: str
