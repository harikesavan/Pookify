import type { UploadedFile } from "@/hooks/use-file-upload";

export interface PookieFormData {
  companyName: string;
  description: string;
  docFiles: UploadedFile[];
}

export const initialFormData: PookieFormData = {
  companyName: "",
  description: "",
  docFiles: [],
};
