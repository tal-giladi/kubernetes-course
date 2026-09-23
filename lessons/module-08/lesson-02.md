# 24 - CRDs, controllers and operators

*Module 08 - Mastery, lesson 2 of 3. Exercise 24 of 25.*

Every object you have used - Pod, Deployment, Ingress - is a record in etcd plus a
controller that reconciles it. **You can add your own kinds**, and once you do, your domain
objects get the same API, the same RBAC, the same `kubectl get`, the same watch semantics
and the same declarative workflow as everything built in. That is the extension model, and
it is why the ecosystem looks the way it does.

## Two halves, and only one of them is the CRD

A **CustomResourceDefinition** registers a new kind. That gets you storage, validation, a
REST endpoint, `kubectl get`, RBAC, and nothing else. Create a custom resource and
**absolutely nothing happens** - it is a row in a database with a schema.

A **controller** is the other half: a process that watches those objects and makes the
world match them. CRD + controller + operational knowledge is what people call an
**operator**.

    CRD          the noun - a schema and an endpoint
    controller   the verb - a loop that reconciles desired state to actual state
    operator     a controller that encodes how to *run* a specific thing

## Defining a kind

    apiVersion: apiextensions.k8s.io/v1
    kind: CustomResourceDefinition
    metadata:
      name: greetings.k8slab.dev          # MUST be <plural>.<group>
    spec:
      group: k8slab.dev
      scope: Namespaced                    # or Cluster
      names: { plural: greetings, singular: greeting, kind: Greeting, shortNames: [gr] }
      versions:
        - name: v1alpha1
          served: true
          storage: true                    # exactly one version is the storage version
          subresources:
            status: {}                     # splits spec and status into separate endpoints
          schema:
            openAPIV3Schema: { ... }
          additionalPrinterColumns:
            - { name: Message, type: string, jsonPath: .spec.message }

The **OpenAPI v3 schema** is not optional decoration - it is your validation, your
defaulting, and what `kubectl explain greeting.spec` reads. `required`, `minimum`,
`maxLength`, `enum`, `default`, and `x-kubernetes-validations` (CEL expressions, for rules
that span fields) all work. Anything not in the schema is **pruned silently** - a typo in a
field name means your value is dropped, not rejected, which is a genuinely nasty first
experience.

The **status subresource** matters more than it looks: with it, `status` is a separate
endpoint. Users write `spec`, controllers write `status`, and a controller's status update
cannot accidentally clobber a user's spec change. It is also what makes
`kubectl scale --subresource=status` and `metadata.generation` tracking work.

## The reconcile loop

A controller is not an event handler. It is a **level-triggered loop**:

    for ever:
      observe the desired state (the custom resource)
      observe the actual state (the ConfigMaps, Pods, whatever it owns)
      make one converging change
      write status

This has to be true because events get lost, controllers restart, and the same event may
arrive twice. So the loop must be **idempotent** and must work from current state alone,
never from "what just changed". A controller that only reacts to events will drift the
first time it misses one.

**Owner references** are the other half of the pattern. When a controller creates a
ConfigMap for a Greeting, it stamps:

    ownerReferences:
      - apiVersion: k8slab.dev/v1alpha1
        kind: Greeting
        name: shalom
        uid: <the Greeting's uid>

and the built-in garbage collector deletes the ConfigMap when the Greeting goes. You do not
write cleanup code; you declare ownership. (`finalizers` are for the cases where you must
do something *outside* the cluster before an object may be deleted.)

Real controllers are written in Go with controller-runtime and scaffolded by Kubebuilder or
the Operator SDK, which give you the informer caches, work queues and rate limiting. You
can write one in any language - and you are about to write one in nine lines of shell,
because the *shape* is the lesson, not the SDK.

## Where you already rely on this

cert-manager (`Certificate`, `Issuer`), Prometheus Operator (`ServiceMonitor`,
`PrometheusRule`), Argo CD (`Application`), Istio, Crossplane, the CSI drivers, and every
managed-database operator. `kubectl api-resources` on a real cluster is mostly CRDs.

## Do this

In namespace `lesson-24`:

1. Apply the CRD in `lab/solutions/24/crd.yaml`, then look at what you just gained:

       kubectl apply -f lab/solutions/24/crd.yaml
       kubectl get crd greetings.k8slab.dev
       kubectl api-resources | grep greetings
       kubectl explain greeting.spec

   A brand-new kind, with documentation, in one file.

