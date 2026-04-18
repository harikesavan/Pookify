"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import { Loader2 } from "lucide-react";

const statusMessages = [
  "Reading your uploaded docs…",
  "Extracting content from your links…",
  "Organizing your knowledge base…",
  "Teaching Pookie your product…",
  "Running sample questions…",
  "Packaging your macOS app…",
  "Almost there…",
];

const TOTAL_DURATION_MS = 12000;
const STATUS_TICK_MS = Math.floor(TOTAL_DURATION_MS / statusMessages.length);
const PROGRESS_TICK_MS = 80;

export function BuildProgress({ onComplete }: { onComplete: () => void }) {
  const [statusIndex, setStatusIndex] = useState(0);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const startedAt = Date.now();

    const statusTimer = setInterval(() => {
      setStatusIndex((prev) =>
        prev < statusMessages.length - 1 ? prev + 1 : prev,
      );
    }, STATUS_TICK_MS);

    const progressTimer = setInterval(() => {
      const elapsed = Date.now() - startedAt;
      const next = Math.min(100, (elapsed / TOTAL_DURATION_MS) * 100);
      setProgress(next);
      if (elapsed >= TOTAL_DURATION_MS) {
        clearInterval(progressTimer);
        clearInterval(statusTimer);
        setTimeout(onComplete, 350);
      }
    }, PROGRESS_TICK_MS);

    return () => {
      clearInterval(statusTimer);
      clearInterval(progressTimer);
    };
  }, [onComplete]);

  return (
    <div className="mx-auto flex min-h-[calc(100vh-5rem)] w-full max-w-xl flex-col items-center justify-center px-6 py-12">
      <motion.div
        className="relative mb-8 flex h-28 w-28 items-center justify-center"
        initial={{ scale: 0.6, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.5, ease: "easeOut" }}
      >
        <span className="absolute inset-0 animate-ping rounded-full bg-red-500/15" />
        <span className="absolute inset-2 rounded-full bg-red-500/10" />
        <span className="text-5xl">🐼</span>
      </motion.div>

      <motion.h1
        className="text-2xl font-semibold tracking-tight md:text-3xl"
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, delay: 0.1 }}
      >
        Building your Pookie
      </motion.h1>

      <div className="mt-4 flex h-7 items-center justify-center">
        <AnimatePresence mode="wait">
          <motion.p
            key={statusIndex}
            className="text-muted-foreground flex items-center gap-2 text-sm md:text-base"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ duration: 0.25 }}
          >
            <Loader2 className="h-3.5 w-3.5 animate-spin text-red-500" />
            {statusMessages[statusIndex]}
          </motion.p>
        </AnimatePresence>
      </div>

      <div className="bg-muted mt-8 h-2 w-full overflow-hidden rounded-full">
        <motion.div
          className="h-full bg-red-500"
          initial={{ width: 0 }}
          animate={{ width: `${progress}%` }}
          transition={{ duration: 0.2, ease: "linear" }}
        />
      </div>
      <p className="text-muted-foreground mt-2 text-xs">
        {Math.round(progress)}%
      </p>
    </div>
  );
}
