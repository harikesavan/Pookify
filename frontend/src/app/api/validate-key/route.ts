import { NextRequest, NextResponse } from "next/server";

const RAG_SERVICE_URL = process.env.RAG_SERVICE_URL || "http://localhost:8000";

export async function POST(request: NextRequest) {
  const { api_key } = await request.json();

  if (!api_key) {
    return NextResponse.json({ error: "API key required" }, { status: 400 });
  }

  const response = await fetch(`${RAG_SERVICE_URL}/query`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": api_key,
    },
    body: JSON.stringify({ query: "test", max_results: 1 }),
  });

  if (!response.ok) {
    return NextResponse.json({ error: "Invalid API key" }, { status: 401 });
  }

  const data = await response.json();

  return NextResponse.json({
    valid: true,
    company_id: data.company_id,
  });
}
