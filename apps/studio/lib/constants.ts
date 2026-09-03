// The state an episode sits in while it waits on Boss.
//
// DECISIONS.md calls this "READY FOR LASEAN". There is no such value in the database.
// platform.work_status is: idea, research, ready, scheduled, in_progress, blocked,
// review, approved, completed, published, archived, killed.
//
// "review" is the enum value that means awaiting a human decision, and pipeline stage 12
// in system.start_media_assembly_line is literally named human_review, so that is what
// this maps to. studio.episodes.production_state (free text, defaults to "insight") is
// the other candidate if the pipeline ends up writing "ready_for_lasean" there instead.
// Changing this is one line, on purpose.
export const READY_FOR_LASEAN = "review" as const;

export const ORG_ID = "00000000-0000-0000-0000-000000000001";
