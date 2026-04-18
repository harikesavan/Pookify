"use client";

import { useCallback, useEffect, useRef, useState } from "react";

export interface UploadedFile {
  name: string;
  size: number;
  type: string;
  url: string;
  rawFile: File;
}

interface UseFileUploadProps {
  onUpload?: (files: UploadedFile[]) => void;
}

export function useFileUpload({ onUpload }: UseFileUploadProps = {}) {
  const objectUrlsRef = useRef<string[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [files, setFiles] = useState<UploadedFile[]>([]);

  const handleClick = useCallback(() => {
    fileInputRef.current?.click();
  }, []);

  const addFiles = useCallback(
    (incoming: FileList | File[]) => {
      const list = Array.from(incoming);
      if (list.length === 0) return;

      const next: UploadedFile[] = list.map((file) => {
        const url = URL.createObjectURL(file);
        objectUrlsRef.current.push(url);
        return {
          name: file.name,
          size: file.size,
          type: file.type,
          url,
          rawFile: file,
        };
      });

      setFiles((prev) => {
        const merged = [...prev];
        for (const candidate of next) {
          const isDuplicate = merged.some(
            (existing) =>
              existing.name === candidate.name &&
              existing.size === candidate.size,
          );
          if (!isDuplicate) merged.push(candidate);
        }
        onUpload?.(merged);
        return merged;
      });
    },
    [onUpload],
  );

  const handleFilesChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      if (event.target.files) addFiles(event.target.files);
      if (fileInputRef.current) fileInputRef.current.value = "";
    },
    [addFiles],
  );

  const removeFile = useCallback((name: string) => {
    setFiles((prev) => {
      const removed = prev.find((file) => file.name === name);
      if (removed) URL.revokeObjectURL(removed.url);
      return prev.filter((file) => file.name !== name);
    });
  }, []);

  const clearAll = useCallback(() => {
    setFiles((prev) => {
      for (const file of prev) URL.revokeObjectURL(file.url);
      return [];
    });
    if (fileInputRef.current) fileInputRef.current.value = "";
  }, []);

  useEffect(() => {
    return () => {
      for (const url of objectUrlsRef.current) URL.revokeObjectURL(url);
      objectUrlsRef.current = [];
    };
  }, []);

  return {
    files,
    fileInputRef,
    handleClick,
    handleFilesChange,
    addFiles,
    removeFile,
    clearAll,
  };
}