2. Prove the schema is real. Try an invalid object first:

       kubectl -n lesson-24 apply -f - <<'EOF'
       apiVersion: k8slab.dev/v1alpha1
       kind: Greeting
       metadata: { name: bad, namespace: lesson-24 }
       spec: { replicas: 99 }
       EOF

   PowerShell has no heredoc; the equivalent is a here-string, and it is the same idea -
   YAML on stdin, no temporary file:

       @'
       apiVersion: k8slab.dev/v1alpha1
       kind: Greeting
       metadata: { name: bad, namespace: lesson-24 }
       spec: { replicas: 99 }
       '@ | kubectl -n lesson-24 apply -f -

   The closing `'@` has to sit at the very start of its line with nothing in front of it.
   Single quotes mean literal, like `<<'EOF'`; `@"` ... `"@` would expand `$variables`.

   Rejected: `replicas` above maximum, and `message` is required. The API server enforced
   your rules with no code on your side.

   Now try one with a typo'd field and watch it be **accepted**:

       spec: { message: "hi", mesage: "typo" }
       kubectl -n lesson-24 get greeting <name> -o yaml     # `mesage` is simply gone

   Pruned, silently. Remember that when a field you set "does nothing".

3. Create two valid Greetings (`lab/solutions/24/greetings.yaml`):

       shalom      message: "shalom from a CRD"
       boker-tov   message: "boker tov"

       kubectl -n lesson-24 get greetings
       kubectl -n lesson-24 get gr        # the shortName works too

   Note the custom MESSAGE column - `additionalPrinterColumns` at work. And note that
   **nothing else happened**. No Pod, no ConfigMap. It is a row in etcd.

4. Now supply the missing half. `lab/solutions/24/controller.sh` is a reconcile loop -
   read it first, it is short:

       bash lab/solutions/24/controller.sh --once

   It lists Greetings, creates a ConfigMap per Greeting with an owner reference, and writes
   `status.configMapName` back through the status subresource. Then:

       kubectl -n lesson-24 get cm
       kubectl -n lesson-24 get greetings -o wide
       kubectl -n lesson-24 get cm greeting-shalom -o jsonpath='{.metadata.ownerReferences}'

5. See the loop's two defining properties:

       # idempotent: running it again changes nothing
       bash lab/solutions/24/controller.sh --once

       # level-triggered: break the world, and it repairs it from current state
       kubectl -n lesson-24 delete cm greeting-shalom
       bash lab/solutions/24/controller.sh --once
       kubectl -n lesson-24 get cm

   No event was delivered to anything. The loop simply observed that reality did not match
   desire and fixed it. That is the whole model.

6. And see garbage collection do the cleanup you never wrote:

       kubectl -n lesson-24 create -f - <<'EOF'
       apiVersion: k8slab.dev/v1alpha1
       kind: Greeting
       metadata: { name: temporary, namespace: lesson-24 }
       spec: { message: "delete me" }
       EOF
       bash lab/solutions/24/controller.sh --once

   (In PowerShell, the same here-string form as above. The controller itself is a bash
   script - run it with Git Bash: `& "C:\Program Files\Git\bin\bash.exe"
   lab/solutions/24/controller.sh --once`, not the `bash` on your PATH, which is WSL.)
       kubectl -n lesson-24 get cm | grep temporary
       kubectl -n lesson-24 delete greeting temporary
       kubectl -n lesson-24 get cm | grep temporary || echo "gone - collected via ownerReferences"

   Leave `shalom` and `boker-tov` in place, reconciled, for the checker.

## Hints

- The CRD's `metadata.name` must be exactly `<plural>.<group>` or the API server rejects it.
- After applying a CRD, wait a second before creating instances -
  `kubectl wait --for=condition=Established crd/greetings.k8slab.dev`.
- To write `status` you must PATCH the `/status` subresource:
  `kubectl patch greeting X --subresource=status --type=merge -p '{"status":{...}}'`.
- If your custom column is empty, check the `jsonPath` - it is evaluated against the whole
  object, so it starts with `.spec` or `.status`.

## Solution

See `lab/solutions/24/`.
