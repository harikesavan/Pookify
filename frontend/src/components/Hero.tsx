"use client";

import Link from "next/link";
import { ShineBorder } from "@/components/ui/hero-designali";
import { Plus } from "lucide-react";

import { Button } from "@/components/ui/button";

export const Hero = () => {
  return (
    <main className="overflow-hidden">
    <section id="home">
   <div className="absolute inset-0 max-md:hidden top-[400px] -z-10 h-[400px] w-full bg-transparent bg-[linear-gradient(to_right,#57534e_1px,transparent_1px),linear-gradient(to_bottom,#57534e_1px,transparent_1px)] bg-[size:3rem_3rem] opacity-20 [mask-image:radial-gradient(ellipse_80%_50%_at_50%_0%,#000_70%,transparent_110%)] dark:bg-[linear-gradient(to_right,#a8a29e_1px,transparent_1px),linear-gradient(to_bottom,#a8a29e_1px,transparent_1px)]"></div>
      <div className="flex flex-col items-center justify-center px-6 text-center">
        <div className="mx-auto max-w-5xl mt-16 md:mt-40">
                     <div className="border-text-red-500 relative mx-auto h-full bg-background border py-12 p-6 [mask-image:radial-gradient(800rem_96rem_at_center,white,transparent)]">

            <h1 className="flex flex-col text-center text-5xl font-semibold leading-none tracking-tight md:flex-col md:text-8xl lg:flex-row lg:text-8xl">
              <Plus
                strokeWidth={4}
                className="text-text-red-500 absolute -left-5 -top-5 h-10 w-10"
              />
              <Plus
                strokeWidth={4}
                className="text-text-red-500 absolute -bottom-5 -left-5 h-10 w-10"
              />
              <Plus
                strokeWidth={4}
                className="text-text-red-500 absolute -right-5 -top-5 h-10 w-10"
              />
              <Plus
                strokeWidth={4}
                className="text-text-red-500 absolute -bottom-5 -right-5 h-10 w-10"
              />
              <span>
                Create a <span className="text-red-500">Pookie</span> agent
                for your Company.
              </span>
            </h1>
            <div className="flex items-center mt-4 justify-center gap-1">
              <span className="relative flex h-3 w-3 items-center justify-center">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-500 opacity-75"></span>
                <span className="relative inline-flex h-2 w-2 rounded-full bg-green-500"></span>
              </span>
              <p className="text-xs text-green-500">Available Now</p>
            </div>
          </div>

          <h1 className="mt-8 text-2xl md:text-2xl">
            Meet the support agent that lives on your customer&#39;s{" "}
            <span className="text-red-500 font-bold">cursor.</span>
          </h1>

          <div className="flex items-center justify-center gap-3 pt-6">
            <Link href="/create">
              <ShineBorder
                borderWidth={3}
                className="border cursor-pointer h-auto w-auto p-2 bg-white/5 backdrop-blur-md dark:bg-black/5"
                color={["#FF007F", "#39FF14", "#00FFFF"]}
              >
                <Button size="lg" className="w-full rounded-xl h-14 px-8 text-lg">
                  Create your Pookie
                </Button>
              </ShineBorder>
            </Link>
            <Link href="#demo" scroll>
              <Button size="lg" variant="outline" className="rounded-xl h-14 px-8 text-lg">
                Watch demo
              </Button>
            </Link>
          </div>
        </div>
      </div>
    </section>
     </main>
  );
};
