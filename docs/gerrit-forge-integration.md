# Gerrit forge integration

This note is the design reasoning for giving Firstmate a forge axis, worked through Gerrit because Gerrit is the case that forces it.
It is written for whoever integrates a forge with Firstmate rather than for the operator of any one fleet, so it argues about axes, vocabulary, and ownership, and never about which projects should be registered how.
Several questions in it are the captain's to settle and are left open on purpose; they are collected at the end.

The mechanics it reasons about have their own owners.
[`bin/fm-pr-lib.sh`](../bin/fm-pr-lib.sh) owns the provider-tagged identity and the merge-poll artifacts, [`bin/fm-pr-merge.sh`](../bin/fm-pr-merge.sh) owns merging, [`bin/fm-project-mode.sh`](../bin/fm-project-mode.sh) owns the registered delivery posture, and [`bin/fm-dod-lib.sh`](../bin/fm-dod-lib.sh) owns what a delivery mode tells a worker.
A forge field in the registry and the delivery-mode rules that consume it are still in review and are described here as a design, not as current behavior.

## 1. Gerrit is not a forge variant

GitHub and GitLab differ in vocabulary, URL shape, and the API each one offers.
Gerrit differs in what the reviewed object *is*, which is not a difference an adapter can absorb.

Branch-shaped review, which is what GitHub and GitLab do, makes the reviewed object a branch plus a request to merge it.
Its identity is the pair of repository and number.
Its history is the branch's commits, preserved as pushed, and a new revision is a new commit appended to the branch.
"The same change" means the same pull-request number, and the content under that number is whatever the branch's tip is now.

Change-shaped review, which is what Gerrit does, makes the reviewed object a single commit carrying a `Change-Id` footer.
Its identity is that footer; the server-assigned change number is only a short handle for it.
A new revision is a new *patch set*: an amended commit that replaces the previous one rather than following it.
"The same change" means the same `Change-Id`, across commits with different hashes and different trees.

Three things follow, and each one breaks an assumption that branch-shaped review lets a tool make for free.

Identity is content-independent and survives rewriting.
A pull request's identity is attached to a ref that accumulates; a change's identity is attached to a footer that travels through `git commit --amend` and `git rebase` unharmed.
The inverse is the sharp edge: regenerating a `Change-Id` does not produce a new revision of the change, it produces a *different* change, and the review history of the original is orphaned.
So the operation that is routine and safe on a branch - rewrite the commit, force-push, same pull request - is the operation that silently discards review state here, and it discards it through a commit-message footer rather than through anything a tool would think to guard.

History is replaced rather than preserved.
There is no accumulated branch on the server whose commits land; there is a sequence of patch sets of which the last one is what merges.
An integration that wants to show "what changed since the last review" is asking a question about two patch sets, not about commits added to a branch.

A branch is not the unit of anything.
A local branch of three commits is three changes related by a parent chain, not one reviewable object.
This is the point at which the branch-shaped assumption stops being a vocabulary mismatch and starts being an arity mismatch: one worker branch no longer maps to one reviewable thing.

What does *not* differ is worth stating, because it bounds the problem.
Reading review state after publication fits Firstmate's existing record with no new shape.
`bin/fm-pr-lib.sh` already carries a provider-tagged identity of provider, url, host, path, and number, because GitLab had already forced host and an arbitrarily nested path into it, and a Gerrit change URL populates those same fields.
The break is not in watching a change.
It is in making one.

## 2. The vocabulary map

