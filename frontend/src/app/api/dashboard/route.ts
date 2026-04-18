import { NextRequest, NextResponse } from "next/server";

const RAG_SERVICE_URL = process.env.RAG_SERVICE_URL || "http://localhost:8000";

export async function POST(request: NextRequest) {
  const { api_key } = await request.json();

  if (!api_key) {
    return NextResponse.json({ error: "API key required" }, { status: 400 });
  }

  const queryResponse = await fetch(`${RAG_SERVICE_URL}/query`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": api_key,
    },
    body: JSON.stringify({ query: "test", max_results: 1 }),
  });

  if (!queryResponse.ok) {
    return NextResponse.json({ error: "Invalid API key" }, { status: 401 });
  }

  const queryData = await queryResponse.json();
  const companyId = queryData.company_id;

  const companyResponse = await fetch(`${RAG_SERVICE_URL}/companies/${companyId}`);

  if (!companyResponse.ok) {
    return NextResponse.json({ error: "Company not found" }, { status: 404 });
  }

  const company = await companyResponse.json();

  const tokenResponse = await fetch(`${RAG_SERVICE_URL}/companies/${companyId}/setup-token`, {
    method: "POST",
  });
  const tokenData = await tokenResponse.json();

  return NextResponse.json({
    company_id: company.company_id,
    company_name: company.company_name,
    file_count: company.file_count,
    api_key: api_key,
    setup_token: tokenData.setup_token,
  });
}
