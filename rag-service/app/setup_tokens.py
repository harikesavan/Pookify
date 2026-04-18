import json
import secrets
import time
from pathlib import Path

from fastapi import HTTPException

from app.config import DATA_DIR

TOKENS_FILE = Path(DATA_DIR) / "setup_tokens.json"
TOKEN_EXPIRY_SECONDS = 900


def load_tokens() -> dict:
    if TOKENS_FILE.exists():
        return json.loads(TOKENS_FILE.read_text())
    return {}


def save_tokens(tokens: dict):
    Path(DATA_DIR).mkdir(parents=True, exist_ok=True)
    TOKENS_FILE.write_text(json.dumps(tokens, indent=2))


def purge_expired_tokens(tokens: dict) -> dict:
    now = time.time()
    return {k: v for k, v in tokens.items() if v["expires_at"] > now}


def create_setup_token(company_id: str) -> str:
    tokens = load_tokens()
    tokens = purge_expired_tokens(tokens)

    token = f"pst_{secrets.token_hex(24)}"
    tokens[token] = {
        "company_id": company_id,
        "created_at": time.time(),
        "expires_at": time.time() + TOKEN_EXPIRY_SECONDS,
    }

    save_tokens(tokens)
    return token


def exchange_setup_token(token: str) -> str:
    tokens = load_tokens()
    tokens = purge_expired_tokens(tokens)

    if token not in tokens:
        raise HTTPException(status_code=401, detail="Invalid or expired setup token")

    token_data = tokens[token]

    if time.time() > token_data["expires_at"]:
        del tokens[token]
        save_tokens(tokens)
        raise HTTPException(status_code=401, detail="Setup token has expired")

    company_id = token_data["company_id"]

    del tokens[token]
    save_tokens(tokens)

    return company_id
