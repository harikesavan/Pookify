/**
 * Clicky Proxy Worker
 *
 * Single gateway for the macOS app. The app never calls external APIs directly.
 *
 * Routes:
 *   POST /chat             → OpenAI Chat Completions API (streaming)
 *   POST /tts              → OpenAI TTS API
 *   POST /transcribe       → OpenAI Audio Transcription API
 *   POST /transcribe-token → AssemblyAI temp token
 *   POST /query-knowledge  → RAG Service (knowledge base query)
 */

interface Env {
  OPENAI_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
  ASSEMBLYAI_API_KEY: string;
  RAG_SERVICE_URL: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return new Response(
        JSON.stringify({
          ok: true,
          hasOpenAIKey: Boolean(env.OPENAI_API_KEY),
        }),
        { status: 200, headers: { "content-type": "application/json" } }
      );
    }

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      if (url.pathname === "/chat") {
        return await handleChat(request, env);
      }

      if (url.pathname === "/tts") {
        return await handleTTS(request, env);
      }

      if (url.pathname === "/transcribe") {
        return await handleTranscribe(request, env);
      }

      if (url.pathname === "/query-knowledge") {
        return await handleQueryKnowledge(request, env);
      }
    } catch (error) {
      console.error(`[${url.pathname}] Unhandled error:`, error);
      return new Response(
        JSON.stringify({ error: String(error) }),
        { status: 500, headers: { "content-type": "application/json" } }
      );
    }

    return new Response("Not found", { status: 404 });
  },
};

async function handleChat(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.OPENAI_API_KEY}`,
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/chat] OpenAI API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

async function handleTranscribe(request: Request, env: Env): Promise<Response> {
  const body = await request.arrayBuffer();
  const contentType = request.headers.get("content-type") || "multipart/form-data";

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.OPENAI_API_KEY}`,
      "content-type": contentType,
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/transcribe] OpenAI API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "application/json",
    },
  });
}

async function handleTTS(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  const response = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.OPENAI_API_KEY}`,
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tts] OpenAI TTS API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}

async function handleQueryKnowledge(request: Request, env: Env): Promise<Response> {
  const ragServiceUrl = env.RAG_SERVICE_URL || "http://localhost:8000";
  const body = await request.text();
  const apiKey = request.headers.get("x-api-key") || "";

  const response = await fetch(`${ragServiceUrl}/query`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
    },
    body,
  });

  const responseBody = await response.text();
  return new Response(responseBody, {
    status: response.status,
    headers: { "content-type": "application/json" },
  });
}
