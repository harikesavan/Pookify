import type { UploadedFile } from "@/hooks/use-file-upload";

export interface PookieFormData {
  companyName: string;
  description: string;
  docFiles: UploadedFile[];
}

export interface PookieConfig {
  company_id: string;
  company_name: string;
  rag_service_url: string;
  api_key: string;
}

export interface CreatePookieResult {
  company_id: string;
  company_name: string;
  api_key: string;
  vector_store_id: string;
  ingested_files: { filename: string; status: string }[];
  config: PookieConfig;
}

export const initialFormData: PookieFormData = {
  companyName: "",
  description: "",
  docFiles: [],
};
