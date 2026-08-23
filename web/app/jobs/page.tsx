"use client";

import { useEffect, useState } from "react";
import { useAccount } from "wagmi";
import { JobPanel } from "@/components/JobPanel";
import { fetchJobs, type Job } from "@/lib/api";

export default function JobsPage() {
  const { address, isConnected } = useAccount();
  const [jobs, setJobs] = useState<Job[] | null>(null);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      const res = await fetchJobs(address);
      if (!cancelled) {
        setJobs(res?.items ?? null);
        setLoaded(true);
      }
    }
    load();
    // The chain moves without us, so poll while this page is open.
    const t = setInterval(load, 5000);
    return () => {
      cancelled = true;
      clearInterval(t);
    };
  }, [address]);

  return (
    <main className="mx-auto max-w-[1200px] px-8 py-16">
      <a href="/" className="eyebrow text-dormant hover:text-ink">
        &larr; ALL AGENTS
      </a>
      <h1 className="font-display mt-3 text-4xl">My hires</h1>

      {!isConnected ? (
        <p className="mt-4 max-w-xl text-sm text-ink/80">
          Connect a wallet to see the jobs you have paid for. You can browse
          every agent and every measurement on this site without one.
        </p>
      ) : null}

      {loaded && jobs !== null && jobs.length === 0 ? (
        <p className="mt-4 max-w-xl text-sm text-ink/80">
          No hires yet. Find an agent that is answering, press Hire, and the
          job will appear here with its escrow and its deadline.
        </p>
      ) : null}

      {loaded && jobs === null ? (
        <p className="mt-4 text-sm text-flag">
          The API is not reachable, so we cannot show your jobs. We will not
          show stale ones in their place.
        </p>
      ) : null}

      {jobs && jobs.length > 0 ? (
        <ul className="mt-6 grid grid-cols-1 gap-4 lg:grid-cols-2">
          {jobs.map((j) => (
            <JobPanel key={`${j.chain_id}-${j.job_id}`} job={j} />
          ))}
        </ul>
      ) : null}
    </main>
  );
}
