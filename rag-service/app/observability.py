import logging

import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration
from sentry_sdk.integrations.openai import OpenAIIntegration
from sentry_sdk.integrations.logging import LoggingIntegration

from langfuse import get_client

from app.config import SENTRY_DSN, LANGFUSE_SECRET_KEY


def init_sentry():
    if not SENTRY_DSN:
        print("Sentry DSN not set — skipping Sentry init")
        return

    sentry_sdk.init(
        dsn=SENTRY_DSN,
        environment="development",
        traces_sample_rate=1.0,
        send_default_pii=True,
        enable_logs=True,
        integrations=[
            StarletteIntegration(transaction_style="endpoint"),
            FastApiIntegration(transaction_style="endpoint"),
            OpenAIIntegration(include_prompts=True),
            LoggingIntegration(
                level=logging.DEBUG,
                event_level=logging.ERROR,
            ),
        ],
    )
    print("Sentry initialized")


def init_langfuse():
    if not LANGFUSE_SECRET_KEY:
        print("Langfuse keys not set — skipping Langfuse init")
        return None

    langfuse = get_client()
    print("Langfuse initialized")
    return langfuse


def init_all():
    init_sentry()
    return init_langfuse()
