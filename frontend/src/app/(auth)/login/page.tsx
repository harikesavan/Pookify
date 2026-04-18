"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { Eye, EyeOff, Loader2 } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

export default function LoginPage() {
  const router = useRouter();
  const [apiKey, setApiKey] = React.useState("");
  const [showKey, setShowKey] = React.useState(false);
  const [isLoading, setIsLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  const isFormValid = apiKey.trim().length > 0;

  React.useEffect(() => {
    const existingKey = localStorage.getItem("pookify_api_key");
    if (existingKey) {
      router.replace("/dashboard");
    }
  }, [router]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!isFormValid || isLoading) return;

    const trimmedKey = apiKey.trim();
    setError(null);
    setIsLoading(true);

    try {
      const response = await fetch("/api/validate-key", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ api_key: trimmedKey }),
      });

      if (!response.ok) {
        throw new Error("Invalid API key. Check your key and try again.");
      }

      const data = await response.json();
      localStorage.setItem("pookify_api_key", trimmedKey);
      localStorage.setItem("pookify_company_id", data.company_id);
      localStorage.setItem("pookify_authenticated", "true");
      router.push("/dashboard");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong");
      setIsLoading(false);
    }
  }

  return (
    <div className="dark flex min-h-screen items-center justify-center bg-[#0a0a0a] p-4">
      <div
        aria-hidden
        className="pointer-events-none fixed left-1/2 top-1/3 -translate-x-1/2 -translate-y-1/2 h-[480px] w-[480px] rounded-full opacity-20 blur-[120px]"
        style={{
          background:
            "radial-gradient(circle, rgba(99,102,241,0.5) 0%, rgba(99,102,241,0) 70%)",
        }}
      />

      <div className="relative z-10 w-full max-w-[420px]">
        <form onSubmit={handleSubmit} className="flex flex-col items-center">
          <div className="mb-8 flex flex-col items-center gap-3">
            <div className="relative flex h-20 w-20 items-center justify-center">
              <div
                aria-hidden
                className="absolute inset-0 rounded-full opacity-40 blur-xl"
                style={{
                  background:
                    "radial-gradient(circle, rgba(99,102,241,0.6) 0%, transparent 70%)",
                }}
              />
              <span className="relative text-5xl">🐼</span>
            </div>
            <h1 className="text-3xl font-bold tracking-tight text-white">
              Pookify
            </h1>
            <p className="text-sm text-neutral-400">
              Enter your API key to access your dashboard
            </p>
          </div>

          <div className="w-full rounded-2xl border border-white/[0.08] bg-[#111] p-6 shadow-2xl shadow-black/40">
            <div className="flex flex-col gap-4">
              <div className="flex flex-col gap-1.5">
                <label
                  htmlFor="apiKey"
                  className="text-xs font-medium uppercase tracking-wider text-neutral-500"
                >
                  API Key
                </label>
                <div className="relative">
                  <Input
                    id="apiKey"
                    type={showKey ? "text" : "password"}
                    placeholder="ck_live_..."
                    autoComplete="off"
                    value={apiKey}
                    onChange={(e) => setApiKey(e.target.value)}
                    className="h-11 rounded-lg border-white/10 bg-white/[0.04] px-3.5 pr-10 font-mono text-sm text-white placeholder:text-neutral-600 focus-visible:border-indigo-500/50 focus-visible:ring-indigo-500/20"
                  />
                  <button
                    type="button"
                    onClick={() => setShowKey(!showKey)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-neutral-500 transition-colors hover:text-neutral-300"
                    tabIndex={-1}
                    aria-label={showKey ? "Hide key" : "Show key"}
                  >
                    {showKey ? (
                      <EyeOff className="h-4 w-4" />
                    ) : (
                      <Eye className="h-4 w-4" />
                    )}
                  </button>
                </div>
              </div>

              {error && (
                <div className="flex items-center gap-2 rounded-lg border border-red-500/20 bg-red-500/[0.08] px-3 py-2.5">
                  <div className="h-1.5 w-1.5 shrink-0 rounded-full bg-red-400" />
                  <p className="text-xs text-red-400">{error}</p>
                </div>
              )}

              <Button
                type="submit"
                disabled={!isFormValid || isLoading}
                className="h-11 w-full rounded-lg bg-indigo-600 text-sm font-semibold text-white transition-all hover:bg-indigo-500 disabled:opacity-40"
              >
                {isLoading ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  "Log In"
                )}
              </Button>
            </div>
          </div>

          <p className="mt-5 text-sm text-neutral-500">
            Don&apos;t have an account?{" "}
            <a
              href="/create"
              className="font-medium text-indigo-400 transition-colors hover:text-indigo-300"
            >
              Create your Pookie
            </a>
          </p>

          <p className="mt-8 text-xs text-neutral-600">
            Your AI companion, always on your side.
          </p>
        </form>
      </div>
    </div>
  );
}
