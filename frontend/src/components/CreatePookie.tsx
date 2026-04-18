"use client";

import { useState } from "react";
import { motion } from "motion/react";
import { File, Sparkles, Upload, X } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useFileUpload, type UploadedFile } from "@/hooks/use-file-upload";

import {
  initialFormData,
  type PookieFormData,
  type CreatePookieResult,
} from "@/components/create-pookie/types";
import { BuildProgress } from "@/components/create-pookie/BuildProgress";
import { Success } from "@/components/create-pookie/Success";

type Phase = "form" | "building" | "done";

const focusInput =
  "focus-visible:ring-2 focus-visible:ring-red-500/30 focus-visible:border-red-500";

const formatFileSize = (bytes: number) => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};

export function CreatePookie() {
  const [phase, setPhase] = useState<Phase>("form");
  const [formData, setFormData] = useState<PookieFormData>(initialFormData);
  const [isDragging, setIsDragging] = useState(false);
  const [result, setResult] = useState<CreatePookieResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const updateFormData = <K extends keyof PookieFormData>(
    field: K,
    value: PookieFormData[K],
  ) => {
    setFormData((prev) => ({ ...prev, [field]: value }));
  };

  const { fileInputRef, handleClick, handleFilesChange, addFiles } =
    useFileUpload({
      onUpload: (files) => updateFormData("docFiles", files),
    });

  const removeFile = (name: string) => {
    updateFormData(
      "docFiles",
      formData.docFiles.filter((file: UploadedFile) => file.name !== name),
    );
  };

  const onDrop = (event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    setIsDragging(false);
    if (event.dataTransfer.files?.length) addFiles(event.dataTransfer.files);
  };

  const isValid =
    formData.companyName.trim() !== "" && formData.docFiles.length > 0;

  const handleSubmit = async () => {
    setPhase("building");
    setError(null);

    try {
      const body = new FormData();
      body.append("companyName", formData.companyName);
      body.append("description", formData.description);
      for (const uploadedFile of formData.docFiles) {
        body.append("files", uploadedFile.rawFile);
      }

      const response = await fetch("/api/create-pookie", {
        method: "POST",
        body,
      });

      if (!response.ok) {
        const errData = await response.json();
        throw new Error(errData.error || "Failed to create Pookie");
      }

      const data: CreatePookieResult = await response.json();
      setResult(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong");
      setPhase("form");
    }
  };

  if (phase === "building") {
    return (
      <BuildProgress
        onComplete={() => {
          if (result) setPhase("done");
        }}
      />
    );
  }

  if (phase === "done" && result) {
    return <Success formData={formData} result={result} />;
  }

  return (
    <div className="mx-auto w-full max-w-xl px-4 pt-8 pb-12 md:pt-10">
      <motion.header
        className="mb-5 text-center"
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
      >
        <h1 className="text-4xl font-semibold tracking-tight md:text-5xl">
          Create your <span className="text-red-500">Pookie</span>
        </h1>
        <p className="text-muted-foreground mt-3 text-base md:text-lg">
          Tell Pookie about your company and feed it your docs.
        </p>
      </motion.header>

      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, delay: 0.1 }}
      >
        <Card className="rounded-2xl border p-6 shadow-sm md:p-7">
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="companyName" className="text-sm">
                Company name
              </Label>
              <Input
                id="companyName"
                placeholder="Acme Inc."
                value={formData.companyName}
                onChange={(e) => updateFormData("companyName", e.target.value)}
                className={`h-10 text-sm ${focusInput}`}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="description" className="text-sm">
                Company description
              </Label>
              <Textarea
                id="description"
                placeholder="What does your company do?"
                value={formData.description}
                onChange={(e) => updateFormData("description", e.target.value)}
                className={`min-h-[72px] text-sm ${focusInput}`}
              />
            </div>

            <div className="space-y-1.5">
              <Label className="text-sm">Knowledge documents</Label>
              <input
                ref={fileInputRef}
                type="file"
                accept=".pdf,.doc,.docx,.md,.markdown,.txt,.rtf,.csv,.xlsx,.xls,.pptx,.ppt,image/*"
                multiple
                className="hidden"
                onChange={handleFilesChange}
              />
              <div
                onDragOver={(e) => {
                  e.preventDefault();
                  setIsDragging(true);
                }}
                onDragLeave={() => setIsDragging(false)}
                onDrop={onDrop}
                onClick={handleClick}
                className={`hover:border-red-500 hover:bg-red-500/5 flex cursor-pointer flex-col items-center justify-center gap-1.5 rounded-xl border border-dashed p-5 text-sm transition-colors ${
                  isDragging ? "border-red-500 bg-red-500/10" : ""
                }`}
              >
                <Upload className="text-muted-foreground h-5 w-5" />
                <p className="text-muted-foreground">
                  <span className="text-foreground font-medium">
                    Drop files
                  </span>{" "}
                  or click to browse
                </p>
                <p className="text-muted-foreground/70 text-xs">
                  PDF, DOCX, images, slides, sheets, and more
                </p>
              </div>

              {formData.docFiles.length > 0 && (
                <ul className="space-y-2 pt-2">
                  {formData.docFiles.map((file: UploadedFile) => (
                    <li
                      key={file.name}
                      className="flex items-center gap-3 rounded-lg border p-3 text-sm"
                    >
                      <File className="text-muted-foreground h-4 w-4 shrink-0" />
                      <span className="flex-1 truncate">{file.name}</span>
                      <span className="text-muted-foreground text-xs">
                        {formatFileSize(file.size)}
                      </span>
                      <button
                        type="button"
                        onClick={() => removeFile(file.name)}
                        className="text-muted-foreground hover:text-foreground"
                        aria-label={`Remove ${file.name}`}
                      >
                        <X className="h-4 w-4" />
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            <motion.div
              whileHover={{ scale: 1.01 }}
              whileTap={{ scale: 0.99 }}
              className="pt-2"
            >
              {error && (
                <p className="text-red-500 text-sm text-center">{error}</p>
              )}
              <Button
                type="button"
                onClick={handleSubmit}
                disabled={!isValid}
                className="flex h-11 w-full items-center justify-center gap-2 rounded-xl bg-red-500 text-sm text-white hover:bg-red-600"
              >
                Build my Pookie
                <Sparkles className="h-4 w-4" />
              </Button>
            </motion.div>
          </div>
        </Card>
      </motion.div>
    </div>
  );
}
