# Recording plan and evidence gate

Use a captioned or narrated product walkthrough under three minutes. Start with the action, then explain the policy. Never display access tokens, provider configuration, shell history, or private connection files.

## Verified material

- Studio's same-input proof: production applicability changes from allowed to denied after publication, then back to allowed after rollback. The proof uses the same agent and input.
- A reviewer cannot activate policy. An administrator can.
- A real Nemotron Ultra plan and Super tool loop edited the disposable website and passed its Python check in Nebius Sandbox with networking disabled.
- The actual production request was denied. Nano recommended human approval; no approval request was created and no approval was granted.
- In an explicitly continued run, Nano selected staging. Signalbox authorized it and the worker published the saved patch to the local filesystem. The published artifact digest matches the evidence.

## Current recording gate

The local worker-effect gate passed. `docs/RECOVERY-EVIDENCE.json` contains the sanitized execution ID and verified artifact digest. One approved additional Nano call was used; no additional Sandbox commands were needed. This proves a local staging filesystem effect, not a hosted production deployment.

The original model-generated narration says approval was pending. That is unsupported by the host records. Use the factual distinction above instead; preserve the raw model output as evidence of that limitation.

## Captured walkthrough

`demo/signalbox-evidence-walkthrough.mp4` is an 80-second walkthrough assembled from actual browser screenshots. It has a default English subtitle track and no audio. Enable captions if the player hides them; `demo/walkthrough.srt` is also provided. It explicitly identifies the saved run, recovery, and local effect. Nothing has been uploaded.

## Longer presentation sequence

0:00–0:20 — Open Governed actions. “An agent can propose a deployment. Signalbox independently decides whether that action is permitted.”

0:20–0:50 — Open the production denial. Show the decision and policy hash. “The agent edited a disposable website in Nebius Sandbox and passed its check. Its production request was refused.”

0:50–1:20 — Show policy editor and the saved activation/rollback proof. “Changing only the active policy changes the same action's decision. Tenant isolation and baseline safety remain in force. Reviewers cannot publish policies.”

1:20–1:55 — Show the follow-up Nano correction and staging transaction. Explain that the recorded run initially requested human review and was continued with an explicitly configured staging alternative. Do not disguise the continuation as an uninterrupted first attempt.

1:55–2:20 — Show worker success, the published file, and its digest. “Authorization, the database transaction, and the connector effect are separate records.”

2:20–2:40 — Close on the result. “Signalbox gives agents a constrained way to act without handing them downstream credentials. The decision and the effect remain inspectable.”

Record existing evidence as a walkthrough; do not fabricate terminal output or imply that prerecorded evidence is a new live inference call. Publication or upload is a separate step.

## Hosted follow-up

The application and worker have since been deployed and verified. [Hosted evidence](HOSTED-RELEASE-EVIDENCE.json) records a fresh staging transaction and matching public artifact, with no new model or Sandbox calls. The existing video still describes the local run; it is now also served at `/demo/recording/signalbox-evidence-walkthrough.mp4`.
