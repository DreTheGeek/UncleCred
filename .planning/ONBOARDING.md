# ONBOARDING: first login to first episode (the click law applied to day one)

Boss's ruling 2026-09-02: the first login is a complete, detailed onboarding that ends with content being made. Every step tells him what he is doing, why, and what comes out the other side. Every step is a picker or a tap, never a form. Progress is saved per step in platform.organizations.metadata.onboarding so a refresh resumes.

## The nine steps
1. WELCOME. What this studio is, in his words: an autonomous animated show about credit that publishes itself and learns. One button: Start.
2. THE SHOW. Universe name (prefilled Uncle Cred), premise (prefilled), the product the show sells ({PRODUCT_NAME}, required here, the one text field in the whole flow), the audience (prefilled: people denied, people building, people funding a business). Outcome shown: the CTA frame every episode ends on.
3. THE CAST. Five character cards, each with role, personality, relationships, prohibited changes already written. Tap to confirm each, or edit inline. Outcome: canon rows in studio.visual_characters.
4. THE LOOK. For Uncle Cred: upload the reference shoot (30 to 60 photos), tap the Face Master, LoRA trains in the background. For every other character: a grid of generated candidates (FLUX.2 via the router), tap the one that is them. That image becomes the canonical front reference, the turnaround and expression sheets generate from it, LoRA v1 trains in the background. Outcome: a locked face per character.
5. THE VOICE. Per character, three generated voice candidates plus paste an ElevenLabs voice_id if one exists (Uncle Cred prefilled, locked). Tap one. Outcome: voice_id locked in canon.
6. THE STORY. The season arc as a one screen story bible: where the show starts, the midpoint turn, the ending everyone is moving toward, and each character's arc. Prefilled by the showrunner from the credit KB and the cast, editable inline, one tap to approve. Outcome: studio.content_series rows with tracks and a locked ending, so every episode knows where the story is going.
7. THE PLATFORMS. Which of TikTok, Reels, Shorts, Facebook, LinkedIn are on (all prefilled on), the posting cadence (prefilled 1 per day, Boss taps 1, 2, or 3), best times prefilled from kb-algorithms. Blotato connection status shown. Outcome: publishing calendar policy.
8. THE RULES. What the show never does, already written: no legal advice, no guarantees, no real customer testimonials, disclosure on every post. Read only, one tap to acknowledge. Outcome: guardrails visibly on.
9. FIRST EPISODE. The studio generates the first episode blueprint live on screen while he watches (title, hook, beats, claims verifying one by one). Ends on the Review Room with Episode 1 waiting. Outcome: he approves his first episode inside onboarding.

## What runs behind it
- Steps 3 to 6 write canon, so the showrunner has everything it needs before step 9.
- The credit knowledge base is already loaded (7,424 chunks from Credit Brothers) and embedding, so step 9's claim verifier has sources on day one.
- Step 6 is the story bible organ: universe -> seasons -> arcs -> episodes. The ending is written first. Episodes are scheduled against the arc, not picked at random. This is what makes it a drama and not a feed.

## Gate
A new owner goes from login to an approved Episode 1 without typing anything except the product name. Timed. Over 20 minutes wall time means a step is too heavy.
