"use client";

import { usePathname } from "next/navigation";
import { WalletButton } from "@/components/WalletButton";

// Every page of the product, in the order a visitor needs them: find an
// agent, see the evidence behind the listing, then the pages that only
// matter once they have a wallet. The same list is in the footer, so no
// page is reachable only by typing its address.
const LINKS = [
  { href: "/", label: "Agents" },
  { href: "/stats", label: "Registry health" },
  { href: "/methodology", label: "Methodology" },
  { href: "/jobs", label: "My hires" },
  { href: "/sessions", label: "Spend caps" },
];

function isActive(pathname: string, href: string): boolean {
  if (href === "/") return pathname === "/" || pathname.startsWith("/agents/");
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function SiteHeader() {
  const pathname = usePathname() ?? "/";
  return (
    <header className="border-b border-ink/15 bg-paper">
      <div className="mx-auto flex max-w-[1200px] flex-wrap items-center gap-x-6 gap-y-2 px-8 py-3">
        <a
          href="/"
          className="font-display text-lg leading-none text-ink hover:opacity-80"
          aria-label="TrustList home"
        >
          TrustList
          <span className="eyebrow ml-2 align-middle text-dormant">
            ERC-8004 / BSC
          </span>
        </a>
        <nav aria-label="Site" className="flex flex-wrap items-center gap-1">
          {LINKS.map((l) => {
            const active = isActive(pathname, l.href);
            return (
              <a
                key={l.href}
                href={l.href}
                aria-current={active ? "page" : undefined}
                className={`eyebrow rounded px-2.5 py-1.5 transition-colors ${
                  active
                    ? "bg-ink text-paper"
                    : "text-ink/70 hover:bg-ink/5 hover:text-ink"
                }`}
              >
                {l.label}
              </a>
            );
          })}
        </nav>
        <div className="ml-auto flex items-center gap-4">
          <a
            href="https://github.com/big14way/Trustlist"
            target="_blank"
            rel="noreferrer"
            className="eyebrow text-ink/70 hover:text-ink"
          >
            Source
          </a>
          <WalletButton />
        </div>
      </div>
    </header>
  );
}
