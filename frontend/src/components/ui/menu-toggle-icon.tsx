"use client";

import * as React from "react";
import { cn } from "@/lib/utils";

type MenuToggleIconProps = React.ComponentProps<"svg"> & {
  open: boolean;
  duration?: number;
};

export function MenuToggleIcon({
  open,
  duration = 300,
  className,
  ...props
}: MenuToggleIconProps) {
  const transitionStyle: React.CSSProperties = {
    transition: `transform ${duration}ms ease, opacity ${duration}ms ease`,
    transformBox: "fill-box",
    transformOrigin: "center",
  };

  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={cn("size-5", className)}
      {...props}
    >
      <line
        x1="4"
        y1="7"
        x2="20"
        y2="7"
        style={{
          ...transitionStyle,
          transform: open
            ? "translate(0, 5px) rotate(45deg)"
            : "translate(0, 0) rotate(0deg)",
        }}
      />
      <line
        x1="4"
        y1="12"
        x2="20"
        y2="12"
        style={{
          ...transitionStyle,
          opacity: open ? 0 : 1,
        }}
      />
      <line
        x1="4"
        y1="17"
        x2="20"
        y2="17"
        style={{
          ...transitionStyle,
          transform: open
            ? "translate(0, -5px) rotate(-45deg)"
            : "translate(0, 0) rotate(0deg)",
        }}
      />
    </svg>
  );
}
