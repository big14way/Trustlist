import { SessionsClient } from "./SessionsClient";

export const dynamic = "force-dynamic";

export default function SessionsPage() {
  return (
    <main className="mx-auto max-w-3xl px-6 py-12">
      <p className="eyebrow text-dormant">SESSIONS</p>
      <h1 className="font-display mt-2 text-3xl">
        A spending cap the chain enforces
      </h1>
      <p className="mt-4 text-sm text-ink/80">
        An agent that can spend your money needs a limit you can see and end.
        A session here is a scoped key on an Altana smart account: it may call
        one contract, it may move at most the amount you set in each period,
        and it stops at the expiry you choose. The account contract enforces
        all three, so a call outside them reverts rather than relying on the
        agent to behave.
      </p>
      <p className="mt-3 text-sm text-ink/80">
        Revoking is one transaction and takes effect immediately. Nothing here
        holds your principal.
      </p>
      <SessionsClient />
    </main>
  );
}
