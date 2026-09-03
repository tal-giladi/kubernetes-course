# 11 - ConfigMaps and Secrets

Configuration does not belong in your image. If it did, "same artifact, three
environments" would be impossible and every config change would be a rebuild. Kubernetes
gives you two objects for it, which are the *same object* with different social rules:
**ConfigMap** for non-sensitive data, **Secret** for sensitive data.

## They are key/value, and the values can be files

    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: app-config
    data:
      GREETING: shalom              # a scalar
      app.conf: |                   # a whole file
        timeout = 30
        retries = 3
    binaryData:
      logo.png: <base64>            # for things that are not UTF-8

Size limit: **1 MiB** for the whole object, because it lives in etcd. ConfigMaps are not a
file server; a 40 MB model file does not go here.

## Four ways to consume one

**1. One key into one env var** - explicit, and the one to prefer:

    env:
      - name: GREETING
        valueFrom:
          configMapKeyRef: { name: app-config, key: GREETING }

**2. Every key as env vars** - convenient, and quietly dangerous: you cannot tell from the
Pod spec what the container receives, and a new key in the ConfigMap silently becomes a new
env var:

    envFrom:
      - configMapRef: { name: app-config }
        prefix: APP_          # optional, and a good idea

**3. As files in a volume** - the flexible one:

    volumes:
      - name: config
        configMap:
          name: app-config
          items:                              # optional: pick and rename keys
            - key: app.conf
              path: app.conf
    ...
      volumeMounts:
        - name: config
          mountPath: /etc/hello
          readOnly: true

Each key becomes a file. What is actually mounted is a directory of symlinks into a
`..data` directory - which is how the kubelet swaps the whole set atomically.

**4. `subPath`** - mount a single file into a directory that already has other files:

    volumeMounts:
      - name: config
        mountPath: /etc/nginx/nginx.conf
        subPath: nginx.conf

The catch, and it is a big one: **a `subPath` mount never updates.** You get the value from
Pod start, forever.

## Updates: what refreshes and what does not

  - **Env vars: never.** They are set at container start. Change the ConfigMap and the
    running container keeps the old value until it is recreated.
  - **Volume mounts: yes**, within about a minute (kubelet sync period plus cache TTL) -
    *unless* you used `subPath`, or the ConfigMap is `immutable`.
  - Your application still has to *notice* the file changed. Most do not.

So the honest pattern is: treat config changes as deployments.

    kubectl -n lesson-11 rollout restart deploy/hello

The tidier version is a **checksum annotation** on the Pod template
(`checksum/config: <sha of the configmap>`), which every Helm chart does: change the
config, the checksum changes, the template changes, and a rolling update happens
automatically. If you want a config that must never drift, mark the ConfigMap
`immutable: true` and give the new one a new name.

## Secrets: base64 is not encryption

A Secret looks like a ConfigMap with `stringData` on the way in and base64 `data` on the
way out. **Base64 is an encoding, not a protection.** Anyone who can read the Secret can
read the value:

    kubectl -n lesson-11 get secret db-creds -o jsonpath='{.data.DB_PASSWORD}' | base64 -d

What actually protects a Secret:

  - **RBAC** - who may `get` secrets in this namespace (lesson 19). This is the real
    control, and by default far too many ServiceAccounts have it.
  - **Encryption at rest** - an `EncryptionConfiguration` on the API server so etcd holds
    ciphertext. Off by default in many distributions; on in most managed ones.
  - **Not putting them in the cluster at all** - external stores (Azure Key Vault, AWS
    Secrets Manager, Vault) projected in by the Secrets Store CSI driver, or
    External Secrets Operator syncing them. This is where serious setups land, and it is
    exactly what your production services already do with Key Vault.
  - Prefer **file mounts over env vars** for secrets: env vars leak into crash dumps, `ps`
    output, child processes and logging middleware that dumps the environment.

Types matter to consumers: `Opaque` (default), `kubernetes.io/tls` (needs `tls.crt` and
`tls.key`), `kubernetes.io/dockerconfigjson` (image pull), `kubernetes.io/service-account-token`.

There is also **`immutable: true`** for Secrets, and it is worth using: it stops
accidental edits and lets the kubelet skip watching them, which measurably reduces API
server load in big clusters.

## Do this

In namespace `lesson-11`, using the `hello:1.1.0` image from lesson 06:

1. A ConfigMap `app-config` with:

       GREETING: shalom
       app.conf: |
         timeout = 30
         retries = 3

2. A Secret `db-creds` (Opaque) with `DB_PASSWORD=hunter2`.
3. A Deployment `hello`, 2 replicas, label `app=hello`, container `hello`, port 8080
   named `http`, consuming all three ways at once:

   - env `GREETING` from `configMapKeyRef` (app-config / GREETING)
   - env `DB_PASSWORD` from `secretKeyRef` (db-creds / DB_PASSWORD)
   - a volume mounting **the whole ConfigMap** read-only at `/etc/hello`

4. Confirm what arrived, using the app's own `/config` endpoint:

       kubectl -n lesson-11 exec deploy/hello -- wget -qO- http://127.0.0.1:8080/config

   You should see `GREETING=shalom`, `DB_PASSWORD=hunter2`, and the two files under
   `/etc/hello`.

5. Prove the update rules to yourself. Change the ConfigMap and wait a minute:

       kubectl -n lesson-11 patch cm app-config -p '{"data":{"GREETING":"hello-again"}}'
       sleep 70
       kubectl -n lesson-11 exec deploy/hello -- wget -qO- http://127.0.0.1:8080/config

   The **file** under `/etc/hello` now says `hello-again`. The **environment variable**
   still says `shalom`. Same ConfigMap, same Pod, two different answers - that difference
   is this lesson.

   Then make the env var catch up, and put the value back:

       kubectl -n lesson-11 patch cm app-config -p '{"data":{"GREETING":"shalom"}}'
       kubectl -n lesson-11 rollout restart deploy/hello
       kubectl -n lesson-11 rollout status deploy/hello

6. Look at what a Secret really is, and at where it is *not* hidden:

       kubectl -n lesson-11 get secret db-creds -o yaml
       kubectl -n lesson-11 get secret db-creds -o jsonpath='{.data.DB_PASSWORD}' | base64 -d ; echo
       kubectl -n lesson-11 describe pod -l app=hello | grep -A3 Environment

## Hints

- `kubectl -n lesson-11 create cm app-config --from-literal=GREETING=shalom --from-file=app.conf`
  (create the local `app.conf` first), or write the YAML with a `|` block.
- `kubectl -n lesson-11 create secret generic db-creds --from-literal=DB_PASSWORD=hunter2`
- In YAML, `stringData:` takes plain text and the API server base64-encodes it for you.
  Do not hand-encode into `data:`.
- The volume needs both a `volumes:` entry (`configMap: {name: app-config}`) and a
  `volumeMounts:` entry on the container.

## Solution

See `lab/solutions/11/all.yaml`.
