"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import {
  LogOut,
  Copy,
  Check,
  Zap,
  MessageSquare,
  Coins,
  Shield,
  Mic,
  Monitor,
  RefreshCw,
  FileText,
  ExternalLink,
} from "lucide-react";
import { Button } from "@/components/ui/button";

interface DashboardData {
  company_id: string;
  company_name: string;
  file_count: number;
  api_key: string;
  setup_token: string;
}

export default function DashboardPage() {
  const router = useRouter();
  const [dashboardData, setDashboardData] = React.useState<DashboardData | null>(null);
  const [copiedApiKey, setCopiedApiKey] = React.useState(false);
  const [copiedSetupLink, setCopiedSetupLink] = React.useState(false);
  const [isLoading, setIsLoading] = React.useState(true);

  React.useEffect(() => {
    const apiKey = localStorage.getItem("pookify_api_key");
    if (!apiKey) {
      router.replace("/login");
      return;
    }

    fetch("/api/dashboard", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ api_key: apiKey }),
    })
      .then((res) => {
        if (!res.ok) throw new Error("Invalid session");
        return res.json();
      })
      .then(setDashboardData)
      .catch(() => {
        localStorage.removeItem("pookify_api_key");
        localStorage.removeItem("pookify_authenticated");
        router.replace("/login");
      })
      .finally(() => setIsLoading(false));
  }, [router]);

  function handleLogout() {
    localStorage.removeItem("pookify_api_key");
    localStorage.removeItem("pookify_company_name");
    localStorage.removeItem("pookify_company_id");
    localStorage.removeItem("pookify_authenticated");
    router.push("/login");
  }

  function handleCopyApiKey() {
    if (!dashboardData) return;
    navigator.clipboard.writeText(dashboardData.api_key);
    setCopiedApiKey(true);
    setTimeout(() => setCopiedApiKey(false), 2000);
  }

  function handleCopySetupLink() {
    if (!dashboardData) return;
    const setupURL = `pookify://setup?token=${encodeURIComponent(dashboardData.setup_token)}`;
    navigator.clipboard.writeText(setupURL);
    setCopiedSetupLink(true);
    setTimeout(() => setCopiedSetupLink(false), 2000);
  }

  if (isLoading || !dashboardData) {
    return (
      <div className="dark flex min-h-screen items-center justify-center bg-[#0a0a0a]">
        <div className="animate-pulse text-neutral-500">Loading...</div>
      </div>
    );
  }

  const setupURL = `pookify://setup?token=${encodeURIComponent(dashboardData.setup_token)}`;
  const maskedKey = dashboardData.api_key.slice(0, 12) + "••••••••" + dashboardData.api_key.slice(-4);

  return (
    <div className="dark min-h-screen bg-[#0a0a0a] text-white">
      <div className="mx-auto max-w-3xl px-4 py-12 sm:px-6">
        <div className="mb-10 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <span className="text-3xl">🐼</span>
            <div>
              <h1 className="text-xl font-bold tracking-tight">Pookify</h1>
              <p className="text-sm text-neutral-500">{dashboardData.company_name}</p>
            </div>
          </div>
          <Button
            variant="ghost"
            onClick={handleLogout}
            className="gap-2 text-neutral-400 hover:bg-white/5 hover:text-white"
          >
            <LogOut className="h-4 w-4" />
            Log Out
          </Button>
        </div>

        <div className="flex flex-col gap-5">
          <div className="rounded-2xl border border-white/[0.08] bg-[#111] p-6">
            <div className="mb-5 flex items-center gap-2">
              <ExternalLink className="h-4 w-4 text-indigo-400" />
              <h2 className="text-base font-semibold">Launch Pookie</h2>
            </div>
            <p className="mb-4 text-sm text-neutral-400">
              Click to open the Pookie app and connect it to your knowledge base. The link expires in 15 minutes.
            </p>
            <div className="flex gap-3">
              <Button
                asChild
                className="flex-1 gap-2 rounded-lg bg-indigo-600 text-sm font-semibold text-white hover:bg-indigo-500"
              >
                <a href={setupURL}>Open in Pookie</a>
              </Button>
              <Button
                variant="ghost"
                onClick={handleCopySetupLink}
                className="gap-2 rounded-lg border border-white/10 text-neutral-400 hover:bg-white/5 hover:text-white"
              >
                {copiedSetupLink ? (
                  <><Check className="h-4 w-4 text-green-400" /> Copied</>
                ) : (
                  <><Copy className="h-4 w-4" /> Copy Link</>
                )}
              </Button>
            </div>
          </div>

          <div className="rounded-2xl border border-white/[0.08] bg-[#111] p-6">
            <div className="mb-5 flex items-center justify-between">
              <h2 className="text-base font-semibold">Knowledge Base</h2>
              <span className="rounded-full border border-white/10 bg-white/[0.04] px-2.5 py-0.5 text-[11px] font-medium text-neutral-400">
                {dashboardData.file_count} document{dashboardData.file_count !== 1 ? "s" : ""}
              </span>
            </div>
            <div className="flex items-center gap-2 rounded-lg border border-white/[0.06] bg-white/[0.02] px-3 py-2.5">
              <FileText className="h-4 w-4 text-neutral-500" />
              <span className="text-sm text-neutral-400">
                {dashboardData.file_count > 0
                  ? `${dashboardData.file_count} file${dashboardData.file_count !== 1 ? "s" : ""} indexed and ready`
                  : "No documents uploaded yet"}
              </span>
            </div>
          </div>

          <div className="rounded-2xl border border-white/[0.08] bg-[#111] p-6">
            <div className="mb-5 flex items-center justify-between">
              <h2 className="text-base font-semibold">Plan</h2>
              <span className="rounded-full bg-indigo-500/10 px-2.5 py-0.5 text-[11px] font-semibold text-indigo-400">
                Free
              </span>
            </div>
            <div className="mb-5 grid grid-cols-2 gap-3">
              <PlanFeature icon={<MessageSquare className="h-3.5 w-3.5" />} label="50 messages / day" />
              <PlanFeature icon={<Coins className="h-3.5 w-3.5" />} label="100k tokens / day" />
              <PlanFeature icon={<Mic className="h-3.5 w-3.5" />} label="Voice + text input" />
              <PlanFeature icon={<Monitor className="h-3.5 w-3.5" />} label="Screen capture" />
            </div>
            <Button className="w-full gap-2 rounded-lg bg-indigo-600 text-sm font-semibold text-white hover:bg-indigo-500">
              <Zap className="h-4 w-4" />
              Upgrade to Pro
            </Button>
          </div>

          <div className="rounded-2xl border border-white/[0.08] bg-[#111] p-6">
            <div className="mb-4 flex items-center gap-2">
              <Shield className="h-4 w-4 text-neutral-500" />
              <h2 className="text-base font-semibold">API Key</h2>
            </div>
            <div className="flex items-center gap-3">
              <div className="flex-1 rounded-lg border border-white/10 bg-white/[0.03] px-4 py-3">
                <code className="font-mono text-sm text-neutral-400">
                  {maskedKey}
                </code>
              </div>
              <Button
                variant="ghost"
                size="icon"
                onClick={handleCopyApiKey}
                className="h-11 w-11 shrink-0 rounded-lg border border-white/10 bg-white/[0.03] text-neutral-400 hover:bg-white/[0.06] hover:text-white"
              >
                {copiedApiKey ? (
                  <Check className="h-4 w-4 text-green-400" />
                ) : (
                  <Copy className="h-4 w-4" />
                )}
              </Button>
            </div>
          </div>
        </div>

        <p className="mt-10 text-center text-xs text-neutral-600">
          Your AI companion, always on your side.
        </p>
      </div>
    </div>
  );
}

function PlanFeature({
  icon,
  label,
}: {
  icon: React.ReactNode;
  label: string;
}) {
  return (
    <div className="flex items-center gap-2 rounded-lg border border-white/[0.06] bg-white/[0.02] px-3 py-2.5">
      <span className="text-neutral-500">{icon}</span>
      <span className="text-sm text-neutral-400">{label}</span>
    </div>
  );
}
