// Ruling: empty states must say what will fill them, never render blank.
// Every one of these takes a "what fills this" line, not a generic "no data".

export function EmptyState({
  title,
  fills,
  hint,
}: {
  title: string;
  fills: string;
  hint?: string;
}) {
  return (
    <div className="rounded-[10px] border border-dashed border-line bg-panel2 px-5 py-8 text-center">
      <div className="disp text-[20px] text-txt">{title}</div>
      <p className="mx-auto mt-2 max-w-[440px] text-[12.5px] leading-relaxed text-dim">{fills}</p>
      {hint ? <p className="mono mt-3 text-[10.5px] tracking-[0.1em] text-dim">{hint}</p> : null}
    </div>
  );
}

export function ErrorState({ what }: { what: string }) {
  return (
    <div className="rounded-[10px] border border-dashed border-bad/50 bg-panel2 px-5 py-8 text-center">
      <div className="disp text-[20px] text-bad">COULD NOT LOAD {what.toUpperCase()}</div>
      <p className="mx-auto mt-2 max-w-[440px] text-[12.5px] leading-relaxed text-dim">
        The studio is up but this panel did not answer. Nothing is lost. Reload, and if it keeps
        happening the pipeline log will say why.
      </p>
    </div>
  );
}

// Shown when the session is valid but platform.organization_members has no row, so every
// owner_* RLS policy returns zero rows. Without this the whole app looks broken instead of
// unfinished, which is the single most likely first-login experience right now.
export function NoMembershipState({ email }: { email?: string }) {
  return (
    <div className="rounded-[10px] border border-dashed border-warn/50 bg-panel2 px-5 py-8 text-center">
      <div className="disp text-[20px] text-warn">YOU ARE SIGNED IN, BUT NOT IN THE ORG YET</div>
      <p className="mx-auto mt-2 max-w-[520px] text-[12.5px] leading-relaxed text-dim">
        {email ? <b className="text-txt">{email}</b> : "This account"} has a valid session, but no
        row in platform.organization_members, so every table returns zero rows by policy. Nothing
        is broken and nothing is missing. Onboarding step 1 creates that row; until it runs, the
        studio has nothing it is allowed to show you.
      </p>
      <p className="mono mt-3 text-[10.5px] tracking-[0.1em] text-dim">
        RLS IS DOING EXACTLY WHAT IT SHOULD
      </p>
    </div>
  );
}
