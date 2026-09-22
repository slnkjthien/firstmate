# Gerrit forge integration

This note is the design reasoning for giving Firstmate a forge axis, worked through Gerrit because Gerrit is the case that forces it.
It is written for whoever integrates a forge with Firstmate rather than for the operator of any one fleet, so it argues about axes, vocabulary, and ownership, and never about which projects should be registered how.
Where a question has been settled the decision is stated in the body rather than left standing as a question; the three that remain open are collected at the end.

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

### How the forge is known: detected, then proposed for confirmation

The binding is **detected from the project's origin and proposed at intake for confirmation**, rather than declared cold in the registry or inferred silently at use time.
Detection is what every other forge already gets for free, because the URL tells Firstmate what it is dealing with.
Confirmation is what stops a wrong guess from becoming a silent second source of truth, since a mis-detected forge produces a brief that is internally consistent and wrong.
Proposing it at intake also puts the signal where a pre-publication signal has to be, in the brief at scaffold time with no clone read and no network call, while keeping a human at the one point where the evidence can be misread.
The in-review delivery-mode design already takes that shape, treating a protocol fact such as an SSH remote on port 29418 or a `refs/for/<branch>` push target as good evidence to propose the binding while refusing to infer it later.

The tool with the broadest forge coverage in this stack corroborates detection, though more narrowly than it first appears to.
no-mistakes binds its provider by calling `DetectProvider(remoteURL)` across the six forges its `Provider` type names - GitHub, GitLab, Bitbucket, Azure DevOps, Forgejo and Gitea - and no project declares its forge anywhere in that scheme.
Only well-known hosts are recognised from the URL alone.
For a host it does not recognise, which is how Gerrit is nearly always deployed, it falls back to machine-local configuration keyed by host: SSH config, then whether the local `glab`, `gh` or `tea` CLI is logged in to that host, then a `FORGEJO_BASE_URL` environment variable, while its per-repository execution context resolves machine-local forge profiles.
What survives as corroboration is exactly one fact: no per-project declaration anywhere in the scheme, across six forges.

The same evidence also bears against detection.
Because it reads per-machine login state, one remote can resolve to different forges on two machines, or to none on a machine where the CLI is not logged in, and that is a genuine argument for declaring the forge rather than detecting it.
It does not overturn the decision, since confirmation at intake is where a misread is meant to be caught, but anyone relying on detection should know it is not purely structural.

#### Could the tool declare its own semantics instead?

That settles where the binding comes from without settling whether a project-level binding is needed at all.
Suppose the forge tool answered the question itself: a `forge-type` subcommand on `gerrit-axi` returning `change`, where a GitHub or GitLab tool would return `branch`.
The appeal is real, and the reasoning behind it is sound as far as it goes.
The origin URL already selects which tool to call, the tool then declares its own semantics, and no project ever carries an annotation that can drift from its remote.

Be precise about what that removes and what it does not.
It removes the per-project declaration, which is the part capable of disagreeing with reality.
It does not remove the mapping, because something must still get from a remote URL to the right tool before any tool can be asked anything, and that something is Firstmate.
The question is therefore not whether Firstmate holds forge knowledge, since it does either way, but whether it holds one thin host-pattern mapping for the whole fleet or one annotation per project.

Framed that way the mapping looks like the better shape, for a reason that has nothing to do with Gerrit.
A host pattern is written once and is then either wrong for every project on that host or right for every project on it, which is a failure mode that announces itself on first use.
A per-project annotation is written once per project and can be wrong on exactly one of them, which is the failure mode that does not announce itself at all.
The cost is a round trip, because asking the tool means running it, so the answer stops being available at scaffold time without a call, which is the property the pre-publication signal needed to begin with.
Caching the answer recovers that and reintroduces, in smaller form, the staleness the annotation had.

This remains open, and two decisions in section 5 name it as their dependency.

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
The teardown test and the review diff each already have a fallback that reasons about content or about the local branch, and on Gerrit the fallback is not a fallback, it is the only path.
The prune has no fallback at all: a `refs/for/<branch>` push creates no upstream tracking ref, so nothing ever reads `[gone]`, the prune never fires, and `fm/<id>` branches accumulate locally after teardown.
That raises the stakes on the content leg of the landed-work test specifically, since it becomes the sole proof that unlanded work is not about to be discarded.
This is also a property of Gerrit.

