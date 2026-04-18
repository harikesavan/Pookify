"use client";

import * as React from "react";
import { createPortal } from "react-dom";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  PlayCircle,
  Sparkles,
  Workflow,
  Users,
  Star,
  Handshake,
  FileText,
  Shield,
  Leaf,
  HelpCircle,
  type LucideIcon,
} from "lucide-react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { MenuToggleIcon } from "@/components/ui/menu-toggle-icon";
import {
  NavigationMenu,
  NavigationMenuContent,
  NavigationMenuItem,
  NavigationMenuLink,
  NavigationMenuList,
  NavigationMenuTrigger,
} from "@/components/ui/navigation-menu";

type LinkItem = {
  title: string;
  href: string;
  icon: LucideIcon;
  description?: string;
};

export function Header() {
  const [open, setOpen] = React.useState(false);
  const scrolled = useScroll(10);
  const pathname = usePathname();

  React.useEffect(() => {
    if (open) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }
    return () => {
      document.body.style.overflow = "";
    };
  }, [open]);

  return (
    <header
      className={cn(
        "sticky top-0 z-50 w-full border-b border-border bg-background/80 supports-[backdrop-filter]:bg-background/60 backdrop-blur-lg transition-shadow",
        scrolled && "shadow-sm"
      )}
    >
      <nav className="mx-auto flex h-20 w-full max-w-5xl items-center justify-between px-4">
        <div className="flex items-center gap-8">
          <Link
            href="/"
            onClick={(event) => {
              if (pathname === "/") {
                event.preventDefault();
                window.scrollTo({ top: 0, behavior: "smooth" });
              }
            }}
            className="hover:bg-accent flex items-center gap-2 rounded-md px-2 py-1.5"
            aria-label="Pookify home"
          >
            <span className="text-3xl leading-none">🐼</span>
            <span className="text-lg font-semibold tracking-tight">Pookify</span>
          </Link>
          <NavigationMenu className="hidden md:flex">
            <NavigationMenuList>
              <NavigationMenuItem>
                <NavigationMenuTrigger className="bg-transparent h-11 px-3.5 text-base">
                  Using Pookify
                </NavigationMenuTrigger>
                <NavigationMenuContent className="bg-background p-1 pr-1.5">
                  <ul className="bg-popover grid w-lg grid-cols-2 gap-2 rounded-md border p-2 shadow">
                    {usingPookifyLinks.map((item) => (
                      <li key={item.title}>
                        <ListItem {...item} />
                      </li>
                    ))}
                  </ul>
                  <div className="p-2">
                    <p className="text-muted-foreground text-sm">
                      Ready to ship one?{" "}
                      <a
                        href="/create"
                        className="text-foreground font-medium hover:underline"
                      >
                        Create your Pookie
                      </a>
                    </p>
                  </div>
                </NavigationMenuContent>
              </NavigationMenuItem>

              <NavigationMenuItem>
                <NavigationMenuTrigger className="bg-transparent h-11 px-3.5 text-base">
                  Company
                </NavigationMenuTrigger>
                <NavigationMenuContent className="bg-background p-1 pr-1.5 pb-1.5">
                  <div className="grid w-lg grid-cols-2 gap-2">
                    <ul className="bg-popover space-y-2 rounded-md border p-2 shadow">
                      {companyLinks.map((item) => (
                        <li key={item.title}>
                          <ListItem {...item} />
                        </li>
                      ))}
                    </ul>
                    <ul className="space-y-2 p-3">
                      {companyLegalLinks.map((item) => (
                        <li key={item.title}>
                          <NavigationMenuLink
                            href={item.href}
                            className="hover:bg-accent flex flex-row items-center gap-x-2 rounded-md p-2"
                          >
                            <item.icon className="text-foreground size-4" />
                            <span className="font-medium">{item.title}</span>
                          </NavigationMenuLink>
                        </li>
                      ))}
                    </ul>
                  </div>
                </NavigationMenuContent>
              </NavigationMenuItem>

              <NavigationMenuItem>
                <NavigationMenuLink
                  href="#pricing"
                  className="hover:bg-muted inline-flex h-11 items-center rounded-lg px-3.5 py-1.5 text-base font-medium"
                >
                  Pricing
                </NavigationMenuLink>
              </NavigationMenuItem>
            </NavigationMenuList>
          </NavigationMenu>
        </div>
        <div className="hidden items-center gap-2 md:flex">
          <Button asChild size="lg" className="h-11 px-5 text-base">
            <a href="/create">Get Started</a>
          </Button>
        </div>
        <Button
          size="icon"
          variant="outline"
          onClick={() => setOpen(!open)}
          className="md:hidden"
          aria-expanded={open}
          aria-controls="mobile-menu"
          aria-label="Toggle menu"
        >
          <MenuToggleIcon open={open} className="size-5" duration={300} />
        </Button>
      </nav>
      <MobileMenu
        open={open}
        className="flex flex-col justify-between gap-2 overflow-y-auto"
      >
        <div className="flex w-full flex-col gap-y-2">
          <span className="text-muted-foreground text-sm">Using Pookify</span>
          {usingPookifyLinks.map((link) => (
            <MobileListItem key={link.title} {...link} />
          ))}
          <span className="text-muted-foreground mt-4 text-sm">Company</span>
          {companyLinks.map((link) => (
            <MobileListItem key={link.title} {...link} />
          ))}
          {companyLegalLinks.map((link) => (
            <MobileListItem key={link.title} {...link} />
          ))}
        </div>
        <div className="flex flex-col gap-2">
          <Button className="w-full" asChild>
            <a href="/create">Get Started</a>
          </Button>
        </div>
      </MobileMenu>
    </header>
  );
}

