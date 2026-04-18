"use client";

import { useEffect } from "react";

export function SmoothAnchorScroll() {
  useEffect(() => {
    const handler = (event: MouseEvent) => {
      if (event.button !== 0) return;
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

      const target = event.target as HTMLElement | null;
      const anchor = target?.closest<HTMLAnchorElement>('a[href^="#"]');
      if (!anchor) return;

      const href = anchor.getAttribute("href");
      if (!href || href === "#") return;

      const id = decodeURIComponent(href.slice(1));
      const element = document.getElementById(id);
      if (!element) return;

      event.preventDefault();
      event.stopPropagation();
      element.scrollIntoView({ behavior: "smooth", block: "start" });
      history.replaceState(null, "", href);
    };

    document.addEventListener("click", handler, { capture: true });
    return () =>
      document.removeEventListener("click", handler, { capture: true });
  }, []);

  return null;
}
