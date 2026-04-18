import { NextRequest, NextResponse } from "next/server";

const RAG_SERVICE_URL = process.env.RAG_SERVICE_URL || "http://localhost:8000";

export async function POST(request: NextRequest) {
  const formData = await request.formData();
  const companyName = formData.get("companyName") as string;
  const description = formData.get("description") as string;

  if (!companyName) {
    return NextResponse.json({ error: "Company name required" }, { status: 400 });
  }

  const companyId = companyName
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 32);

  const createResponse = await fetch(`${RAG_SERVICE_URL}/companies`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      company_id: companyId,
      company_name: companyName,
      custom_instructions: description,
    }),
  });

  if (!createResponse.ok) {
    const error = await createResponse.text();
    return NextResponse.json(
      { error: `Failed to create company: ${error}` },
      { status: createResponse.status },
    );
  }

  const company = await createResponse.json();

  const files: File[] = [];
  for (const [key, value] of formData.entries()) {
    if (key === "files" && value instanceof File) {
      files.push(value);
    }
  }

  const ingestResults = [];
  for (const file of files) {
    const fileFormData = new FormData();
    fileFormData.append("file", file);

    const ingestResponse = await fetch(
      `${RAG_SERVICE_URL}/companies/${companyId}/ingest`,
      { method: "POST", body: fileFormData },
    );

    if (ingestResponse.ok) {
      const result = await ingestResponse.json();
      ingestResults.push({ filename: file.name, status: "indexed", ...result });
    } else {
      ingestResults.push({ filename: file.name, status: "failed" });
    }
  }

  const configResponse = await fetch(
    `${RAG_SERVICE_URL}/companies/${companyId}/config`,
  );
  const config = await configResponse.json();

  return NextResponse.json({
    company_id: companyId,
    company_name: companyName,
    api_key: company.api_key,
    setup_token: company.setup_token,
    vector_store_id: company.vector_store_id,
    ingested_files: ingestResults,
    config,
  });
}
