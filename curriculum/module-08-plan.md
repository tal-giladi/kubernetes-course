# Module 08 plan - Mastery

**Lessons 23-25. Prerequisite: modules 01-07. Produces: a diagnosis routine, an
understanding of the extension model, and one complete application.**

## Objectives

1. Diagnose an unfamiliar failure from the cluster alone, in a fixed order, without
   guessing.
2. Explain how every operator you will ever install works, and write the smallest possible
   controller.
3. Assemble a production-shaped application using every mechanism in the course, and prove
   each property rather than assume it.

## Lessons

### 23 - The debugging playbook
- **Concept**: the four-command order and the four columns to read first; the symptom
  table - `Pending`, `ImagePullBackOff`, `CrashLoopBackOff`, `CreateContainerConfigError`,
  `Running 0/1`, `Terminating`, `OOMKilled`, empty endpoints, 404 vs 503, timeouts;
  `logs --previous`; ephemeral containers via `kubectl debug` for distroless images; the
  cluster-level checks worth doing when *everything* is broken; where `kubectl logs` stops
  and real observability starts.
- **Example**: exit code 137 vs 143 vs 1, and what each tells you about who did the killing.
- **Practice**: four deliberately broken Deployments - a bad tag, a mistyped Service
  selector, a case-wrong ConfigMap key and an impossible CPU request. Diagnose from the
  cluster, write down the theory, then fix in place. Deleting and recreating is against the
  rules.
- **Summary**: the symptom names the cause; theorising before `describe` wastes the hour.

### 24 - CRDs, controllers and operators
- **Concept**: CRD as schema plus endpoint and *nothing else*; the OpenAPI schema as
  validation, defaulting and documentation; silent pruning of unknown fields; the status
  subresource and why it exists; the level-triggered reconcile loop and idempotency;
  owner references replacing cleanup code; finalizers for out-of-cluster work; where real
  controllers come from (controller-runtime, Kubebuilder) and where you already depend on
  them.
- **Example**: creating a custom resource and watching absolutely nothing happen.
- **Practice**: define a `Greeting` kind with validation, printer columns and status;
  create instances; then run a nine-line shell reconcile loop, prove it is idempotent,
  delete what it made and watch it rebuild, and delete a Greeting to watch garbage
  collection remove the child.
- **Summary**: the CRD is the noun; the controller is the verb; the loop reads state, never
  events.

### 25 - Capstone
- **Concept**: nothing new. Integration is the skill.
- **Practice**: namespace with `restricted` enforcement, dedicated ServiceAccount with no
  token, ConfigMap and Secret, a fully probed and constrained Deployment with topology
  spread and a preStop hook, a Service, a StatefulSet with per-Pod storage behind a headless
  Service, Ingress with TLS, HPA, PDB, and three NetworkPolicies. Then verified: a live HTTP
  and HTTPS request through the real ingress path, config delivery, StatefulSet identity
  across a delete, a zero-downtime rolling update measured with a curl loop, a blocked
  unlabelled Pod, and a bad image that does not take the service down.
- **Summary**: five reflection questions whose answers are mostly not more YAML.

## Dependencies

23 can be attempted any time after module 04, but lands hardest after 05-06 when the
learner has seen each failure mode legitimately. 24 is independent. 25 requires everything,
including the ingress-nginx and metrics-server installs from lessons 10 and 17.

## Misconceptions

- "I will read the manifest to find the bug." (In production you will not have it. Work the
  cluster.)
- "A CRD adds behaviour." (It adds a table.)
- "A controller reacts to events." (It reconciles state. Events are only a hint to look.)
- "It applied cleanly, so it works." (Every verification step in lesson 25 exists because
  something can apply cleanly and still be wrong.)
