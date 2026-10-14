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
curl localhost:8080       # Hello World !!! (local)
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

## 5. Déployer l'application avec les fichiers YAML (recommandé)

Le dossier `k8s/` décrit l'application de façon déclarative :

| Fichier | Contenu |
| --- | --- |
| `k8s/deployment.yaml` | **Deployment** `hello-world` : image, port 8080, health checks, ressources, sécurité. L'annotation `image.openshift.io/triggers` le redéploie à chaque nouvelle image de l'ImageStream. |
| `k8s/service.yaml` | **Service** `hello-world` sur le port 8080 |
| `k8s/route.yaml` | **Route** `hello-world` en HTTPS (edge) ; le HTTP est redirigé vers HTTPS |

L'image est référencée par `image-registry.openshift-image-registry.svc:5000/hello/hello-world:latest`. Si ton projet ne s'appelle pas `hello`, remplace `hello` dans `k8s/deployment.yaml`.

```bash
oc apply -f k8s/
oc get deploy,svc,route,pods
oc rollout status deploy/hello-world
```

Pour modifier la configuration (replicas, ressources, probes…), édite les fichiers puis relance `oc apply -f k8s/`. Pour voir ce qui va changer avant d'appliquer : `oc diff -f k8s/`.

Si l'application a déjà été déployée avec `oc new-app` (section 6), supprime d'abord ces ressources, car le Deployment créé par `new-app` utilise un autre sélecteur de labels, qui ne peut pas être modifié :

```bash
oc delete deploy,svc,route hello-world
oc apply -f k8s/
```

## 6. Alternative : déployer avec les commandes `oc`

Cette méthode, plus rapide pour un test, n'est pas versionnée dans Git. Ne pas la combiner avec la section 5.

```bash
oc new-app hello-world
oc create route edge hello-world --service=hello-world --port=8080
oc get deploy,svc,route,pods
```

- `oc new-app` crée un **Deployment** `hello-world`, redéployé automatiquement à chaque nouvelle image de l'ImageStream, et un **Service** `hello-world` sur le port 8080, celui déclaré par `EXPOSE` dans le Dockerfile.
- `oc create route edge` crée une **Route** : le HTTPS est terminé sur le routeur OpenShift, puis le trafic est transmis en HTTP au pod. Pour une route en HTTP simple, utiliser plutôt `oc expose svc/hello-world`.

Les health checks ne sont pas configurés par `oc new-app` : voir la section 8.

## 7. Vérifier

```bash
HOST=$(oc get route hello-world -o jsonpath='{.spec.host}')
curl https://$HOST                         # Hello World !!! (local)
curl https://$HOST/actuator/health         # {"status":"UP",...}
```

Si le certificat du cluster est auto-signé, ajouter `-k` à `curl`.

## 8. Ajouter les health checks (déploiement avec les commandes `oc` uniquement)

Avec ces probes, OpenShift redémarre un pod bloqué et n'envoie du trafic qu'aux pods prêts. Avec les fichiers YAML (section 5), elles sont déjà définies dans `k8s/deployment.yaml`.

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

Avec les fichiers YAML, `oc scale`, `oc set env` et `oc set resources` modifient le cluster mais pas les fichiers : le prochain `oc apply -f k8s/` annule ces changements. Pour les garder, reporte-les dans `k8s/deployment.yaml`.

### Exporter la configuration en YAML

Afficher les YAML du Deployment, du Service et de la Route tels qu'ils existent dans le cluster :

```bash
oc get deploy,svc,route hello-world -o yaml
oc get deploy,svc,route hello-world -o yaml > hello-world-export.yaml   # sauvegarde dans un fichier
```

Ces YAML servent de point de départ pour passer au mode déclaratif (`oc apply -f`) puis à ArgoCD. Avant de les réutiliser, supprimer les champs ajoutés par le cluster : `status`, `metadata.uid`, `metadata.resourceVersion`, `metadata.creationTimestamp`, `metadata.managedFields`, ainsi que `spec.clusterIP` et `spec.clusterIPs` pour le Service.

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
| `ImagePullBackOff` | Image introuvable dans l'ImageStream, ou nom de projet incorrect dans l'image de `k8s/deployment.yaml` | `oc get is hello-world`, puis relancer `oc start-build`. Vérifier que le chemin `.../<projet>/hello-world:latest` correspond au projet courant (`oc project`). |
| `oc apply` échoue sur le Deployment (`field is immutable`) | Le Deployment a été créé avant par `oc new-app` | `oc delete deploy,svc,route hello-world`, puis `oc apply -f k8s/` |
| `CrashLoopBackOff` | L'appli s'arrête au démarrage | `oc logs <pod> --previous` |
| Pod redémarré en boucle après l'ajout des probes | La liveness échoue avant la fin du démarrage | Augmenter `--initial-delay-seconds`. |
| `Application is not available` sur la Route | Aucun pod prêt ou mauvais port | `oc get pods`, `oc describe route hello-world` (port 8080). |

## 12. Nettoyer

Supprimer seulement l'application, en gardant le projet :

```bash
oc delete -f k8s/                         # déploiement avec les fichiers YAML
oc delete all -l app=hello-world          # ou : déploiement avec oc new-app
oc delete bc/hello-world is/hello-world   # build et ImageStream
```

Supprimer tout le projet :

```bash
oc delete project hello
```