type MobileMenuProps = React.ComponentProps<"div"> & {
  open: boolean;
};

function MobileMenu({ open, children, className, ...props }: MobileMenuProps) {
  if (!open || typeof window === "undefined") return null;

  return createPortal(
    <div
      id="mobile-menu"
      className={cn(
        "bg-background/95 supports-[backdrop-filter]:bg-background/50 backdrop-blur-lg",
        "fixed top-20 right-0 bottom-0 left-0 z-40 flex flex-col overflow-hidden border-y md:hidden"
      )}
    >
      <div
        data-slot={open ? "open" : "closed"}
        className={cn(
          "data-[slot=open]:animate-in data-[slot=open]:zoom-in-97 ease-out",
          "size-full p-4",
          className
        )}
        {...props}
      >
        {children}
      </div>
    </div>,
    document.body
  );
}

function ListItem({
  title,
  description,
  icon: Icon,
  href,
  className,
}: LinkItem & { className?: string }) {
  return (
    <NavigationMenuLink
      href={href}
      className={cn(
        "hover:bg-accent hover:text-accent-foreground focus:bg-accent focus:text-accent-foreground flex w-full flex-row gap-x-2 rounded-sm p-2",
        className
      )}
    >
      <div className="bg-background/40 flex aspect-square size-12 items-center justify-center rounded-md border shadow-sm">
        <Icon className="text-foreground size-5" />
      </div>
      <div className="flex flex-col items-start justify-center">
        <span className="font-medium">{title}</span>
        {description ? (
          <span className="text-muted-foreground text-xs">{description}</span>
        ) : null}
      </div>
    </NavigationMenuLink>
  );
}

function MobileListItem({
  title,
  description,
  icon: Icon,
  href,
}: LinkItem) {
  return (
    <a
      href={href}
      className="hover:bg-accent focus:bg-accent flex w-full flex-row gap-x-2 rounded-sm p-2"
    >
      <div className="bg-background/40 flex aspect-square size-12 items-center justify-center rounded-md border shadow-sm">
        <Icon className="text-foreground size-5" />
      </div>
      <div className="flex flex-col items-start justify-center">
        <span className="font-medium">{title}</span>
        {description ? (
          <span className="text-muted-foreground text-xs">{description}</span>
        ) : null}
      </div>
    </a>
  );
}

const usingPookifyLinks: LinkItem[] = [
  {
    title: "Demo Video",
    href: "#demo",
    description: "Watch Pookie guide a real customer end to end",
    icon: PlayCircle,
  },
  {
    title: "Features",
    href: "#features",
    description: "Voice, chat, and cursor guidance grounded in your docs",
    icon: Sparkles,
  },
  {
    title: "How It Works",
    href: "#how-it-works",
    description: "From docs upload to a personalized download link",
    icon: Workflow,
  },
];

const companyLinks: LinkItem[] = [
  {
    title: "About Us",
    href: "#",
    description: "The team behind Pookify",
    icon: Users,
  },
  {
    title: "Customer Stories",
    href: "#",
    description: "See how teams resolve support in seconds",
    icon: Star,
  },
  {
    title: "Partnerships",
    href: "#",
    description: "Integrate Pookify into your product",
    icon: Handshake,
  },
];

const companyLegalLinks: LinkItem[] = [
  { title: "Terms of Service", href: "#", icon: FileText },
  { title: "Privacy Policy", href: "#", icon: Shield },
  { title: "Blog", href: "#", icon: Leaf },
  { title: "Help Center", href: "#", icon: HelpCircle },
];

function useScroll(threshold: number) {
  const [scrolled, setScrolled] = React.useState(false);

  const onScroll = React.useCallback(() => {
    setScrolled(window.scrollY > threshold);
  }, [threshold]);

  React.useEffect(() => {
    window.addEventListener("scroll", onScroll);
    return () => window.removeEventListener("scroll", onScroll);
  }, [onScroll]);

  React.useEffect(() => {
    onScroll();
  }, [onScroll]);

  return scrolled;
}
