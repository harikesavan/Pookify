import type { Metadata } from "next";
import { CreatePookie } from "@/components/CreatePookie";

export const metadata: Metadata = {
  title: "Create your Pookie — Pookify",
  description:
    "Set up a personalized support agent for your customers in under 5 minutes.",
};

export default function SignupPage() {
  return <CreatePookie />;
}