| Term | Branch-shaped (GitHub, GitLab) | Change-shaped (Gerrit) | What that costs an integration |
|---|---|---|---|
| publish | push the branch, then open a pull request: two steps, the second one a forge API call through a vendor CLI | one `git push HEAD:refs/for/<branch>`: creating the change *is* the push | the publish step is a vendor CLI on one side and plain git on the other, so it cannot be a single parameterized command |
| review | comments and approvals attached to the pull request, plus forge CI reporting check runs against the branch | comments and label votes (`Code-Review`, `Verified`) attached to the change; CI votes a label | "checks green" is a label value rather than a set of check runs, and the pipeline's CI step has no check runs to watch |
| merged | the pull request is closed and its content is in the base branch, usually squashed | the change is *submitted*, and its status becomes `MERGED` | "merge" names an action Firstmate performs, while "submit" names one it must not - see section 4 |
| head | a commit hash that identifies what was reviewed and stays valid | a patch-set revision, and every amend or rebase produces a new one | a recorded head quietly becomes the *previously* reviewed content, so a Gerrit task records none |
| number | repository-scoped on GitHub, project-scoped on GitLab; addressing it needs owner and repository, or host and path | server-global; with the host pinned, the number alone names the change | the project path is not part of a Gerrit read at all |

The head row is the one that bites hardest, because it fails quietly.
On GitHub a recorded head stays true: it is the commit that was reviewed and, absent a new push, the commit that will merge.
On Gerrit the same recorded value goes stale on every amend, and a stale value does not look stale - it looks like a perfectly well-formed revision, because it is one.
Anything that compares against it is then comparing against an earlier patch set while believing it is comparing against the change.

### Where today's mode names mislead

Not one of Firstmate's three delivery-mode names refers to a stopping point, and each misses it differently.

`direct-PR` names an artifact.
On a forge with no pull request the name has no referent at all, which is why the natural first rule is to refuse the combination rather than give it a meaning: there is nothing to rename it to from inside the mode's own vocabulary.
But the refusal follows from the name, not from anything the mode does - "push your work and stop without running the pipeline" is a coherent instruction on Gerrit.

`no-mistakes` names a pipeline.
It happens not to name an artifact, which is the only reason it survives the transplant unmodified.

`local-only` names a place, and it is the closest of the three to honest, because where this mode stops is a place.

So the name that blocks Gerrit is blocking it on a noun, and the name that lets Gerrit through does so by accident.
That is a symptom.
Section 3 is the diagnosis.

## 3. The axes and the composition test

Three properties are in play, and they answer three different questions.

- **Mode** is where the worker stops.
- **Forge** is what the publication artifact is, and therefore which tool makes it.
- **Shape** is whether a task's work is published as a stack of changes or as one squashed change.

One test decides whether a property sits on the right axis.
**An axis in the right place composes with every value of the others without special cases.**
A candidate that needs a new value each time some other axis gains one is not an axis at all; it is that other axis wearing this one's name.

### The candidate that fails it

An earlier candidate made shape a mode: `direct-PR` would mean a topic'd stack, and a new `direct-change` would mean a single squashed change.
It fails immediately.
`no-mistakes` needs the same distinction the moment it ships to Gerrit, so it splits too; `local-only` needs it as well, since a ready branch is already either one commit or several.
Three modes become six, and every mode added afterwards arrives needing two names instead of one.
Shape is not varying *with* mode there, it is varying *inside* every value of mode, which is the signature of a property that has been folded into the wrong axis.

### Why shape is not the forge either

Shape already exists on GitHub, it predates Gerrit entirely, and it is load-bearing in four places today:

- `bin/fm-pr-merge.sh` defaults a GitHub merge to `--squash` when the caller selects no method.
- `bin/fm-fleet-sync.sh`'s branch pruning reasons about it explicitly, dropping the ancestry check on the grounds that pull requests in this fleet are squash-merged, so a merged branch is never an ancestor and such a check would prune nothing.
- `bin/fm-teardown.sh`'s landed-work test accepts content present in the default branch precisely because a squash collapses the branch's commits and per-commit patch identities stop matching.
- `bin/fm-ff-lib.sh` reconciles a clean secondmate divergence through a three-way tree proof, as happens after an upstream squash merge.

It appears nowhere in the registry.
A property that four mechanisms depend on, across pruning, teardown safety, merging, and secondmate convergence, and that no project has ever declared, is not a Gerrit concept arriving with Gerrit.
It is an existing axis that has been pinned to one value by assumption for long enough to become invisible.
That it survived being invisible says how rarely it varies, not where it belongs.

### The hinge: pre-publication versus post-publication

