import { fetchStats } from "@/lib/api-server";

// The footer carries the same navigation as the header and the status line
// SPEC section 30.7 asks for: how far behind head the index is and when the
// last scoring pass ran. A product that admits its own lag reads as
// trustworthy; one that hides it reads as stale.
const LINKS = [
  { href: "/", label: "Agents" },
  { href: "/stats", label: "Registry health" },
  { href: "/methodology", label: "How the numbers are made" },
  { href: "/jobs", label: "My hires" },
  { href: "/sessions", label: "Spend caps" },
  { href: "https://github.com/big14way/Trustlist", label: "Source" },
];

export async function SiteFooter() {
  const stats = await fetchStats();
  const scored = stats?.computed_at
    ? `${stats.computed_at.slice(0, 16).replace("T", " ")}Z`
    : null;
  return (
    <footer className="mt-16 bg-depth text-paper">
      <div className="mx-auto max-w-[1200px] px-8 py-8">
        <nav aria-label="Footer" className="flex flex-wrap gap-x-6 gap-y-2">
          {LINKS.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="eyebrow text-paper/80 hover:text-paper"
              {...(l.href.startsWith("http")
                ? { target: "_blank", rel: "noreferrer" }
                : {})}
            >
              {l.label}
            </a>
          ))}
        </nav>
        <p className="font-data mt-5 text-xs text-paper/60">
          {stats && stats.indexed_to_block
            ? `indexed to block ${stats.indexed_to_block.toLocaleString()}${
                scored ? ` · last scoring pass ${scored}` : ""
              } · `
            : "index status unavailable · "}
          Every number on this site is a database read from our own indexer
          and prober. Nothing is sampled, estimated, or carried over from a
          previous run.
        </p>
        <p className="font-data mt-2 text-xs text-paper/60">
          TrustList, an ERC-8004 agent marketplace on BNB Smart Chain. Built
          for the BNB Chain Build the Era hackathon.
        </p>
      </div>
    </footer>
  );
}
