"use client";

import { LayoutGroup, motion } from "motion/react";
import { PlayCircle } from "lucide-react";
import { TextRotate } from "@/components/ui/text-rotate";

export const Demo = () => {
  return (
    <section id="demo" className="w-full scroll-mt-8 px-6 pt-48 pb-16 md:pt-32 md:pb-20">
      <div className="mx-auto flex max-w-5xl flex-col items-center">
        <span className="text-muted-foreground text-lg font-semibold uppercase tracking-[0.25em] md:text-xl">
          Demo
        </span>

        <LayoutGroup>
          <motion.h2
            layout
            className="mt-4 flex items-center justify-center whitespace-pre py-5 text-3xl font-semibold leading-none sm:text-5xl md:text-6xl"
            transition={{ type: "spring", damping: 30, stiffness: 400 }}
          >
            <motion.span
              layout
              className="py-0.5 sm:py-1 md:py-2"
              transition={{ type: "spring", damping: 30, stiffness: 400 }}
            >
              Watch Pookie{" "}
            </motion.span>
            <motion.span layout className="flex whitespace-pre">
              <TextRotate
                texts={["answer", "guide", "point", "teach", "resolve"]}
                mainClassName="text-white px-2 sm:px-2 md:px-3 bg-red-500 overflow-hidden py-0.5 sm:py-1 md:py-2 justify-center rounded-lg"
                staggerFrom="last"
                initial={{ y: "100%" }}
                animate={{ y: 0 }}
                exit={{ y: "-120%" }}
                staggerDuration={0.025}
                splitLevelClassName="overflow-hidden pb-0.5 sm:pb-1 md:pb-1"
                transition={{ type: "spring", damping: 30, stiffness: 400 }}
                rotationInterval={2000}
              />
            </motion.span>
          </motion.h2>
        </LayoutGroup>

        <div className="relative mt-8 w-full max-w-3xl">
          <div className="group relative aspect-video w-full overflow-hidden rounded-2xl border bg-muted/40 shadow-sm">
            <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(239,68,68,0.08),transparent_60%)]" />
            <button
              type="button"
              className="absolute inset-0 flex flex-col items-center justify-center gap-3 text-foreground transition-transform group-hover:scale-[1.02]"
              aria-label="Play demo video"
            >
              <span className="flex h-20 w-20 items-center justify-center rounded-full bg-background/80 shadow-lg ring-1 ring-border backdrop-blur-sm">
                <PlayCircle className="h-10 w-10 text-red-500" strokeWidth={1.5} />
              </span>
              <span className="text-muted-foreground text-sm">
                Demo video coming soon
              </span>
            </button>
          </div>
        </div>
      </div>
    </section>
  );
};
