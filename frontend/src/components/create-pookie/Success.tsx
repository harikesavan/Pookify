"use client";

import { useState } from "react";
import Link from "next/link";
import { motion } from "motion/react";
import { ArrowRight, Check, Copy, Download } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import type { PookieFormData, CreatePookieResult } from "@/components/create-pookie/types";

export function Success({ formData, result }: { formData: PookieFormData; result: CreatePookieResult }) {
  const [copied, setCopied] = useState(false);
  const agentName = `Pookie from ${formData.companyName}`;

  const pookifySetupURL = `pookify://setup?token=${encodeURIComponent(result.setup_token)}`;

  const copySetupLink = async () => {
    try {
      await navigator.clipboard.writeText(pookifySetupURL);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      /* noop */
    }
  };

  return (
    <div className="mx-auto w-full max-w-2xl px-4 pt-10 pb-16 md:pt-14">
      <motion.div
        className="text-center"
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
      >
        <motion.div
          className="mx-auto mb-4 flex h-20 w-20 items-center justify-center rounded-full bg-red-500/10"
          initial={{ scale: 0.4, rotate: -15 }}
          animate={{ scale: 1, rotate: 0 }}
          transition={{ type: "spring", damping: 12, stiffness: 200 }}
        >
          <span className="text-5xl">🐼</span>
        </motion.div>
        <h1 className="text-3xl font-semibold tracking-tight md:text-4xl">
          {agentName} is{" "}
          <span className="text-red-500">ready.</span>
        </h1>
        <p className="text-muted-foreground mt-2 text-sm md:text-base">
          Share the link below with your customers — or download Pookie to test
          it yourself.
        </p>
      </motion.div>

      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, delay: 0.15 }}
        className="mt-8 grid gap-4"
      >
        <Card className="rounded-3xl p-6">
          <div className="flex items-start gap-4">
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-red-500/10 text-red-500">
              <Download className="h-5 w-5" />
            </div>
            <div className="flex-1">
              <h2 className="text-lg font-semibold">Open in Pookie</h2>
              <p className="text-muted-foreground text-sm">
                This will configure the Pookie app with your company&apos;s knowledge base.
              </p>
            </div>
            <Button
              asChild
              className="rounded-2xl bg-red-500 text-white hover:bg-red-600"
            >
              <a href={pookifySetupURL}>
                Launch Pookie
              </a>
            </Button>
          </div>
        </Card>

        <Card className="rounded-3xl p-6">
          <div className="flex items-start gap-4">
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-red-500/10 text-red-500">
              <ArrowRight className="h-5 w-5" />
            </div>
            <div className="flex-1">
              <h2 className="text-lg font-semibold">Share setup link</h2>
              <p className="text-muted-foreground text-sm">
                Send this to your team. The link expires in 15 minutes and can only be used once.
              </p>
              <div className="mt-3 flex items-center gap-2 rounded-xl border bg-muted/30 p-3">
                <code className="flex-1 truncate text-sm">pookify://setup?token=...</code>
                <Button
                  type="button"
                  variant="outline"
                  onClick={copySetupLink}
                  className="inline-flex items-center gap-2 rounded-xl leading-none"
                >
                  {copied ? (
                    <>
                      <Check className="h-4 w-4 shrink-0" />
                      <span>Copied</span>
                    </>
                  ) : (
                    <>
                      <Copy className="h-4 w-4 shrink-0" />
                      <span>Copy</span>
                    </>
                  )}
                </Button>
              </div>
              <p className="text-muted-foreground mt-2 text-xs">
                {result.ingested_files.length} document{result.ingested_files.length !== 1 ? "s" : ""} indexed
              </p>
            </div>
          </div>
        </Card>
      </motion.div>

      <motion.div
        className="mt-8 text-center"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.4, delay: 0.4 }}
      >
        <Button
          asChild
          variant="outline"
          className="rounded-2xl"
        >
          <Link href="/">Back to home</Link>
        </Button>
      </motion.div>
    </div>
  );
}
