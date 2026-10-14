# Déployer hello-world sur OpenShift

Ce guide déroule toutes les commandes pour construire, déployer, exposer, mettre à jour et supprimer l'application `hello-world` sur OpenShift.

Noms utilisés dans tout le guide :

| Élément | Nom |
| --- | --- |
| Projet (namespace) | `hello` |
| BuildConfig / ImageStream / Deployment / Service / Route | `hello-world` |

Toutes les commandes se lancent depuis la racine du projet.

## 1. Prérequis

- La CLI `oc` ([téléchargement](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/)), ou `brew install openshift-cli` sur macOS
- Un compte sur le cluster OpenShift qui a le droit de créer un projet

Se connecter au cluster. Le token se récupère dans la console web, menu utilisateur > *Copy login command* :

```bash
oc login --token=<TOKEN> --server=https://api.<cluster>:6443
oc whoami                 # utilisateur connecté
oc whoami --show-server   # cluster ciblé
```

## 2. Tester en local (optionnel)

Avec Maven et Java 21 :

```bash
mvn test                  # tests unitaires
mvn spring-boot:run
curl localhost:8080       # Hello World
```

Avec Docker ou Podman (même image que celle construite par OpenShift) :

```bash
docker build -t hello-world .
docker run --rm -p 8080:8080 hello-world
curl localhost:8080
curl localhost:8080/actuator/health
```

## 3. Créer le projet

```bash
oc new-project hello
oc project                # vérifie le projet courant
```

Pour revenir plus tard sur ce projet : `oc project hello`.

## 4. Construire l'image dans OpenShift

On crée un BuildConfig **binaire** de stratégie **Docker**. OpenShift reçoit le dossier local, exécute le `Dockerfile` et pousse l'image dans son registre interne, dans l'ImageStream `hello-world`.

```bash
oc new-build --binary --strategy=docker --name=hello-world
oc start-build hello-world --from-dir=. --follow
```

Vérifier :

```bash
oc get bc                 # BuildConfig
oc get builds             # hello-world-1 doit être Complete
oc get is                 # ImageStream hello-world
oc describe is hello-world
```

## 5. Déployer l'application

```bash
oc new-app hello-world
```

`oc new-app` crée :

- un **Deployment** `hello-world`, redéployé automatiquement à chaque nouvelle image de l'ImageStream ;
- un **Service** `hello-world` sur le port 8080, celui déclaré par `EXPOSE` dans le Dockerfile.

Vérifier :

```bash
oc get deploy,svc,pods
oc rollout status deploy/hello-world
```

## 6. Exposer l'application (Route)

Une route **edge** termine le HTTPS sur le routeur OpenShift, puis transmet le trafic en HTTP au pod :

```bash
oc create route edge hello-world --service=hello-world --port=8080
oc get route hello-world
```

Pour une route en HTTP simple, utiliser plutôt `oc expose svc/hello-world`.

## 7. Vérifier

```bash
HOST=$(oc get route hello-world -o jsonpath='{.spec.host}')
curl https://$HOST                         # Hello World
curl https://$HOST/actuator/health         # {"status":"UP",...}
```

Si le certificat du cluster est auto-signé, ajouter `-k` à `curl`.

## 8. Ajouter les health checks

Avec ces probes, OpenShift redémarre un pod bloqué et n'envoie du trafic qu'aux pods prêts.

```bash
oc set probe deploy/hello-world --liveness \
  --get-url=http://:8080/actuator/health/liveness \
  --initial-delay-seconds=20 --period-seconds=10

oc set probe deploy/hello-world --readiness \
  --get-url=http://:8080/actuator/health/readiness \
  --initial-delay-seconds=10 --period-seconds=5

oc describe deploy/hello-world | grep -iE 'liveness|readiness'
```

## 9. Mettre à jour l'application

Après une modification du code, relancer un build. Le trigger d'image redéploie l'appli automatiquement :

```bash
oc start-build hello-world --from-dir=. --follow
oc rollout status deploy/hello-world
```

Revenir à la version précédente :

```bash
oc rollout history deploy/hello-world
oc rollout undo deploy/hello-world
```

## 10. Exploiter

```bash
oc logs -f deploy/hello-world                    # logs de l'appli
oc scale deploy/hello-world --replicas=2         # 2 instances
oc rollout restart deploy/hello-world            # redémarrage progressif
oc set env deploy/hello-world JAVA_TOOL_OPTIONS="-Xmx256m"   # variable d'environnement
oc set resources deploy/hello-world \
  --requests=cpu=100m,memory=256Mi --limits=memory=512Mi     # ressources
oc rsh deploy/hello-world                        # shell dans un pod
oc get all -l app=hello-world                    # toutes les ressources de l'appli
```

## 11. Dépanner

```bash
oc logs -f bc/hello-world                        # logs du dernier build
oc get pods                                      # état des pods
oc describe pod <nom-du-pod>                     # détails et événements d'un pod
oc logs <nom-du-pod> --previous                  # logs du conteneur avant son crash
oc get events --sort-by=.lastTimestamp           # derniers événements du projet
```

| Symptôme | Cause probable | Que faire |
| --- | --- | --- |
| Build en `Failed` | Erreur Maven ou image de base inaccessible | `oc logs bc/hello-world`. Vérifier que le cluster peut accéder à Docker Hub (`maven`, `eclipse-temurin`). |
| `ImagePullBackOff` | Image introuvable dans l'ImageStream | `oc get is hello-world`, puis relancer `oc start-build`. |
| `CrashLoopBackOff` | L'appli s'arrête au démarrage | `oc logs <pod> --previous` |
| Pod redémarré en boucle après l'ajout des probes | La liveness échoue avant la fin du démarrage | Augmenter `--initial-delay-seconds`. |
| `Application is not available` sur la Route | Aucun pod prêt ou mauvais port | `oc get pods`, `oc describe route hello-world` (port 8080). |

## 12. Nettoyer

Supprimer seulement l'application, en gardant le projet :

```bash
oc delete all -l app=hello-world
oc delete bc/hello-world is/hello-world
```

Supprimer tout le projet :

```bash
oc delete project hello
```