Firstmate has no forge property for GitLab and has never needed one.
`bin/fm-pr-lib.sh` derives the provider from the merge-request URL *after the fact*, tagging the stored identity with it, and the work is handed to `glab`; workers create the artifact with the vendor CLI, and `bin/fm-pr-merge.sh` merges through that same CLI.
Firstmate owns none of the mechanics.
Every forge decision it makes, it makes with the URL already in hand.

Gerrit breaks that in exactly one way.
The forge must be known **before** anything is published, because there is no pull request to open.
A worker cannot be told "push your branch and open a pull request, and we will work out the forge from the URL afterwards": the instruction it needs differs before any URL exists, between a push to `refs/for/<branch>` and a push followed by a `gh-axi` call.

That is the whole of what a `forge=` annotation buys: **a pre-publication signal, where GitLab only ever needed a post-publication one.**
Everything downstream of publication - watching, reading state, reporting - continues to work off the provider tag derived from the URL, exactly as it does for GitLab, because by then the URL exists.

This also frames a live question this note does not settle: should the forge be *detected* from the project's origin rather than declared in the registry?
Every other forge effectively is detected, in the sense that the URL tells Firstmate what it is dealing with; the intake guidance proposed in the same in-review delivery-mode design treats a protocol fact such as an SSH remote on port 29418 or a `refs/for/<branch>` push target as good evidence to propose the binding while refusing to infer it later.
What a declaration buys over detection is that the signal is in the brief at scaffold time, with no clone read and no network call, which is where a pre-publication signal has to be.
What it costs is a second source of truth that can disagree with the remote, and disagree silently, since a mis-declared forge produces a brief that is internally consistent and wrong.

### Applying "mode is where the worker stops"

Read the modes as stopping points rather than as artifacts and they line up cleanly:

- `local-only` stops at a ready branch and publishes nothing. Nothing about a forge applies, because no artifact is made: `bin/fm-merge-local.sh` fast-forwards the project's *local* default branch, and the intake guidance already allows a `local-only` project to have no remote at all.
- `direct-PR` publishes without the pipeline.
- `no-mistakes` runs the pipeline, then publishes.

On that reading the forge composes with the two modes that publish and is meaningless on the one that does not.
That inverts both rules the delivery-mode design currently carries, which permit `local-only forge=gerrit` as an annotation that changes nothing and refuse `direct-PR forge=gerrit` outright.
The composition test says that is backwards on both counts: the refusal lands on the combination that has a meaning, and the permission on the combination that does not.

The refusal reads as reasonable only because of the name.
"That mode's definition of done is a pull request this forge does not have" is a true statement about the string `direct-PR` and not about the stopping point it names, and section 2 is why those two came apart.

The permission is not merely useless, which is worth being plain about, because an inert annotation in a brief is not inert at landing.
`local-only`'s configured landing is a guarded fast-forward of the project's local default branch.
On a project whose changes are supposed to reach a review server, that landing advances local `main` with content the server has never seen, and the annotation that was supposed to record "this is a Gerrit project" is the one thing in the posture that does not get consulted.

## 4. What Gerrit makes structurally impossible

Three things, and they are not impossible in the same way.
Flattening them into one list of missing features would be the wrong lesson.

**There is no pull-request object.**
Nothing to open, nothing that holds a number before the push, and nothing that carries a description separate from the commit.
The commit message *is* the review description and the `Change-Id` footer *is* the identity, so any design that wants a handle on the reviewed thing before that thing exists cannot have one.
This is a property of Gerrit and no amount of tooling changes it.

**There is no branch on the remote.**
`refs/for/<branch>` is a magic ref rather than a destination: the push creates or updates a change and leaves behind no ref a later fetch can see.
Every mechanism that reasons about a remote branch therefore has no counterpart here - the gone-upstream prune in `bin/fm-fleet-sync.sh`, the remote-reachability leg of `bin/fm-teardown.sh`'s landed-work test, and the `refs/pull/<n>/head` fetch in `bin/fm-review-diff.sh`.
Each of those already has a fallback that reasons about content or about the local branch, and on Gerrit the fallback is not a fallback, it is the only path.
That raises the stakes on the content leg of the landed-work test specifically, since it becomes the sole proof that unlanded work is not about to be discarded.
This is also a property of Gerrit.