**No tool available today can submit.**
`gerrit-axi` is read-only by construction.
Its README states the boundary - "v0.1 is read-only. It never votes, replies, sets reviewers or topics, submits, abandons, or pushes. Every operation is a query." - and its own test suite enforces it by grepping for mutating REST verbs and mutating SSH subcommands.
Its entire surface is `status`, `show`, `comments`, and `auth status`.
But the refusal Firstmate is designed to carry is stated as policy rather than capability, and like the registry forge field it is in review rather than current behavior.
Today a Gerrit change URL is rejected only because `bin/fm-pr-lib.sh` cannot parse it into a provider identity, which is a capability limit and not a policy.
What the designed refusal protects is the decisive vote rather than the submit: a submit only succeeds once someone has recorded a `Code-Review+2`, and that vote is a positive attributed claim that a named human approved, read as such by colleagues and by any audit of the repository.
A server that permits self-approval is exactly what makes this a boundary Firstmate chooses rather than one it merely runs into.

So the first two are Gerrit's shape, and the third is the current toolchain plus a deliberate policy that is designed but not yet landed.
Only the toolchain half could be removed by writing code, and until the policy lands the toolchain half is the only half that exists; whether it should be removed is section 5.

## 5. Where responsibility sits: Firstmate or the forge tool

Start from the division that already works.
For GitLab, Firstmate knows which tool and calls it, the tool knows the forge, and Firstmate owns none of the mechanics.
Not the artifact's creation, not its URL shape beyond parsing it back into an identity, not the merge command.
The forge property Firstmate carries for GitLab is no property at all, only a tag read off a URL.

The question this raises for Gerrit is whether the stack-versus-squash glue belongs on the same side of that line.
**It does: the shape mechanics live in the forge tool.**
That decision carries an open dependency, named in section 3, because a tool that declares its own semantics and a tool that merely executes them are different amounts of tool.
It was also taken before a third candidate home was on the board, and that candidate is argued below.

The case for it is that this is forge mechanics through and through.
Producing a stack of changes under a topic means giving each commit a `Change-Id`, pushing once to `refs/for/<branch>` with a topic option, and reasoning about the parent chain that makes the stack a stack.
None of that is a Firstmate concept, and every line of it Firstmate writes is a line Firstmate maintains on behalf of one forge.
Move it and Firstmate's job shrinks back to "know which tool, call it", which is exactly what it already is everywhere else.

### Does the pipeline need to know?

The strongest objection is that the no-mistakes pipeline, not Firstmate, is what runs at delivery time, so hiding forge mechanics inside a forge tool only helps if the pipeline can call that tool.
The objection is right about the mechanism.
no-mistakes does own publication: `push`, `pr`, and `ci` are its own pipeline steps, sitting alongside `review`, `test`, `document`, and `lint`, and a run reports each of them independently.

It does not defeat the answer, because on a Gerrit project those are precisely the steps that do not run.
The in-review delivery design has a `forge=gerrit` worker pass `--skip push,pr,ci` on every run and skip nothing else, keeping `review`, `test`, `document`, and `lint` as the whole point of the run.
Publication then moves out of the pipeline entirely: the worker stops at a ready branch, and Firstmate pushes it to the review server.
So the caller of the forge tool is Firstmate or the worker, never no-mistakes, and the pipeline never has to know `gerrit-axi` exists.
The objection's premise holds everywhere the pipeline publishes, and a Gerrit project is the one place it does not.

That answer is contingent, though, and reading it as structural would be a mistake.
The pipeline can be kept ignorant of the forge tool only because it has no Gerrit support to exercise: its `Provider` type names six forges and none of them is Gerrit, so its publication steps could not work against one.
The skip exists because those steps cannot function, not because publication belongs outside the pipeline on principle.
Add Gerrit to that provider set and the skip disappears, the pipeline publishes natively, and the question of who calls the forge tool reopens.

### What powers the tool needs

`gerrit-axi` is read-only by construction today, so the shape mechanics cannot move into it as it stands.
**It gains publish and submit powers**, under the same open dependency.

Getting the risk boundary right matters more than the decision, because the intuitive cut is the wrong one.
The natural reading, and the one recommended earlier in this design, puts the boundary between publish and submit: publishing is reversible, submitting is not, so grant publish and withhold submit.
Evidence supersedes that reading rather than merely outweighing it.
Gerrit computes submittability on the server, independently of who asks.
A change observed on a live server with its `Verified` label satisfied and every other gate passed still reports `submittable: false` and `blocked_on: Code-Review` for as long as no human has voted, and a submit call against it fails there.
Granting submit therefore moves much less risk than it appears to, because what is being granted is the ability to ask a server that will refuse.

