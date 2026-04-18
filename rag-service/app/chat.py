from langfuse.openai import openai
from langfuse import get_client, propagate_attributes

from app.config import OPENAI_API_KEY

openai_client = openai.OpenAI(api_key=OPENAI_API_KEY)
langfuse = get_client()


def stream_chat_completion(
    messages: list,
    model: str = "gpt-4o",
    max_completion_tokens: int = 1024,
    session_id: str = None,
    user_id: str = None,
    company_id: str = None,
):
    with propagate_attributes(
        session_id=session_id,
        user_id=user_id,
        trace_name="chat-completion",
        tags=["chat", "vision"],
        metadata={"company_id": company_id, "model": model},
    ):
        stream = openai_client.chat.completions.create(
            model=model,
            messages=messages,
            max_completion_tokens=max_completion_tokens,
            stream=True,
            name="vision-chat",
        )

        for chunk in stream:
            yield chunk