**No tool available today can submit.**
`gerrit-axi` is read-only by construction.
Its README states the boundary - "v0.1 is read-only. It never votes, replies, sets reviewers or topics, submits, abandons, or pushes. Every operation is a query." - and its own test suite enforces it by grepping for mutating REST verbs and mutating SSH subcommands.
Its entire surface is `status`, `show`, `comments`, and `auth status`.
But the refusal Firstmate itself carries is stated as policy rather than capability.
Submitting a change means first recording a `Code-Review+2`, and that vote is a positive attributed claim that a named human approved, read as such by colleagues and by any audit of the repository.
A server that permits self-approval is exactly what makes this a boundary Firstmate chooses rather than one it merely runs into.

So the first two are Gerrit's shape, and the third is the current toolchain plus a deliberate policy.
Only the toolchain half could be removed by writing code, and whether it should be is section 5.

## 5. Where responsibility sits: Firstmate or the forge tool

Start from the division that already works.
For GitLab, Firstmate knows which tool and calls it, the tool knows the forge, and Firstmate owns none of the mechanics.
Not the artifact's creation, not its URL shape beyond parsing it back into an identity, not the merge command.
The forge property Firstmate carries for GitLab is no property at all, only a tag read off a URL.

The question this raises for Gerrit is whether the stack-versus-squash glue belongs on the same side of that line.

The case for moving it into the forge tool is that it is forge mechanics through and through.
Producing a stack of changes under a topic means giving each commit a `Change-Id`, pushing once to `refs/for/<branch>` with a topic option, and reasoning about the parent chain that makes the stack a stack.
None of that is a Firstmate concept, and every line of it Firstmate writes is a line Firstmate maintains on behalf of one forge.
Move it and Firstmate's job shrinks back to "know which tool, call it", which is exactly what it already is everywhere else.

The case against is not a matter of scope, and stating it as scope would understate it.
This is not the same trade as GitLab.
`glab` already had merge powers when Firstmate adopted it, so calling it cost nothing in blast radius that was not already being spent.
`gerrit-axi` is safe *by construction*, and its safety is enforced rather than asserted - the read-only property is a test in its own suite, not a convention in its documentation.
Giving it publish and submit powers does not extend a capability it already has; it removes the property that makes it safe to call from an autonomous agent without a confirmation step.
The tool that cannot vote today would become the tool that can.

Two independent facts hold the boundary in section 4 today: Firstmate refuses, and the tool is incapable.
That change would reduce it to one.
A structural guarantee would become a procedural one.
That is the trade to weigh, and it is the captain's call, not a detail of where code lives.

A middle position deserves weighing alongside the other two, because the shape glue does not need the dangerous half.
Publishing a change for review is reversible in a way submitting is not: a published change can be abandoned, and until someone votes, nothing has been claimed on anyone's behalf.
Publish powers without submit powers would let the shape mechanics move while leaving the attributed-approval boundary held by incapability rather than by policy alone.

The second open question - whether `gerrit-axi`'s deliberate read-only stance should be reconsidered at all, given it was built to fill this same gap - is the same question approached from the tool's end rather than from Firstmate's.
Answering either one answers most of the other, which is a reason to take them together rather than in sequence.

Whichever way that goes, one question is already open and is not touched by it.
The merge poll watches one change number, and a stack is several changes, so grouping them by topic is the obvious handle.
Topic membership is mutable on the server, which makes a watch keyed on a topic a watch keyed on something anyone with access can change out from under it.
That is a captain call and stays open here.

## Open questions

Each of these is argued above and settled nowhere.

1. Is the forge declared in the registry or detected from the project's origin? (Section 3.)
2. Do the stack-versus-squash mechanics live in Firstmate or in the forge tool? (Section 5.)
3. Should `gerrit-axi`'s read-only stance be reconsidered, and if so, does it gain publish powers, or publish and submit? (Sections 4 and 5.)
4. How is a stack watched, when the only natural grouping handle is mutable on the server? (Section 5.)