The hazard concentrates one step earlier, in **decisive voting**.
A tool that can record `Code-Review+2` lets an agent manufacture the approval and then submit legitimately against it, and at that point every gate really is satisfied and nothing anywhere records that no human ever approved.
That is exactly the attributed-claim problem section 4 identifies, a positive claim that a named human approved, read as such by colleagues and by any audit of the repository.
It is also why the server permitting self-approval makes this a policy boundary rather than a capability limit: the server will not stop it, so something else has to.
In the designed end state two independent facts hold that line: Firstmate refuses, and the tool is incapable.
Today only the second is real, because Firstmate's policy refusal is unlanded.
That raises the stakes on relaxing `gerrit-axi` rather than lowering them: granting it decisive-vote powers now would remove the only guard that currently exists, not the second of two.

So the trade is not publish against submit.
It is publish and submit on one side, where the server itself is the enforcement, against decisive voting on the other, where nothing is.
A non-decisive `Code-Review+1` sits between them and deserves to be considered on its own terms, since it records an opinion without satisfying the gate.

### A third place the mechanics could live

Two homes for the shape mechanics have been weighed so far, Firstmate and a forge tool Firstmate calls.
There is a third, and it deserves arguing as a peer rather than a footnote, because it was not in view when the choice above was made.
no-mistakes already carries a multi-forge abstraction, with a `Provider` type, per-provider packages, and a per-repository execution context, and Gerrit support could be contributed there natively following the pattern its six existing providers follow.

The case for it is that it removes part of a duplication the other two options create.
If the pipeline gains Gerrit support while Firstmate also has its own forge tool, `Change-Id` handling, magic-ref pushes, topic stacks and submittability are each implemented independently on both sides.
Contributing upstream takes the publication mechanics off Firstmate's side: `Change-Id` handling on push and magic-ref publication would live in a pipeline that already knows six forges, rather than in a seventh integration beside it, and that abstraction is both more mature than a new one and shared rather than ours alone.

It removes only that part.
The pipeline never merges: its host interface finds, creates and updates pull requests and reads their state, checks and mergeability, and its `ci` step only verifies that a merge happened.
Merging, the merge poll and the stack watch below stay with Firstmate wherever publication lives, so Firstmate still needs a Gerrit-aware tool, and submittability and topic-stack reasoning still exist on both sides under this option.
It shrinks the forge tool Firstmate needs rather than replacing it.

The case against is a dependency the other two options do not carry.
Gerrit support upstream lands when that project decides it lands, at whatever scope its maintainers accept, and a forge needed now cannot be scheduled against someone else's roadmap.
A tool under our own hand ships when we ship it.
The honest reading is that the upstream route removes the publication half of the duplication, not all of it, and pays for that with a schedule we do not control, so it is worth taking only if the timing is acceptable and sharing publication is worth that wait.

### Watching a stack

The merge poll watches one change number, and a stack is several changes, so grouping them by topic is the obvious handle.
Topic membership is mutable on the server, though, so a watch keyed on a topic alone is keyed on something anyone with access can change out from under it.

The resolution is to **pin the membership and detect growth rather than follow it**.
Record the change numbers the stack had when the watch was armed, keep watching exactly those, and re-read the topic only to notice that it no longer matches.
A change that appears or disappears is then reported as a change to the thing being watched, instead of being absorbed silently into it.
That keeps the watch's subject fixed, which is what makes a merged verdict mean anything, while still surfacing the case a bare pin would hide: someone adding a change to the stack after the watch was armed.

## Open questions

Three remain.
Both section 5 decisions name the first as their dependency.

1. Would a `forge-type` subcommand on the forge tool remove the need for a project-level forge binding, and is one host-pattern mapping held in Firstmate materially better than one annotation per project? (Section 3.)
2. Should the forge tool be able to vote at all, and if so, only non-decisively? A decisive `Code-Review+2` is where the attributed-approval hazard actually sits, not at submit. (Section 5.)
3. Should Gerrit publication be contributed upstream to no-mistakes, narrowing the forge tool to merging, the merge poll and the stack watch? That option was not in view when the decision was made. It removes only the duplicated publication mechanics, since submittability and topic-stack reasoning stay on both sides, and it ties a forge needed now to an upstream roadmap. (Section 5.)
