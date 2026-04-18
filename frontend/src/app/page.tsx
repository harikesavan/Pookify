import { Hero } from "@/components/Hero";
import { Demo } from "@/components/Demo";
import { Footer } from "@/components/Footer";

export default function Home() {
  return (
    <>
      <Hero />
      <Demo />
      <section className="h-screen w-full" aria-hidden="true" />
      <Footer />
    </>
  );
}
